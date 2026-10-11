import XCTest
final class Followup: XCTestCase {
 let app = XCUIApplication(bundleIdentifier: "dev.ericslutz.gus")
 override func setUp() {
  super.setUp();continueAfterFailure=false;executionTimeAllowance=360
  app.terminate();XCUIDevice.shared.orientation = .portrait
  app.launchArguments=[];app.launch()
  XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout:15))
 }
 override func tearDown() {app.terminate();XCUIDevice.shared.orientation = .portrait;super.tearDown()}
 func shot(_ name:String) {
  sleep(2)
  let s=XCTAttachment(screenshot:XCUIScreen.main.screenshot());s.name=name;s.lifetime = .keepAlways;add(s)
  let t=XCTAttachment(string:app.debugDescription);t.name=name+"-tree";t.lifetime = .keepAlways;add(t)
 }
 func landscape(_ name:String) {XCUIDevice.shared.orientation = .landscapeLeft;sleep(2);XCTAssertGreaterThan(app.frame.width,app.frame.height);shot(name)}
 func settings() {
  app.tabBars.buttons["More"].tap()
  let settings=app.buttons["Settings"].firstMatch
  if settings.waitForExistence(timeout:3) {settings.tap()} else {app.staticTexts["Settings"].firstMatch.tap()}
  XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout:10))
 }
 func testHome() {
  app.tabBars.buttons["Home"].tap()
  XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout:15))
  shot("home-portrait");landscape("home-landscape")
 }
 func testSettingsNavigation() {
  settings();shot("settings-portrait")
  let row=app.buttons["Navigation"].firstMatch
  for _ in 0..<7 {if row.exists && row.isHittable {break};app.swipeUp()}
  XCTAssertTrue(row.exists);XCTAssertTrue(row.isHittable);row.tap()
  XCTAssertTrue(app.navigationBars["Navigation"].waitForExistence(timeout:10))
  shot("navigation-portrait");landscape("navigation-landscape")
  XCTAssertTrue(app.navigationBars["Navigation"].exists)
 }
 func testSettingsLandscape() {settings();landscape("settings-landscape")}
 func testDownloadManager() {
  app.tabBars.buttons["Downloaded"].tap();shot("downloads-portrait")
  let manage=app.buttons["Manage Downloads"].firstMatch
  XCTAssertTrue(manage.waitForExistence(timeout:10));manage.tap()
  shot("download-manager-portrait");landscape("download-manager-landscape")
  XCTAssertTrue(app.navigationBars["Downloads"].exists)
 }
}
