import XCTest
final class Audit: XCTestCase {
 func shot(_ app: XCUIApplication,_ n: String) {
  sleep(2)
  let a=XCTAttachment(screenshot:app.screenshot()); a.name=n; a.lifetime = .keepAlways; add(a)
  let t=XCTAttachment(string:app.debugDescription);t.name=n+"-tree";t.lifetime = .keepAlways;add(t)
 }
 func testFlow() {
  let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus")
  app.launchArguments=["--gus-demo-server"]
  app.launch(); sleep(7); shot(app,"home")
  #if os(tvOS)
  for _ in 0..<3 { XCUIRemote.shared.press(.down) };shot(app,"remote-down")
  XCUIRemote.shared.press(.select);shot(app,"remote-select")
  XCUIRemote.shared.press(.menu);shot(app,"remote-back")
  #endif
  app.terminate()
 }
 #if os(iOS)
 func testPadScreens() {
  let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus")
  let routes=[("connect",""),("home","home"),("libraries","libraries"),("settings","settings"),("downloaded","downloaded"),("movie","item/3b54b9d2d41e6a53d5fa6e1dd52b7af1"),("album","item/c3cbbf1aaa7b731f859cdddccb9609c8"),("photo","item/dfcea439343a6b5beb060329260ad10d"),("book","item/778975ecc43b55232b4330c87917f4eb"),("audio","play/271583dbfa9d4bb50f11e5195373cb84"),("video","play/e324275401dd350d45914c3388b5c8e0")]
  for (name,route) in routes {
   XCUIDevice.shared.orientation = .portrait
   app.launchArguments = route.isEmpty ? ["--gus-skip-session-restore"] : ["--gus-demo-server","--gus-route",route]
   app.launch();sleep(5)
   if name == "audio", app.buttons["Pause"].exists { app.buttons["Pause"].tap() }
   if name == "video", app.buttons["Play/Pause"].exists { app.buttons["Play/Pause"].tap() }
   shot(app,"pad-"+name+"-portrait")
   XCUIDevice.shared.orientation = .landscapeLeft
   shot(app,"pad-"+name+"-landscape")
   app.terminate()
  }
  XCUIDevice.shared.orientation = .portrait
 }
 #endif
}
