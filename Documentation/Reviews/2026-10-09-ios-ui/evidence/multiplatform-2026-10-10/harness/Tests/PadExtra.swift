import XCTest
final class PadExtra: XCTestCase {
 func shot(_ app:XCUIApplication,_ name:String) { sleep(2);let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a);let t=XCTAttachment(string:app.debugDescription);t.name=name+"-tree";t.lifetime = .keepAlways;add(t) }
 func testExtra() {
  let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus")
  for (n,r) in [("series","item/27223149162dfc7034397fe963c6c399"),("episode","item/7cb5ea4e2c42e772b2eb63e724cbe42d"),("reader","play/778975ecc43b55232b4330c87917f4eb"),("audio","play/271583dbfa9d4bb50f11e5195373cb84")] {
   XCUIDevice.shared.orientation = .portrait;app.launchArguments=["--gus-demo-server","--gus-route",r];app.launch();sleep(5);shot(app,n+"-portrait")
   XCUIDevice.shared.orientation = .landscapeLeft;shot(app,n+"-landscape")
   if n == "audio" {app.swipeDown();shot(app,"audio-after-dismiss-swipe")}
   if app.buttons["Done"].exists {app.buttons["Done"].firstMatch.tap();shot(app,n+"-done")}
   app.terminate()
  }
  XCUIDevice.shared.orientation = .portrait
  app.launchArguments=["--gus-demo-server","--gus-route","home","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"]
  app.launch();sleep(5);shot(app,"home-AX5");app.terminate()
 }
}
