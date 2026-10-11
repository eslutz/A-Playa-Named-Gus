import XCTest
final class Physical: XCTestCase {
 func shot(_ name:String,_ a:XCUIApplication) {
  sleep(2)
  XCTAssertEqual(a.state, .runningForeground, "Stop capture if another app interrupts Gus")
  let s=XCTAttachment(screenshot:a.screenshot());s.name=name;s.lifetime = .keepAlways;add(s)
  let t=XCTAttachment(string:a.debugDescription);t.name=name+"-tree";t.lifetime = .keepAlways;add(t)
 }
 func start(_ route:String="home")->XCUIApplication {
  continueAfterFailure=false;executionTimeAllowance=180
  XCUIDevice.shared.orientation = .portrait
  let a=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus");a.launchArguments=["--gus-route",route];a.launch();sleep(3);return a
 }
 override func tearDown(){XCUIDevice.shared.orientation = .portrait;super.tearDown()}
 func tap(_ name:String,_ a:XCUIApplication) {
  let b=a.buttons[name].firstMatch
  if b.exists {b.tap();return}
  let t=a.staticTexts[name].firstMatch;XCTAssertTrue(t.waitForExistence(timeout:10));t.tap()
 }
 func section(_ name:String,_ a:XCUIApplication) {
  if a.tabBars.buttons[name].exists {a.tabBars.buttons[name].tap()}
  else {a.tabBars.buttons["More"].tap();tap(name,a)}
 }
 func rotate(_ a:XCUIApplication,_ name:String) {
  XCUIDevice.shared.orientation = .landscapeLeft;sleep(2)
  XCTAssertGreaterThan(a.frame.width,a.frame.height);shot(name+"-landscape",a)
  XCUIDevice.shared.orientation = .portrait;sleep(2)
 }
 func testHomeLibraryAndDetail() {
  let a=start();XCTAssertTrue(a.tabBars.buttons["Home"].waitForExistence(timeout:15));shot("home-portrait",a);rotate(a,"home")
  section("Libraries",a);shot("libraries-portrait",a);rotate(a,"libraries")
  section("Movies",a);let item=a.buttons["The Alamo, 1960"].firstMatch;XCTAssertTrue(item.waitForExistence(timeout:15));item.tap()
  let play=a.buttons["Play"].firstMatch;XCTAssertTrue(play.waitForExistence(timeout:15));shot("movie-detail-portrait",a);rotate(a,"movie-detail")
  XCTAssertTrue(play.exists);XCTAssertTrue(play.isHittable)
 }
 func testSettingsAndDownloads() {
  let a=start("settings");shot("settings-portrait",a);rotate(a,"settings")
  for _ in 0..<6 {if a.buttons["Navigation"].firstMatch.isHittable {break};a.swipeUp()}
  tap("Navigation",a);shot("navigation-portrait",a);rotate(a,"navigation")
  a.terminate();a.launchArguments=["--gus-route","home"];a.launch();sleep(3)
  section("Downloaded",a);shot("downloads-portrait",a);rotate(a,"downloads")
  tap("Manage Downloads",a);shot("download-manager-portrait",a);rotate(a,"download-manager")
 }
 func pauseAndRotate(_ a:XCUIApplication,_ name:String) {
  for _ in 0..<8 {
   let transport=a.buttons["Play/Pause"]
   if transport.exists && transport.label == "Pause" {transport.tap();break}
   if transport.exists && transport.label == "Play" {break}
   a.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap();sleep(1)
  }
  let transport=a.buttons["Play/Pause"]
  XCTAssertTrue(transport.exists);XCTAssertEqual(transport.label,"Play")
  shot(name+"-paused-portrait",a)
  XCUIDevice.shared.orientation = .landscapeLeft;sleep(3)
  if !transport.exists {a.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()}
  XCTAssertTrue(transport.waitForExistence(timeout:5));XCTAssertEqual(transport.label,"Play")
  shot(name+"-paused-landscape",a)
  XCUIDevice.shared.orientation = .portrait;sleep(2)
  if !a.buttons["Close Button"].exists {a.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()}
  XCTAssertTrue(a.buttons["Close Button"].waitForExistence(timeout:5));a.buttons["Close Button"].tap();shot(name+"-closed",a)
 }
 func testDownloadedVideoRotation() {
  let a=start();section("Downloaded",a);let item=a.buttons["Idle Hands"].firstMatch;XCTAssertTrue(item.waitForExistence(timeout:15));item.tap();sleep(5);pauseAndRotate(a,"downloaded")
 }
 func testStreamedVideoRotation() {
  let a=start();section("Movies",a);let item=a.buttons["The Alamo, 1960"].firstMatch;XCTAssertTrue(item.waitForExistence(timeout:15));item.tap();let play=a.buttons["Play"].firstMatch;XCTAssertTrue(play.waitForExistence(timeout:15));play.tap();sleep(5);pauseAndRotate(a,"streamed")
 }
}
