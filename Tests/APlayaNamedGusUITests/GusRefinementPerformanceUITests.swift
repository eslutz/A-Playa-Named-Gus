import XCTest

#if os(iOS)
    /// Opt-in, same-device Release comparison. The caller installs and signs into
    /// the rights-cleared demo fixture before running this test. No credentials
    /// or media identifiers are included in the numeric attachment.
    @MainActor
    final class GusRefinementPerformanceUITests: XCTestCase {
        func testColdWarmAndBrowseLatency() throws {
            try XCTSkipUnless(ProcessInfo.processInfo.environment["GUS_REFINEMENT_PERFORMANCE"] == "1")
            continueAfterFailure = false
            executionTimeAllowance = 1200
            let app = XCUIApplication()
            defer { app.terminate() }
            app.launch()
            let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "NextUp.card.media:")).firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 30), "Restore the demo account with a Next Up item before measuring")

            var cold: [Double] = []
            var warm: [Double] = []
            var detail: [Double] = []
            var back: [Double] = []
            for _ in 0 ..< 30 {
                app.terminate()
                let start = ContinuousClock.now
                app.launch()
                XCTAssertTrue(card.waitForExistence(timeout: 30))
                cold.append(milliseconds(since: start))

                XCUIDevice.shared.press(.home)
                let foregroundStart = ContinuousClock.now
                app.activate()
                XCTAssertTrue(card.waitForExistence(timeout: 30))
                warm.append(milliseconds(since: foregroundStart))
            }
            for _ in 0 ..< 10 {
                let start = ContinuousClock.now
                card.tap()
                XCTAssertTrue(app.buttons["Detail.play"].waitForExistence(timeout: 30))
                detail.append(milliseconds(since: start))
                let backStart = ContinuousClock.now
                let backButton = app.navigationBars.buttons.element(boundBy: 0)
                XCTAssertTrue(backButton.waitForExistence(timeout: 5))
                backButton.tap()
                XCTAssertTrue(card.waitForExistence(timeout: 10))
                back.append(milliseconds(since: backStart))
            }
            let payload: [String: [Double]] = [
                "coldProcessToHomeMilliseconds": cold,
                "warmForegroundToHomeMilliseconds": warm,
                "browseToDetailMilliseconds": detail,
                "backToHomeMilliseconds": back,
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "refinement-latency-samples"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        private func milliseconds(since start: ContinuousClock.Instant) -> Double {
            let components = start.duration(to: .now).components
            return Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
        }
    }
#endif
