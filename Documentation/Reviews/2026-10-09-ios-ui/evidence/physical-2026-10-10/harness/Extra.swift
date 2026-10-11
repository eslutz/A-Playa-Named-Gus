import XCTest
final class ExtraAudit: XCTestCase {
 func app()->XCUIApplication {executionTimeAllowance=100;continueAfterFailure=false;let a=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus");a.launch();return a}
 func shot(_ n:String,_ a:XCUIApplication) {Thread.sleep(forTimeInterval:3);let name="extra-"+n+(a.frame.width>a.frame.height ? "-landscape":"-portrait");let t=XCTAttachment(string:a.debugDescription);t.name=name+"-tree";t.lifetime = .keepAlways;add(t);print("CAPTURE_READY \(name)");Thread.sleep(forTimeInterval:3)}
 func section(_ n:String,_ a:XCUIApplication) {if a.tabBars.buttons[n].exists {a.tabBars.buttons[n].tap()} else {a.staticTexts[n].firstMatch.tap()}}
 func testFilter() {let a=app();section("Movies",a);let b=a.buttons["Filter"];XCTAssertTrue(b.waitForExistence(timeout:8));b.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap();shot("filter-menu",a)}
 func testEmptySearch() {let a=app();section("Home",a);let f=a.searchFields.firstMatch;XCTAssertTrue(f.waitForExistence(timeout:8));f.tap();f.typeText("NoSuchTitleAudit987654");if a.keyboards.buttons["Search"].exists {a.keyboards.buttons["Search"].tap()};shot("empty-search",a)}

 func testEpisodeDetail() {
  let a=app();section("Libraries",a);a.buttons["Family Shows"].tap();let series=a.buttons["Are You Afraid of the Dark?, 1990"];XCTAssertTrue(series.waitForExistence(timeout:8));series.tap()
  
  Thread.sleep(forTimeInterval:3)
  if a.frame.width>a.frame.height {
   a.coordinate(withNormalizedOffset:CGVector(dx:0.8,dy:0.76)).press(forDuration:0.1,thenDragTo:a.coordinate(withNormalizedOffset:CGVector(dx:0.8,dy:0.28)))
  } else {a.swipeUp()}
  shot("episode-rail",a)
  if a.frame.width>a.frame.height {a.coordinate(withNormalizedOffset:CGVector(dx:0.73,dy:0.70)).tap()} else {a.coordinate(withNormalizedOffset:CGVector(dx:0.62,dy:0.20)).tap()};shot("episode-detail",a)
 }

 func testNavigationAndAbout() {
  let a=app()
  if a.tabBars.buttons["More"].exists {a.tabBars.buttons["More"].tap();a.staticTexts["Settings"].tap()} else {section("Settings",a)}
  if a.frame.width>a.frame.height {
   for _ in 0..<2 {a.coordinate(withNormalizedOffset:CGVector(dx:0.8,dy:0.76)).press(forDuration:0.1,thenDragTo:a.coordinate(withNormalizedOffset:CGVector(dx:0.8,dy:0.28)))}
   a.coordinate(withNormalizedOffset:CGVector(dx:0.8,dy:0.70)).press(forDuration:0.1,thenDragTo:a.coordinate(withNormalizedOffset:CGVector(dx:0.8,dy:0.50)))
  } else {a.swipeUp()}
  shot("settings-navigation-row",a)
  a.buttons["Navigation"].firstMatch.tap();shot("navigation-settings",a)
 }
}
