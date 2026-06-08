import XCTest

final class GusLaunchUITests: XCTestCase {
    func testConnectScreenRendersOnLaunch() {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(connectButton(in: app).waitForExistence(timeout: 5))
    }

    #if os(iOS)
        func testConnectScreenRendersAtLargestAccessibilityContentSize() {
            let app = makeApp()
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
            ]
            app.launch()

            XCTAssertTrue(connectButton(in: app).waitForExistence(timeout: 5))
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

            XCTAssertTrue(connectButton(in: app).waitForExistence(timeout: 5))
        }
    #endif

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--gus-skip-session-restore"]
        return app
    }

    private func connectButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons["ConnectServerView.connectButton"]
    }
}
