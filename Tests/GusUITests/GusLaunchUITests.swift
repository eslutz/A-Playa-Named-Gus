import XCTest

final class GusLaunchUITests: XCTestCase {
    func testConnectScreenRendersOnLaunch() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["Connect to Jellyfin"].waitForExistence(timeout: 5))
    }
}
