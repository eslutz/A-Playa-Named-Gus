import XCTest
final class DownloadRepairs: XCTestCase {
 let app = XCUIApplication(bundleIdentifier: "dev.ericslutz.gus")
 override func setUp() {
  continueAfterFailure=false; executionTimeAllowance=360
  XCUIDevice.shared.orientation = .portrait
  app.launchArguments=[];app.launch()
  XCTAssertTrue(app.tabBars.buttons["Downloaded"].waitForExistence(timeout:15))
 }
 override func tearDown() {app.terminate(); XCUIDevice.shared.orientation = .portrait;super.tearDown()}
 func shot(_ name:String) {
  XCTAssertEqual(app.state,.runningForeground)
  let s=XCTAttachment(screenshot:XCUIScreen.main.screenshot());s.name=name;s.lifetime = .keepAlways;add(s)
  let t=XCTAttachment(string:app.debugDescription);t.name=name+"-tree";t.lifetime = .keepAlways;add(t)
 }
 func testArtworkAndManagement() {
  app.tabBars.buttons["Downloaded"].tap();sleep(10);shot("downloads-artwork-portrait")
  app.buttons["Manage Downloads"].firstMatch.tap()
  XCTAssertTrue(app.switches["Downloads.deleteFinished"].waitForExistence(timeout:5))
  XCTAssertFalse(app.buttons["Play Idle Hands"].exists)
  shot("management-portrait")
  let delete=app.buttons["Delete Idle Hands"].firstMatch
  for _ in 0..<5 {if delete.isHittable {break};app.swipeUp()}
  XCTAssertTrue(delete.isHittable);delete.tap()
  XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout:5));shot("delete-confirmation")
  app.buttons["Cancel"].tap();XCTAssertTrue(delete.exists)
  app.buttons["Downloads.select"].tap()
  let select=app.buttons["Select Idle Hands"].firstMatch
  for _ in 0..<5 {if select.isHittable {break};app.swipeUp()}
  select.tap()
  for _ in 0..<6 {if app.buttons["Downloads.deleteSelected"].isHittable {break};app.swipeDown()}
  app.buttons["Downloads.deleteSelected"].tap()
  XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout:5));shot("selected-delete-confirmation")
  app.buttons["Cancel"].tap()
  XCUIDevice.shared.orientation = .landscapeLeft;sleep(2);shot("management-landscape")
 }
 func testActionsAndSidebar() {
  app.tabBars.buttons["Movies"].tap()
  let item=app.buttons["The Alamo, 1960"].firstMatch
  XCTAssertTrue(item.waitForExistence(timeout:10));item.tap()
  let download=app.buttons["Download"].firstMatch
  XCTAssertTrue(download.waitForExistence(timeout:10))
  let favorites=app.buttons.matching(NSPredicate(format:"label CONTAINS 'Favorites'")).firstMatch
  XCTAssertTrue(favorites.exists)
  XCTAssertEqual(download.frame.height,favorites.frame.height,accuracy:2)
  XCTAssertEqual(download.frame.width,favorites.frame.width,accuracy:2)
  XCTAssertEqual(download.frame.midY,favorites.frame.midY,accuracy:2)
  shot("detail-actions-portrait")
  XCUIDevice.shared.orientation = .landscapeLeft;sleep(2);shot("detail-actions-landscape")
  XCUIDevice.shared.orientation = .portrait;sleep(2)
  app.tabBars.buttons["Home"].tap()
  XCUIDevice.shared.orientation = .landscapeLeft;sleep(2)
  XCTAssertTrue(app.staticTexts["Gus"].exists);shot("home-sidebar-landscape")
 }
 func testLandscapeScrollableControls() {
  app.tabBars.buttons["Movies"].tap();let movie=app.buttons["The Alamo, 1960"].firstMatch
  XCTAssertTrue(movie.waitForExistence(timeout:10));movie.tap()
  XCTAssertTrue(app.buttons["Download"].waitForExistence(timeout:10))
  shot("hero-width-portrait")
  XCUIDevice.shared.orientation = .landscapeLeft;sleep(2);shot("hero-width-landscape")
  app.coordinate(withNormalizedOffset:CGVector(dx:0.8,dy:0.85)).press(forDuration:0.1,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.8,dy:0.35)))
  let download=app.buttons["Download"].firstMatch
  let favorite=app.buttons.matching(NSPredicate(format:"label CONTAINS 'Favorites'")).firstMatch
  XCTAssertTrue(download.isHittable);XCTAssertTrue(favorite.isHittable)
  XCTAssertEqual(download.frame.width,favorite.frame.width,accuracy:2);XCTAssertEqual(download.frame.height,favorite.frame.height,accuracy:2);XCTAssertEqual(download.frame.midY,favorite.frame.midY,accuracy:2)
  shot("detail-actions-landscape-scrolled")
  XCUIDevice.shared.orientation = .portrait;sleep(2);app.tabBars.buttons["Downloaded"].tap();app.buttons["Manage Downloads"].tap()
  XCTAssertTrue(app.buttons["Downloads.select"].waitForExistence(timeout:5))
  XCUIDevice.shared.orientation = .landscapeLeft;sleep(2)
  let delete=app.buttons["Delete Idle Hands"].firstMatch
  for _ in 0..<5 {if delete.isHittable {break};app.coordinate(withNormalizedOffset:CGVector(dx:0.8,dy:0.85)).press(forDuration:0.1,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.8,dy:0.3)))}
  XCTAssertTrue(delete.isHittable);shot("management-landscape-scrolled")
 }

}
