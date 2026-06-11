import Foundation

/// A media-selection option candidate: its position within an AVKit selection group
/// plus the language it declares — decoupled from AVFoundation so matching is testable.
struct MediaSelectionCandidate: Equatable {
    let position: Int
    let languageTag: String?
}

/// Maps a Jellyfin stream index onto an AVKit media-selection option for in-place
/// track switching on direct-played files.
///
/// Direct-played containers expose tracks to AVKit in container order, which matches
/// Jellyfin's per-type stream order, so the primary key is the stream's ordinal among
/// same-type streams. A declared-language mismatch vetoes the ordinal match (the
/// container's track layout disagrees with the server's metadata) and falls back to an
/// unambiguous language match; failing both, callers rebuild the stream server-side.
enum PlaybackMediaSelectionMatcher {
    static func candidatePosition(
        forStreamIndex streamIndex: Int,
        kind: MediaStreamKind,
        streams: [MediaStreamInfo],
        candidates: [MediaSelectionCandidate]
    ) -> Int? {
        let sameKind = streams
            .filter { $0.type == kind }
            .sorted { ($0.index ?? .max) < ($1.index ?? .max) }
        guard let ordinal = sameKind.firstIndex(where: { $0.index == streamIndex }) else { return nil }
        let stream = sameKind[ordinal]

        if candidates.indices.contains(ordinal),
           languagesCompatible(stream.language, candidates[ordinal].languageTag)
        {
            return candidates[ordinal].position
        }

        guard let language = declaredLanguage(stream.language) else { return nil }
        let matches = candidates.filter { candidate in
            guard let tag = declaredLanguage(candidate.languageTag) else { return false }
            return normalized(language) == normalized(tag)
        }
        guard matches.count == 1, let match = matches.first else { return nil }
        return match.position
    }

    private static func languagesCompatible(_ jellyfinLanguage: String?, _ avLanguageTag: String?) -> Bool {
        guard let jellyfin = declaredLanguage(jellyfinLanguage),
              let av = declaredLanguage(avLanguageTag)
        else {
            return true // either side undeclared → trust the ordinal
        }
        return normalized(jellyfin) == normalized(av)
    }

    private static func declaredLanguage(_ code: String?) -> String? {
        guard let code, !code.isEmpty, code.lowercased() != "und" else { return nil }
        return code
    }

    /// Jellyfin uses ISO 639-2 ("eng"); AVFoundation uses BCP-47 ("en-US"). Normalize
    /// both to an alpha-2 code where Foundation knows one.
    private static func normalized(_ code: String) -> String {
        let alpha2 = Locale(identifier: code).language.languageCode?.identifier(.alpha2)
        return (alpha2 ?? code).lowercased()
    }
}
