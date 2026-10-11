import XCTest
final class TVRemediation: XCTestCase {
 override func setUp() {continueAfterFailure=false;executionTimeAllowance=150}
 func capture(_ app:XCUIApplication,_ name:String) {
  sleep(2)
  print("TREE_BASE64 \(name) \(Data(app.debugDescription.utf8).base64EncodedString())")
  print("CAPTURE_READY \(name)");fflush(stdout)
  let device=ProcessInfo.processInfo.environment["SIMULATOR_UDID"] ?? ""
  let done=expectation(description:"Native capture")
  let url=URL(string:"http://127.0.0.1:8097/capture?device=\(device)&name=\(name)")!
  URLSession.shared.dataTask(with:url) { _,response,error in
   XCTAssertNil(error);XCTAssertEqual((response as? HTTPURLResponse)?.statusCode,200);done.fulfill()
  }.resume()
  wait(for:[done],timeout:50)
 }
 func testDetailLinkNavigation() {
  let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus")
  app.launchArguments=["--gus-demo-server","--gus-route","item/3b54b9d2d41e6a53d5fa6e1dd52b7af1"]
  app.launch()
  XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout:25))
  capture(app,"tv-detail-full-screen")
  XCUIRemote.shared.press(.down)
  capture(app,"tv-detail-remote-focus")
  XCUIRemote.shared.press(.menu)
  XCTAssertFalse(app.buttons["Play"].exists)
  capture(app,"tv-detail-return-home")
  app.terminate()
 }
 func testAudioExit() {
  let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus")
  app.launchArguments=["--gus-demo-server","--gus-route","play/271583dbfa9d4bb50f11e5195373cb84"]
  app.launch()
  XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout:25))
  capture(app,"tv-audio-player")
  XCUIRemote.shared.press(.menu)
  capture(app,"tv-audio-closed")
  let reopen=app.buttons["NowPlaying.reopen"]
  XCTAssertTrue(reopen.waitForExistence(timeout:5))
  for _ in 0..<40 {if reopen.hasFocus {break};XCUIRemote.shared.press(.down)}
  XCTAssertTrue(reopen.hasFocus);XCUIRemote.shared.press(.select)
  XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout:5));capture(app,"tv-audio-reopened")
  XCUIRemote.shared.press(.menu)
  app.terminate()
 }
}
