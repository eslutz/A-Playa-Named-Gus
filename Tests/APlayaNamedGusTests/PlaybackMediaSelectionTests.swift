import Foundation
@testable import Gus
import Testing

@Suite("Playback media selection matching")
struct PlaybackMediaSelectionTests {
    private func streams() -> [MediaStreamInfo] {
        [
            MediaStreamInfo(index: 0, type: .video),
            MediaStreamInfo(index: 1, isDefault: true, language: "eng", type: .audio),
            MediaStreamInfo(index: 2, language: "jpn", type: .audio),
            MediaStreamInfo(index: 3, language: "eng", type: .subtitle),
            MediaStreamInfo(index: 4, language: "spa", type: .subtitle),
        ]
    }

    @Test("matches by ordinal among same-kind streams")
    func matchesByOrdinal() {
        let candidates = [
            MediaSelectionCandidate(position: 0, languageTag: "en"),
            MediaSelectionCandidate(position: 1, languageTag: "ja"),
        ]

        #expect(PlaybackMediaSelectionMatcher.candidatePosition(
            forStreamIndex: 2,
            kind: .audio,
            streams: streams(),
            candidates: candidates
        ) == 1)
    }

    @Test("normalizes ISO 639-2 against BCP-47 language tags")
    func normalizesLanguageCodes() {
        let candidates = [
            MediaSelectionCandidate(position: 0, languageTag: "en-US"),
            MediaSelectionCandidate(position: 1, languageTag: "es-419"),
        ]

        #expect(PlaybackMediaSelectionMatcher.candidatePosition(
            forStreamIndex: 4,
            kind: .subtitle,
            streams: streams(),
            candidates: candidates
        ) == 1)
    }

    @Test("a declared-language mismatch at the ordinal falls back to an unambiguous language match")
    func languageMismatchFallsBackToLanguageSearch() {
        // Container order disagrees with server metadata: candidate at the English
        // stream's ordinal is Japanese.
        let candidates = [
            MediaSelectionCandidate(position: 0, languageTag: "ja"),
            MediaSelectionCandidate(position: 1, languageTag: "en"),
        ]

        #expect(PlaybackMediaSelectionMatcher.candidatePosition(
            forStreamIndex: 1,
            kind: .audio,
            streams: streams(),
            candidates: candidates
        ) == 1)
    }

    @Test("ambiguous language matches refuse rather than guess")
    func ambiguousLanguageRefuses() {
        let candidates = [
            MediaSelectionCandidate(position: 0, languageTag: "ja"),
            MediaSelectionCandidate(position: 1, languageTag: "en"),
            MediaSelectionCandidate(position: 2, languageTag: "en"),
        ]

        #expect(PlaybackMediaSelectionMatcher.candidatePosition(
            forStreamIndex: 1,
            kind: .audio,
            streams: streams(),
            candidates: candidates
        ) == nil)
    }

    @Test("undeclared languages trust the ordinal")
    func undeclaredLanguagesTrustOrdinal() {
        let candidates = [
            MediaSelectionCandidate(position: 0, languageTag: "und"),
            MediaSelectionCandidate(position: 1, languageTag: nil),
        ]

        #expect(PlaybackMediaSelectionMatcher.candidatePosition(
            forStreamIndex: 2,
            kind: .audio,
            streams: streams(),
            candidates: candidates
        ) == 1)
    }

    @Test("unknown stream index returns nil")
    func unknownStreamIndexReturnsNil() {
        #expect(PlaybackMediaSelectionMatcher.candidatePosition(
            forStreamIndex: 9,
            kind: .audio,
            streams: streams(),
            candidates: [MediaSelectionCandidate(position: 0, languageTag: "en")]
        ) == nil)
    }
}

@Suite("Playback quality")
struct PlaybackQualityTests {
    @Test("bitrates descend from maximum to low")
    func bitratesDescend() {
        let bitrates = PlaybackQuality.allCases.map(\.maxStreamingBitrate)
        #expect(bitrates == bitrates.sorted(by: >))
        #expect(PlaybackQuality.maximum.maxStreamingBitrate == 120_000_000)
        #expect(PlaybackQuality.low.maxStreamingBitrate == 3_000_000)
    }

    @Test("stored quality defaults to maximum for unknown raw values")
    func storedDefaultsToMaximum() {
        #expect(PlaybackQuality(rawValue: "nonsense") == nil)
        #expect(PlaybackQuality.stored.maxStreamingBitrate >= PlaybackQuality.high.maxStreamingBitrate)
    }
}
