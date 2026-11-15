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

    func selection(for item: MediaItem, source: MediaSource, scope: AccountScope) -> PlaybackStreamSelection {
        guard isEnabled(scope: scope), item.type == .episode, let series = item.seriesID,
              let choice = stored(scope)[series], choice.itemID != item.id else { return .none }
        return PlaybackStreamSelection(
            audioStreamIndex: choice.audio.flatMap { Self.match($0.stream, in: source.mediaStreams) },
            subtitleStreamIndex: choice.subtitlesOff ? -1 : choice.subtitle.flatMap { Self.match($0.stream, in: source.mediaStreams) }
        )
    }

    func hasUnavailableSelection(for item: MediaItem, source: MediaSource, scope: AccountScope) -> Bool {
        guard isEnabled(scope: scope), item.type == .episode, let series = item.seriesID,
              let choice = stored(scope)[series], choice.itemID != item.id else { return false }
        return (choice.audio != nil && Self.match(choice.audio!.stream, in: source.mediaStreams) == nil)
            || (choice.subtitle != nil && Self.match(choice.subtitle!.stream, in: source.mediaStreams) == nil)
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
