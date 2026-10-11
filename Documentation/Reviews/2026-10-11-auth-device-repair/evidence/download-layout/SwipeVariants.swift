import XCTest
final class SwipeVariants: XCTestCase {
 let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus")
 override func setUp(){continueAfterFailure=false;executionTimeAllowance=120;XCUIDevice.shared.orientation = .portrait;app.launchArguments=["--gus-demo-server"];app.launch();XCTAssertTrue(app.tabBars.buttons["Downloaded"].waitForExistence(timeout:20));app.tabBars.buttons["Downloaded"].tap()}
 override func tearDown(){app.terminate();super.tearDown()}
 func row(_ name:String)->XCUIElement{let b=app.cells.containing(.button,identifier:name).firstMatch;for _ in 0..<6{if b.isHittable{return b};app.swipeUp()};return b}
 func shot(_ name:String){let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
 func testPartialAndFullSwipe(){
  let partial=row("Delete A");XCTAssertTrue(partial.exists)
  partial.coordinate(withNormalizedOffset:CGVector(dx:0.90,dy:0.5)).press(forDuration:0.1,thenDragTo:partial.coordinate(withNormalizedOffset:CGVector(dx:0.60,dy:0.5)))
  XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout:3));XCTAssertTrue(app.cells.buttons["Delete A"].exists);shot("partial-swipe-reveals-delete")
  app.buttons["Delete"].tap();XCTAssertFalse(app.cells.buttons["Delete A"].exists);XCTAssertFalse(app.alerts.firstMatch.exists)
  let full=row("Delete B");XCTAssertTrue(full.exists)
  full.coordinate(withNormalizedOffset:CGVector(dx:0.95,dy:0.5)).press(forDuration:0.1,thenDragTo:full.coordinate(withNormalizedOffset:CGVector(dx:0.02,dy:0.5)))
  sleep(2);XCTAssertFalse(app.cells.buttons["Delete B"].exists);XCTAssertFalse(app.alerts.firstMatch.exists);shot("full-swipe-deletes-immediately")
 }
}
