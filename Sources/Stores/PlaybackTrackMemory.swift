import Foundation

/// Explicit episode choices are remembered only with account opt-in. Raw source indexes
/// never cross an item boundary; unavailable or ambiguous choices fall back to defaults.
@MainActor
final class PlaybackTrackMemory {
    static let shared = PlaybackTrackMemory()
    private let defaults: UserDefaults
    /// Persist descriptive identity only; indexes and codec details belong to one source.
    private struct SemanticTrackPreference: Codable {
        let displayTitle: String?
        let language: String?
        let title: String?
        let type: MediaStreamKind?
        let isForced: Bool?
        let isHearingImpaired: Bool?
        let isExternal: Bool?

        init(_ stream: MediaStreamInfo) {
            displayTitle = stream.displayTitle
            language = stream.language
            title = stream.title
            type = stream.type
            isForced = stream.isForced
            isHearingImpaired = stream.isHearingImpaired
            isExternal = stream.isExternal
        }

        var stream: MediaStreamInfo {
            MediaStreamInfo(
                displayTitle: displayTitle,
                language: language,
                title: title,
                type: type,
                isForced: isForced,
                isHearingImpaired: isHearingImpaired,
                isExternal: isExternal
            )
        }
    }

    private struct Choice: Codable {
        let itemID: String
        let audio: SemanticTrackPreference?
        let subtitle: SemanticTrackPreference?
        let subtitlesOff: Bool
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(_ scope: AccountScope) -> String {
        let identity = (try? JSONEncoder().encode([scope.serverID, scope.userID])) ?? Data()
        return "playbackTrackMemory." + identity.base64EncodedString()
    }

    func isEnabled(scope: AccountScope) -> Bool {
        defaults.bool(forKey: key(scope) + ".enabled")
    }

    func setEnabled(_ enabled: Bool, scope: AccountScope) {
        defaults.set(enabled, forKey: key(scope) + ".enabled")
        if !enabled {
            defaults.removeObject(forKey: key(scope))
        }
    }

    func remember(item: MediaItem, source: MediaSource, selection: PlaybackStreamSelection, scope: AccountScope, audioExplicit: Bool = true, subtitleExplicit: Bool = true) {
        guard isEnabled(scope: scope), item.type == .episode, let id = item.id, let series = item.seriesID else { return }
        var choices = stored(scope)
        let previous = choices[series]
        choices[series] = Choice(
            itemID: id,
            audio: audioExplicit ? source.mediaStreams.first { $0.type == .audio && $0.index == selection.audioStreamIndex }.map(SemanticTrackPreference.init) : previous?.audio,
            subtitle: subtitleExplicit ? source.mediaStreams.first { $0.type == .subtitle && $0.index == selection.subtitleStreamIndex }.map(SemanticTrackPreference.init) : previous?.subtitle,
            subtitlesOff: subtitleExplicit ? selection.subtitleStreamIndex == -1 : previous?.subtitlesOff == true
        )
        if let data = try? JSONEncoder().encode(choices) {
            defaults.set(data, forKey: key(scope))
        }
    }

    struct Resolution {
        let selection: PlaybackStreamSelection
        let hasUnavailableSelection: Bool
    }

    /// Resolve effective tracks without changing the incoming Automatic/Explicit intent.
    /// Local callers supply only their projected downloaded catalog, never the original
    /// remote catalog of a converted or unidentified file.
    func resolve(request: PlaybackRequest, item: MediaItem, source: MediaSource?, baseSelection: PlaybackStreamSelection, scope: AccountScope) -> Resolution {
        let streams = source?.mediaStreams ?? []
        let choice = applicableChoice(for: item, scope: scope)
        func available(_ index: Int?, kind: MediaStreamKind) -> Int? {
            index.flatMap { value in
                guard value >= 0, streams.contains(where: { $0.type == kind && $0.index == value }) else { return nil }
                return value
            }
        }

        var selection = baseSelection
        var unavailable = false
        // Raw indexes without a semantic snapshot are also explicit. A sanitized
        // missing index must not silently become a remembered, different role.
        if request.audioTrack != nil || request.streamSelection.audioStreamIndex != nil {
            selection.audioStreamIndex = available(baseSelection.audioStreamIndex, kind: .audio)
            unavailable = selection.audioStreamIndex == nil
        } else {
            selection.audioStreamIndex = choice?.audio.flatMap { Self.match($0.stream, in: streams) }
            unavailable = choice?.audio != nil && selection.audioStreamIndex == nil
        }
        switch request.subtitleIntent {
        case .off:
            selection.subtitleStreamIndex = -1
        case .explicit:
            selection.subtitleStreamIndex = available(baseSelection.subtitleStreamIndex, kind: .subtitle)
            unavailable = unavailable || selection.subtitleStreamIndex == nil
        case .automatic:
            selection.subtitleStreamIndex = choice?.subtitlesOff == true ? -1 : choice?.subtitle.flatMap { Self.match($0.stream, in: streams) }
            unavailable = unavailable || (choice?.subtitle != nil && selection.subtitleStreamIndex == nil)
        }
        return Resolution(selection: selection, hasUnavailableSelection: unavailable)
    }

    private func applicableChoice(for item: MediaItem, scope: AccountScope) -> Choice? {
        guard isEnabled(scope: scope), item.type == .episode, let series = item.seriesID,
              let choice = stored(scope)[series], choice.itemID != item.id else { return nil }
        return choice
    }

    private func stored(_ scope: AccountScope) -> [String: Choice] {
        guard let data = defaults.data(forKey: key(scope)) else { return [:] }
        return (try? JSONDecoder().decode([String: Choice].self, from: data)) ?? [:]
    }

    static func match(_ previous: MediaStreamInfo, in streams: [MediaStreamInfo]) -> Int? {
        let language = normalizedLanguage(previous.language)
        let candidates = streams.filter {
            $0.type == previous.type && ($0.index ?? -1) >= 0
                && ($0.type != .audio || $0.isExternal != true)
                && ($0.isForced == true) == (previous.isForced == true)
                && ($0.isHearingImpaired == true) == (previous.isHearingImpaired == true)
                && role($0) == role(previous)
                && normalizedLanguage($0.language) == language
        }
        // A custom title can express a role in any language. Neither a shared
        // generated display label nor a unique language proves that named role.
        if let title = previous.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            let named = candidates.filter { sameLabel($0.title, title) }
            return named.count == 1 ? named.first?.index : nil
        }
        let labeled = candidates.filter { sameLabel($0.displayTitle, previous.displayTitle) }
        if labeled.count == 1 {
            return labeled.first?.index
        }
        // Untagged media needs a descriptive identity, never just a coincidental index.
        guard language != nil, candidates.count == 1 else { return nil }
        return candidates.first?.index
    }

    private static func role(_ stream: MediaStreamInfo) -> Int {
        let label = [stream.title, stream.displayTitle].compactMap { $0 }.joined(separator: " ").lowercased()
        if label.contains("commentary") {
            return 1
        }
        if label.contains("audio description") || label.contains("descriptive audio") || label.contains("described video") {
            return 2
        }
        return 0
    }

    private static func sameLabel(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs = lhs?.trimmingCharacters(in: .whitespacesAndNewlines), !lhs.isEmpty,
              let rhs = rhs?.trimmingCharacters(in: .whitespacesAndNewlines), !rhs.isEmpty else { return false }
        return lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    private static func normalizedLanguage(_ identifier: String?) -> String? {
        guard let identifier, !identifier.isEmpty else { return nil }
        let canonical = Locale.canonicalLanguageIdentifier(from: identifier)
        guard let code = Locale.Language(identifier: canonical).languageCode, !["und", "zxx"].contains(code.identifier) else { return nil }
        return code.identifier(.alpha2) ?? code.identifier(.alpha3)
    }
}
