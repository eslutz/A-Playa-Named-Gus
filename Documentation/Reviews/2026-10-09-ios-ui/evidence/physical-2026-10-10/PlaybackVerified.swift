import XCTest
final class PlaybackAudit: XCTestCase {
 func shot(_ n:String,_ a:XCUIApplication) {
  Thread.sleep(forTimeInterval:2)
  let name="playback-verified-"+n+(a.frame.width>a.frame.height ? "-landscape":"-portrait")
  let t=XCTAttachment(string:a.debugDescription);t.name=name+"-tree";t.lifetime = .keepAlways;add(t)
  print("CAPTURE_READY \(name)");Thread.sleep(forTimeInterval:3)
 }
 func inspect(_ n:String,_ a:XCUIApplication) {
  Thread.sleep(forTimeInterval:2)
  for _ in 0..<4 {
   let transport=a.buttons["Play/Pause"]
   if transport.exists && transport.label == "Pause" {transport.tap();break}
   if transport.exists && transport.label == "Play" {break}
   a.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap();Thread.sleep(forTimeInterval:0.5)
  }
  shot(n+"-player",a)
  for (label,suffix) in [("Audio Track","audio"),("Subtitles","subtitles"),("Playback Speed","speed")] {
   if a.buttons[label].exists {a.buttons[label].tap();shot(n+"-"+suffix,a);a.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.15)).tap()}
  }
  if a.buttons["Close Button"].exists {a.buttons["Close Button"].tap()}
  shot(n+"-closed",a)

 }
 func testDownloaded() {
  executionTimeAllowance=90;continueAfterFailure=false
  let a=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus");a.launch();defer {a.terminate()}
  a.staticTexts["Downloaded"].firstMatch.tap();let item=a.buttons["Idle Hands"].firstMatch;XCTAssertTrue(item.waitForExistence(timeout:10));item.tap();inspect("downloaded",a)
 }
 func testStreamed() {
  executionTimeAllowance=90;continueAfterFailure=false
  let a=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus");a.launch();defer {a.terminate()}
  a.staticTexts["Movies"].firstMatch.tap();let item=a.buttons["The Alamo, 1960"].firstMatch;XCTAssertTrue(item.waitForExistence(timeout:10));item.tap();let play=a.buttons["Play"].firstMatch;XCTAssertTrue(play.waitForExistence(timeout:10));play.coordinate(withNormalizedOffset:CGVector(dx:0.85,dy:0.5)).tap();inspect("streamed",a)
 }
}
