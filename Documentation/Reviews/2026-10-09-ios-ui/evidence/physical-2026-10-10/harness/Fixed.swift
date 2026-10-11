import XCTest
class FixedAudit: XCTestCase {
 func capture(_ name: String,_ app: XCUIApplication) {
  Thread.sleep(forTimeInterval: 3)
  let suffix = app.frame.width > app.frame.height ? "landscape" : "portrait"
  let name = "targeted-" + name + "-" + suffix
  let a=XCTAttachment(string:app.debugDescription);a.name=name+"-tree";a.lifetime = .keepAlways;add(a)
  print("CAPTURE_READY \(name)");Thread.sleep(forTimeInterval:3)
 }
 func tap(_ name:String,_ app:XCUIApplication) {
  let b=app.buttons[name].firstMatch
  if b.exists { b.coordinate(withNormalizedOffset: CGVector(dx:0.5,dy:0.5)).tap();return }
  let t=app.staticTexts[name].firstMatch
  XCTAssertTrue(t.waitForExistence(timeout:5));t.tap()
 }
 func section(_ name:String,_ app:XCUIApplication) {
  if app.tabBars.buttons[name].exists {app.tabBars.buttons[name].tap()}
  else if app.tabBars.buttons["More"].exists {app.tabBars.buttons["More"].tap();tap(name,app)}
  else {tap(name,app)}
 }
 func start()->XCUIApplication {executionTimeAllowance=100;continueAfterFailure=false;let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus");app.launch();return app}
 func scroll(_ app:XCUIApplication) {
  let x:CGFloat = app.frame.width > app.frame.height ? 0.80 : 0.65
  app.coordinate(withNormalizedOffset:CGVector(dx:x,dy:0.76)).press(forDuration:0.1,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:x,dy:0.28)))
 }
 func testMovieDetail() {
  let app=start();section("Movies",app)
  XCTAssertTrue(app.buttons["The Alamo, 1960"].waitForExistence(timeout:12))
  capture("movies-grid",app)
  app.buttons["The Alamo, 1960"].tap();capture("movie-detail-top",app)
  scroll(app);capture("movie-detail-middle",app)
  scroll(app);capture("movie-detail-bottom",app)
 }
 func testSeriesDetail() {
  let app=start();section("Libraries",app);tap("Family Shows",app)
  capture("shows-grid",app)
  let first=app.scrollViews.buttons.firstMatch
  XCTAssertTrue(first.waitForExistence(timeout:8));print("SERIES_SELECTED \(first.label)");first.tap()
  capture("series-detail-top",app)
  scroll(app);capture("series-detail-middle",app)
  scroll(app);capture("series-detail-bottom",app)
 }
 func testSearch() {
  let app=start();section("Home",app)
  let field=app.searchFields.firstMatch
  XCTAssertTrue(field.waitForExistence(timeout:8));field.tap();field.typeText("Goosebumps")
  capture("search-keyboard",app)
  if app.keyboards.buttons["Search"].exists {app.keyboards.buttons["Search"].tap()}
  capture("search-results",app)
 }
 func testSettings() {
  let app=start();section("Settings",app);capture("settings-top",app)
  for _ in 0..<5 {
   let n=app.descendants(matching:.any).matching(identifier:"Navigation").firstMatch
   if n.exists && n.isHittable {break}
   scroll(app)
  }
  capture("settings-middle",app);tap("Navigation",app);capture("navigation-settings",app)
 }
 func testDownloads() {
  let app=start();section("Downloaded",app);capture("downloaded",app)
  tap("Manage Downloads",app);capture("download-manager-top",app)
  scroll(app);capture("download-manager-bottom",app)
 }
}
