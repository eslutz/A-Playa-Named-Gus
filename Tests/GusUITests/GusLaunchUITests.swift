import XCTest

final class GusLaunchUITests: XCTestCase {
    func testConnectScreenRendersOnLaunch() {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.staticTexts["Connect to Jellyfin"].waitForExistence(timeout: 5))
    }

    func testConnectScreenRendersAtLargestAccessibilityContentSize() {
        let app = makeApp()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["Connect to Jellyfin"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Connect"].exists)
    }

    func testConnectScreenRendersWithPseudolocalizationAtLargestAccessibilityContentSize() {
        let app = makeApp()
        app.launchArguments += [
            "-AppleLanguages",
            "(en-XA)",
            "-AppleLocale",
            "en_XA",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launch()

        XCTAssertTrue(app.buttons["ConnectServerView.connectButton"].waitForExistence(timeout: 5))
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--gus-skip-session-restore"]
        return app
    }
}
