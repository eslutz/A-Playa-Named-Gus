import XCTest
final class FinalCompletion: XCTestCase {
 let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus")
 override func setUp(){continueAfterFailure=false;executionTimeAllowance=180;XCUIDevice.shared.orientation = .portrait;app.launchArguments=["--gus-demo-server","-downloads.deleteFinished","YES"];app.launch();XCTAssertTrue(app.tabBars.buttons["Downloaded"].waitForExistence(timeout:20));app.tabBars.buttons["Downloaded"].tap()}
 override func tearDown(){app.terminate();super.tearDown()}
 func shot(_ name:String){let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a);let t=XCTAttachment(string:app.debugDescription);t.name=name+"-tree";t.lifetime = .keepAlways;add(t)}
 func row(_ name:String)->XCUIElement {let b=app.cells.buttons[name].firstMatch;for _ in 0..<6 {if b.isHittable{return b};app.swipeUp()};return b}
 func testEPUBCompletion(){
  row("Finish EPUB").tap();XCTAssertTrue(app.buttons["Chapters"].waitForExistence(timeout:15));sleep(3);shot("epub-beginning")
  app.buttons["BookReader.done"].tap();XCTAssertTrue(row("Finish EPUB").exists)
  row("Finish EPUB").tap();XCTAssertTrue(app.buttons["Chapters"].waitForExistence(timeout:15));app.buttons["Chapters"].tap();app.buttons["Final Chapter"].tap();sleep(4);shot("epub-final-page")
  app.buttons["BookReader.done"].tap();sleep(3);XCTAssertFalse(app.cells.buttons["Finish EPUB"].exists);shot("epub-completion-cleanup")
 }
 func testRepeatCompletion(){
  row("Repeat Audio").tap();XCTAssertTrue(app.buttons["Repeat Off"].waitForExistence(timeout:10));app.buttons["Repeat Off"].tap();app.buttons["Repeat All"].tap();sleep(20)
  XCTAssertTrue(app.buttons["Pause"].exists);shot("audio-repeat-retained")
  app.buttons["Done"].tap();XCTAssertTrue(row("Repeat Audio").exists)
  app.buttons["NowPlaying.reopen"].tap();XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout:10));app.buttons["Stop"].tap();sleep(3)
  XCTAssertFalse(app.cells.buttons["Repeat Audio"].exists);shot("audio-repeat-stop-cleanup")
 }
}
final class RepeatAllRemaining: XCTestCase {
 let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus")
 func shot(_ name:String){let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a);let t=XCTAttachment(string:app.debugDescription);t.name=name+"-tree";t.lifetime = .keepAlways;add(t)}
 func testTwoTrackRepeatAll(){
  continueAfterFailure=false;executionTimeAllowance=180
  app.launchArguments=["--gus-demo-server","--gus-route","item/4b8337fa903bbfa157f0932ce705246c","-downloads.deleteFinished","YES"]
  app.launch();XCTAssertTrue(app.buttons["Play"].firstMatch.waitForExistence(timeout:20));app.buttons["Play"].firstMatch.tap()
  XCTAssertTrue(app.buttons["Repeat Off"].waitForExistence(timeout:15));app.buttons["Repeat Off"].tap()
  XCTAssertTrue(app.buttons["Repeat All"].exists);shot("repeat-all-start")
  sleep(22);XCTAssertTrue(app.buttons["Pause"].exists);shot("repeat-all-looping")
  XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout:5));app.buttons["Stop"].tap();shot("repeat-all-stopped");app.terminate()
 }
}
final class AdaptiveToolbarSmoke: XCTestCase {
 func testCloseAndStopRemainAccessible(){
  continueAfterFailure=false;executionTimeAllowance=120
  let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus")
  XCUIDevice.shared.orientation = .portrait
  app.launchArguments=["--gus-demo-server","--gus-route","item/3b54b9d2d41e6a53d5fa6e1dd52b7af1"];app.launch()
  let done=app.buttons["ContentLink.detailDone"];XCTAssertTrue(done.waitForExistence(timeout:15));XCTAssertEqual(done.label,"Done");done.tap();XCTAssertFalse(done.exists);app.terminate()
  app.launchArguments=["--gus-demo-server","--gus-route","item/4b8337fa903bbfa157f0932ce705246c"];app.launch()
  let play=app.buttons["Play"].firstMatch;XCTAssertTrue(play.waitForExistence(timeout:15));play.tap()
  let stop=app.buttons["Stop"];XCTAssertTrue(stop.waitForExistence(timeout:15));XCTAssertTrue(stop.isHittable)
  let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name="home-search-audio-toolbar";shot.lifetime = .keepAlways;add(shot)
  stop.tap();app.terminate()
 }
}
