import XCTest
final class SimDownloads: XCTestCase {
 let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus")
 override func setUp() {continueAfterFailure=false;executionTimeAllowance=180;XCUIDevice.shared.orientation = .portrait;app.launchArguments=["--gus-demo-server","-downloads.deleteFinished","YES"];app.launch();XCTAssertTrue(app.tabBars.buttons["Downloaded"].waitForExistence(timeout:20));app.tabBars.buttons["Downloaded"].tap()}
 override func tearDown(){app.terminate();super.tearDown()}
 func find(_ label:String)->XCUIElement {let b=app.buttons[label].firstMatch;for _ in 0..<8 {if b.exists && b.isHittable{return b};app.swipeUp()};return b}
 func manager(){app.buttons["Manage Downloads"].firstMatch.tap();XCTAssertTrue(app.buttons["Downloads.select"].waitForExistence(timeout:5))}
 func confirm(_ label:String){XCTAssertTrue(app.alerts["Delete Downloads?"].waitForExistence(timeout:5));app.alerts.buttons[label].tap()}
 func shot(_ name:String){let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
 func testASelectedDeletion() {
  manager();app.buttons["Downloads.select"].tap();find("Select Delete A").tap();find("Select Delete B").tap()
  for _ in 0..<8 {if app.buttons["Downloads.deleteSelected"].isHittable{break};app.swipeDown()}
  app.buttons["Downloads.deleteSelected"].tap();confirm("Cancel")
  XCTAssertTrue(app.buttons["Downloads.deleteSelected"].exists)
  app.buttons["Downloads.deleteSelected"].tap();shot("selected-confirmation");confirm("Delete 2 Downloads")
  XCTAssertFalse(app.buttons["Delete Delete A"].exists);XCTAssertFalse(app.buttons["Delete Delete B"].exists)
 }
 func testBSwipeDeletion() {
  let row=find("Swipe Test");XCTAssertTrue(row.exists);row.swipeLeft();let delete=app.buttons["Delete"].firstMatch
  if delete.exists {delete.tap()}
  XCTAssertFalse(app.buttons["Swipe Test"].exists);XCTAssertFalse(app.alerts.firstMatch.exists);shot("swipe-deleted")
 }
 func testCVideoCompletion() {
  find("Finish Video").tap();sleep(40)
  XCTAssertTrue(app.tabBars.buttons["Downloaded"].waitForExistence(timeout:15))
  XCTAssertFalse(app.buttons["Finish Video"].exists);shot("video-completion-cleanup")
 }
 func testDAudioCompletion() {
  find("Finish Audio").tap();sleep(20);shot("audio-finished")
  let done=app.buttons["Done"].firstMatch;XCTAssertTrue(done.waitForExistence(timeout:5));done.tap()
  XCTAssertFalse(app.cells.buttons["Finish Audio"].exists)
 }
 func testEBookCompletion() {
  find("Finish Book").tap();let done=app.buttons["Done"].firstMatch;XCTAssertTrue(done.waitForExistence(timeout:10));sleep(2);shot("book-final-page");done.tap();sleep(2)
  XCTAssertFalse(app.buttons["Finish Book"].exists)
 }
 func testZDeleteAll() {
  manager();find("Downloads.deleteAll").tap();confirm("Cancel")
  find("Downloads.deleteAll").tap();XCTAssertTrue(app.alerts["Delete Downloads?"].waitForExistence(timeout:5))
  app.alerts.buttons.matching(NSPredicate(format:"label BEGINSWITH 'Delete '")).firstMatch.tap()
  XCTAssertTrue(app.staticTexts["No Downloads"].waitForExistence(timeout:5));shot("all-deleted")
 }
}
