import XCTest
final class Tail: XCTestCase {
 func shot(_ app:XCUIApplication,_ name:String) {
  sleep(2)
  let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)
  let t=XCTAttachment(string:app.debugDescription);t.name=name+"-tree";t.lifetime = .keepAlways;add(t)
 }
 #if os(watchOS)
 func testWatch() {
  let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus.watchkitapp")
  app.launch();sleep(4);shot(app,"watch-connect");app.terminate()
  app.launchArguments=["--gus-demo-server"];app.launch();sleep(7);shot(app,"watch-remote")
  for i in 1...4 { app.swipeUp();shot(app,"watch-page-\(i)") }
  app.terminate()
 }
 func testWatchMore() {
  let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus.watchkitapp")
  app.launchArguments=["--gus-demo-server"];app.launch();sleep(5)
  app.swipeUp();app.swipeUp();shot(app,"browse-top")
  if app.buttons["Movies"].exists {
   app.buttons["Movies"].tap();shot(app,"movies")
   let item=app.buttons.matching(NSPredicate(format:"label CONTAINS %@", "Edison")).firstMatch
   if item.exists {item.tap();shot(app,"movie-actions");app.swipeUp();shot(app,"movie-actions-lower")
    if app.buttons["Play on Watch"].exists {app.buttons["Play on Watch"].tap();sleep(6);shot(app,"watch-video")}
   }
  }
  app.terminate();app.launch();sleep(5)
  for i in 1...8 {app.swipeUp();if i >= 4 {shot(app,"more-page-\(i)")}}
  app.terminate()
 }
 #else
 func testScreens() {
  #if os(macOS)
  let app=XCUIApplication(url:URL(fileURLWithPath:"/Users/ericslutz/Developer/Code/Side Projects/A Playa Named Gus/Gus/build/DerivedData/Build/Products/Debug/A Playa Named Gus.app"))
  #else
  let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus")
  #endif
  let routes=[("connect",""),("home","home"),("libraries","libraries"),("settings","settings"),("movie","item/3b54b9d2d41e6a53d5fa6e1dd52b7af1"),("album","item/c3cbbf1aaa7b731f859cdddccb9609c8"),("photo","item/dfcea439343a6b5beb060329260ad10d"),("book","item/778975ecc43b55232b4330c87917f4eb"),("audio","play/271583dbfa9d4bb50f11e5195373cb84"),("video","play/e324275401dd350d45914c3388b5c8e0")]
  for (name,route) in routes {
   app.launchArguments = route.isEmpty ? ["--gus-skip-session-restore"] : ["--gus-demo-server","--gus-route",route]
   app.launch();sleep(5);shot(app,name);app.terminate()
  }
 }
 #endif
}
