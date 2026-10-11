import Foundation
@testable import Gus
import Testing

@Suite("Audio session operation ordering")
struct PlaybackAudioSessionTests {
    @MainActor @Test("late activation, dismissal and replacement retain request order")
    func preservesOrderAcrossSuspension() async {
        let queue = PlaybackAudioSessionQueue()
        let recorder = Recorder()
        queue.enqueue {
            await recorder.append("activation-start")
            try? await Task.sleep(for: .milliseconds(20))
            await recorder.append("activation-finish")
        }
        queue.enqueue { await recorder.append("dismissal") }
        let replacement = queue.enqueue { await recorder.append("replacement") }
        await replacement.value
        #expect(await recorder.values == ["activation-start", "activation-finish", "dismissal", "replacement"])
    }

    private actor Recorder {
        private(set) var values: [String] = []

        func append(_ value: String) {
            values.append(value)
        }
    }
}
