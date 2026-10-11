import XCTest
import Darwin
final class Landscape: XCTestCase {
 func testDirect() {
  let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus")
  XCUIDevice.shared.orientation = .landscapeLeft
  for (n,r) in [("home","home"),("libraries","libraries"),("settings","settings"),("book","item/778975ecc43b55232b4330c87917f4eb"),("audio","play/271583dbfa9d4bb50f11e5195373cb84")] {
   app.launchArguments=["--gus-demo-server","--gus-route",r];app.launch();sleep(5)
   print("DIRECT_CAPTURE \(n)");fflush(stdout);sleep(5);app.terminate()
  }
  XCUIDevice.shared.orientation = .portrait
 }
 func testExtra() {
  let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus")
  XCUIDevice.shared.orientation = .landscapeLeft
  for (n,r) in [("connect",""),("downloaded","downloaded"),("movie","item/3b54b9d2d41e6a53d5fa6e1dd52b7af1"),("album","item/c3cbbf1aaa7b731f859cdddccb9609c8"),("photo","item/dfcea439343a6b5beb060329260ad10d"),("series","item/27223149162dfc7034397fe963c6c399"),("episode","item/7cb5ea4e2c42e772b2eb63e724cbe42d"),("reader","play/778975ecc43b55232b4330c87917f4eb"),("video","play/e324275401dd350d45914c3388b5c8e0")] {
   app.launchArguments=r.isEmpty ? ["--gus-skip-session-restore"] : ["--gus-demo-server","--gus-route",r];app.launch();sleep(5)
   print("DIRECT_CAPTURE \(n)");fflush(stdout);sleep(5);app.terminate()
  }
  XCUIDevice.shared.orientation = .portrait
 }

}
