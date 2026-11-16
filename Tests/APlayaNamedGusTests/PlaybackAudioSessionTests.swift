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

    @MainActor @Test("category and activation failures propagate and do not poison the next activation", arguments: [false, true])
    func activationFailure(configurationFails: Bool) async throws {
        let failure = NSError(domain: NSOSStatusErrorDomain, code: 560_557_684)
        let recorder = Recorder()
        do {
            try await PlaybackAudioSession.activate(video: true, configureCategory: { _ in
                if configurationFails {
                    throw failure
                }
            }, activateSession: {
                await recorder.append("activation")
                throw failure
            })
            Issue.record("Audio session refusal must reach the caller")
        } catch {
            let activationError = try #require(error as? PlaybackAudioSessionActivationError)
            #expect(activationError.underlyingError?.domain == NSOSStatusErrorDomain)
            #expect(activationError.underlyingError?.code == 560_557_684)
            #expect(activationError.diagnosticDomain == 3)
            #expect(activationError.localizedDescription == String(localized: "Couldn't start audio playback. Try again."))
        }
        #expect(await recorder.values == (configurationFails ? [] : ["activation"]))
        try await PlaybackAudioSession.activate(video: false, configureCategory: { _ in }, activateSession: {
            await recorder.append("replacement")
        })
        #expect(await recorder.values.last == "replacement")
    }

    @Test("native activation rejection cannot become success when its callback omits an error")
    func activationCallbackResult() throws {
        #expect(throws: (any Error).self) {
            try PlaybackAudioSession.requireActivation(succeeded: false, error: nil)
        }
        let failure = NSError(domain: NSOSStatusErrorDomain, code: 560_557_684)
        #expect(throws: failure) {
            try PlaybackAudioSession.requireActivation(succeeded: false, error: failure)
        }
        try PlaybackAudioSession.requireActivation(succeeded: true, error: nil)
    }

    @MainActor @Test("activation cancellation keeps lifecycle cancellation semantics")
    func activationCancellation() async {
        do {
            try await PlaybackAudioSession.activate(video: false, configureCategory: { _ in }, activateSession: { throw CancellationError() })
            Issue.record("Activation must propagate cancellation")
        } catch {
            #expect(error is CancellationError)
            #expect(GusError(from: error).isCancellation)
        }
    }

    private actor Recorder {
        private(set) var values: [String] = []

        func append(_ value: String) {
            values.append(value)
        }
    }
}
