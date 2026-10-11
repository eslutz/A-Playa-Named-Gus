import XCTest
#if os(iOS)
    import UIKit
#endif

@MainActor
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
                UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
            ]
            app.launch()

            let headline = app.staticTexts["Connect to Jellyfin"].firstMatch
            XCTAssertTrue(headline.waitForExistence(timeout: 10))
            XCTAssertGreaterThanOrEqual(headline.frame.height, 40)
            capture("connect-verified-ax5-top")
            revealConnect(in: app)
            capture("connect-verified-ax5-action")
        }

        func testConnectScreenRendersWithPseudolocalizationAtLargestAccessibilityContentSize() {
            let app = makeApp()
            app.launchArguments += [
                "-NSDoubleLocalizedStrings",
                "YES",
                "-UIPreferredContentSizeCategoryName",
                UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
            ]
            app.launch()

            revealConnect(in: app)
            XCTAssertGreaterThan(connectButton(in: app).label.count, "Connect".count)
            capture("connect-native-double-length-ax5")
        }
    #endif

    #if os(iOS)
        private func revealConnect(in app: XCUIApplication) {
            let button = connectButton(in: app)
            for _ in 0 ..< 8 {
                if button.exists, button.isHittable {
                    break
                }
                app.swipeUp()
            }
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            XCTAssertTrue(button.isHittable)
        }

    #endif

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--gus-skip-session-restore"]
        return app
    }

    private func connectButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons["ConnectServerView.connectButton"]
    }
}
