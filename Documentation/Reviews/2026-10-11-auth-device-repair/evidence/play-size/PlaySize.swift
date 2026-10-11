import XCTest
final class PlaySize: XCTestCase {
 let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus")
 override func tearDown(){app.terminate();super.tearDown()}
 func capture(_ name:String){
  let play=app.buttons["Play"].firstMatch
  XCTAssertTrue(play.waitForExistence(timeout:20))
  XCTAssertGreaterThan(play.frame.width,0);XCTAssertLessThanOrEqual(play.frame.width,321)
  let metrics=XCTAttachment(string:"Play frame: \(play.frame)\nApp frame: \(app.frame)\n"+app.debugDescription);metrics.name=name+"-metrics";metrics.lifetime = .keepAlways;add(metrics)
  #if os(iOS)
  let screenshot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());
  #else
  let screenshot=XCTAttachment(screenshot:app.screenshot());
  #endif
  screenshot.name=name;screenshot.lifetime = .keepAlways;add(screenshot)
 }
 func testPlaySize(){
  continueAfterFailure=false;executionTimeAllowance=180
  #if os(iOS)
  XCUIDevice.shared.orientation = .portrait
  #endif
  app.launchArguments=["--gus-demo-server","--gus-route","item/3b54b9d2d41e6a53d5fa6e1dd52b7af1"];app.launch()
  capture("play-default")
  #if os(iOS)
  XCUIDevice.shared.orientation = .landscapeLeft;sleep(2);capture("play-landscape")
  XCUIDevice.shared.orientation = .portrait
  #endif
 }
}
