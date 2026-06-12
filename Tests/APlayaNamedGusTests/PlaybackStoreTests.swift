import Foundation
@testable import Gus
import Testing

/// Note: PlaybackStore requires AVFoundation and a live SessionStore, which makes
/// full unit testing complex. These tests cover the pure-logic portions.
/// Full state-machine tests require integration-level setup with a mock session.
@Suite("Playback store — pure logic")
struct PlaybackStoreTests {
    @Test("PlaybackQuality ordering: cases run from highest to lowest bitrate")
    func qualityOrdering() {
        let qualities = PlaybackQuality.allCases
        let bitrates = qualities.map { $0.maxStreamingBitrate }
        let sorted = bitrates.sorted(by: >)
        #expect(bitrates == sorted, "PlaybackQuality cases should be ordered from highest to lowest bitrate")
    }

    @Test("PlaybackQuality.maximum has 120 Mbps bitrate")
    func maximumQualityBitrate() {
        #expect(PlaybackQuality.maximum.maxStreamingBitrate == 120_000_000)
    }

    @Test("PlaybackQuality.high has 20 Mbps bitrate")
    func highQualityBitrate() {
        #expect(PlaybackQuality.high.maxStreamingBitrate == 20_000_000)
    }

    @Test("PlaybackQuality.medium has 8 Mbps bitrate")
    func mediumQualityBitrate() {
        #expect(PlaybackQuality.medium.maxStreamingBitrate == 8_000_000)
    }

    @Test("PlaybackQuality.low has 3 Mbps bitrate")
    func lowQualityBitrate() {
        #expect(PlaybackQuality.low.maxStreamingBitrate == 3_000_000)
    }

    @Test("PlaybackQuality raw values round-trip through stored accessor")
    func qualityRoundTrip() {
        for quality in PlaybackQuality.allCases {
            UserDefaults.standard.set(quality.rawValue, forKey: PlaybackQuality.defaultsKey)
            #expect(PlaybackQuality.stored == quality, "Expected stored quality to equal \(quality)")
        }
        UserDefaults.standard.removeObject(forKey: PlaybackQuality.defaultsKey)
    }

    @Test("PlaybackQuality.stored defaults to .maximum when key absent")
    func storedDefaultsToMaximum() {
        UserDefaults.standard.removeObject(forKey: PlaybackQuality.defaultsKey)
        #expect(PlaybackQuality.stored == .maximum)
    }

    @Test("PlaybackPreferences.autoPlaysNextEpisode defaults to true")
    func autoPlayNextEpisodeDefault() {
        UserDefaults.standard.removeObject(forKey: PlaybackPreferences.autoPlayNextEpisodeKey)
        #expect(PlaybackPreferences.autoPlaysNextEpisode == true)
    }

    @Test("PlaybackPreferences.autoPlaysNextEpisode reflects stored value")
    func autoPlayNextEpisodeReadsStoredValue() {
        UserDefaults.standard.set(false, forKey: PlaybackPreferences.autoPlayNextEpisodeKey)
        #expect(PlaybackPreferences.autoPlaysNextEpisode == false)
        UserDefaults.standard.set(true, forKey: PlaybackPreferences.autoPlayNextEpisodeKey)
        #expect(PlaybackPreferences.autoPlaysNextEpisode == true)
        UserDefaults.standard.removeObject(forKey: PlaybackPreferences.autoPlayNextEpisodeKey)
    }

    @Test("PlaybackQuality has four cases covering all tiers")
    func qualityCaseCount() {
        #expect(PlaybackQuality.allCases.count == 4)
    }

    @Test("PlaybackQuality case identifiers match raw values")
    func qualityIdentifiers() {
        for quality in PlaybackQuality.allCases {
            #expect(quality.id == quality.rawValue)
        }
    }
}
