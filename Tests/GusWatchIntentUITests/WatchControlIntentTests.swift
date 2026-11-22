import AppIntentsTesting
import XCTest

@MainActor
final class WatchControlIntentTests: XCTestCase {
    func testDownloadsControlOpensWatchDownloads() async throws {
        continueAfterFailure = false
        let fixture = try XCTUnwrap(URL(string: "http://127.0.0.1:5062"))
        let health: Data
        do {
            (health, _) = try await URLSession.shared.data(from: fixture.appending(path: "health"))
        } catch let error as URLError where error.code == .cannotConnectToHost {
            throw XCTSkip("Run Scripts/book-details-fixture.py --navigation for the Watch routing fixture.")
        }
        let response = try JSONDecoder().decode([String: String].self, from: health)
        XCTAssertEqual(response["fixture"], "gus-navigation")

        let app = XCUIApplication(bundleIdentifier: "dev.ericslutz.gus.watchkitapp")
        app.launchArguments = ["--gus-demo-server", "--gus-disable-cloud-sync"]
        app.launchEnvironment["GUS_DEMO_URL"] = fixture.absoluteString
        app.launch()
        defer {
            if app.state == .runningForeground {
                let signOut = app.buttons["Sign Out"]
                for _ in 0 ..< 12 where !signOut.isHittable {
                    app.swipeUp(velocity: .fast)
                }
                if signOut.isHittable {
                    signOut.tap()
                }
            }
            app.terminate()
        }
        XCTAssertTrue(app.navigationBars["Remote"].waitForExistence(timeout: 20))
        let definitions = IntentDefinitions(bundleIdentifier: "dev.ericslutz.gus.watchkitapp")
        var intent = definitions.intents["GusWidgetNavigationIntent"].makeIntent()
        intent.target = AnyAppEnum(typeIdentifier: "GusWidgetDestination", rawValue: "downloaded")
        try await intent.run()
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 15))
    }
}
