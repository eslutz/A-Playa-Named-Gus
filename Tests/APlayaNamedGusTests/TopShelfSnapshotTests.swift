import Foundation
@testable import Gus
import Testing

@Suite("Top Shelf snapshot")
struct TopShelfSnapshotTests {
    @Test("snapshot round-trips through its container file")
    func roundTrip() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gus-topshelf-tests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let snapshot = TopShelfSnapshot(items: [
            TopShelfSnapshot.Item(
                id: "item-1",
                title: "Night of the Living Dead",
                imageURL: URL(string: "http://example.com/Items/item-1/Images/Backdrop?maxWidth=1280"),
                playbackProgress: 0.42
            ),
            TopShelfSnapshot.Item(id: "item-2", title: "Sintel", imageURL: nil, playbackProgress: nil),
        ])

        snapshot.save(to: fileURL)
        let loaded = TopShelfSnapshot.load(from: fileURL)

        #expect(loaded == snapshot)
    }

    @Test("missing snapshot loads as nil (static fallback)")
    func missingSnapshot() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gus-topshelf-missing-\(UUID().uuidString).json")
        #expect(TopShelfSnapshot.load(from: fileURL) == nil)
        #expect(TopShelfSnapshot.load(from: nil) == nil)
    }
}
