import XCTest
final class WatchRemediation: XCTestCase {
 override func setUp() {continueAfterFailure=false;executionTimeAllowance=180}
 func capture(_ app:XCUIApplication,_ name:String) {
  sleep(2)
  print("TREE_BASE64 \(name) \(Data(app.debugDescription.utf8).base64EncodedString())")
  print("CAPTURE_READY \(name)");fflush(stdout);sleep(3)
 }
 func testSmallWatchAudio() {
  let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus.watchkitapp")
  app.launchArguments=["--gus-demo-server"];app.launch();sleep(6)
  capture(app,"watch-remote")
  app.swipeUp();app.swipeUp()
  let music=app.buttons["Music"].firstMatch
  for _ in 0..<5 {if music.isHittable {break};app.swipeUp()}
  capture(app,"watch-browse")
  XCTAssertTrue(music.exists);music.tap()
  let album=app.buttons.matching(NSPredicate(format:"label CONTAINS %@","PUBLIC DOMAIN")).firstMatch
  XCTAssertTrue(album.waitForExistence(timeout:15));capture(app,"watch-music");album.tap()
  let track=app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Whispers")).firstMatch
  XCTAssertTrue(track.waitForExistence(timeout:15));capture(app,"watch-tracks");track.tap()
  let pause=app.buttons["Pause"]
  XCTAssertTrue(pause.waitForExistence(timeout:15));capture(app,"watch-audio")
  pause.tap();XCTAssertTrue(app.buttons["Play"].exists)
  app.swipeUp();capture(app,"watch-audio-paused")
  app.terminate()
 }
}
