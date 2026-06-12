@testable import Gus
import JellyfinAPI
import XCTest

/// XCTest `measure` probes for hot pure-logic paths, recorded in
/// `Documentation/AppStore/performance-baselines.md`.
///
/// These complement the `DiagnosticsHub` signpost intervals (server connect, library
/// load, playback startup, search), which are measured in Instruments against a live
/// server. These tests are intentionally named as measurements rather than pass/fail
/// budgets; release thresholds live in the documented baseline workflow.
final class PerformanceMeasurementTests: XCTestCase {
    private static let mapperItemCount = 2000

    private static func makeItems(count: Int) -> [BaseItemDto] {
        (0 ..< count).map { index in
            BaseItemDto(
                communityRating: 7.5,
                genres: ["Comedy", "Drama"],
                id: "item-\(index)",
                imageTags: [ImageType.primary.rawValue: "tag-\(index)"],
                indexNumber: index % 24,
                mediaSources: [
                    MediaSourceInfo(
                        container: "mp4",
                        id: "source-\(index)",
                        mediaStreams: [
                            MediaStream(codec: "h264", displayTitle: "1080p", index: 0, type: .video),
                            MediaStream(codec: "aac", displayTitle: "English", index: 1, isDefault: true, language: "eng", type: .audio),
                        ],
                        videoType: .videoFile
                    ),
                ],
                name: "Item \(index)",
                parentIndexNumber: index % 8,
                productionYear: 1999,
                runTimeTicks: 6420 * 10_000_000,
                type: index % 3 == 0 ? .episode : .movie,
                userData: UserItemDataDto(playbackPositionTicks: 42, playedPercentage: 37.5)
            )
        }
    }

    func testMediaItemMapperThroughputMeasurement() {
        let items = Self.makeItems(count: Self.mapperItemCount)
        measure {
            _ = JellyfinMediaItemMapper.mediaItems(from: items)
        }
    }

    func testServerURLNormalizationMeasurement() {
        let inputs = (0 ..< 2000).map { "  server-\($0).example.com:8096/jellyfin/  " }
        measure {
            for input in inputs {
                _ = try? AppModel.normalizeURL(input)
            }
        }
    }

    func testHistogramMathMeasurement() {
        let buckets = (0 ..< 10000).map { index in
            HistogramMath.Bucket(start: Double(index), end: Double(index + 1), count: index % 7)
        }
        measure {
            _ = HistogramMath.weightedAverage(of: buckets)
            _ = HistogramMath.weightedTotal(of: buckets)
        }
    }
}
