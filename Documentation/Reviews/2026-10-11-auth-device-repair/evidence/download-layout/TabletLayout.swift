import XCTest
final class TabletLayout: XCTestCase {
 let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus")
 func shot(_ name:String){XCTAssertEqual(app.state,.runningForeground);let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a);let t=XCTAttachment(string:app.debugDescription);t.name=name+"-tree";t.lifetime = .keepAlways;add(t)}
 func testPortraitAndLandscape(){continueAfterFailure=false;executionTimeAllowance=180;app.launchArguments=["--gus-demo-server"];XCUIDevice.shared.orientation = .portrait;app.launch();sleep(5);shot("ipad-home-portrait");XCUIDevice.shared.orientation = .landscapeLeft;sleep(3);shot("ipad-home-landscape");app.terminate();app.launchArguments=["--gus-demo-server","--gus-route","item/3b54b9d2d41e6a53d5fa6e1dd52b7af1"];XCUIDevice.shared.orientation = .portrait;app.launch();XCTAssertTrue(app.buttons["Download"].firstMatch.waitForExistence(timeout:20));shot("ipad-actions-portrait");XCUIDevice.shared.orientation = .landscapeLeft;sleep(3);shot("ipad-actions-landscape");app.terminate();XCUIDevice.shared.orientation = .portrait}
}
