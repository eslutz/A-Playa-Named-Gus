import XCTest
final class HeroLayout: XCTestCase {
 let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus")
 func shot(_ name:String){XCTAssertEqual(app.state,.runningForeground);let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a);let t=XCTAttachment(string:app.debugDescription);t.name=name+"-tree";t.lifetime = .keepAlways;add(t)}
 func testPortraitAndLandscape(){continueAfterFailure=false;executionTimeAllowance=180;app.launchArguments=["--gus-demo-server"];XCUIDevice.shared.orientation = .portrait;app.launch();sleep(5);shot("hero-simulator-home-portrait");XCUIDevice.shared.orientation = .landscapeLeft;sleep(3);shot("hero-simulator-home-landscape");app.terminate();app.launchArguments=["--gus-demo-server","--gus-route","item/3b54b9d2d41e6a53d5fa6e1dd52b7af1"];XCUIDevice.shared.orientation = .portrait;app.launch();XCTAssertTrue(app.buttons["Download"].firstMatch.waitForExistence(timeout:20));shot("hero-simulator-actions-portrait");XCUIDevice.shared.orientation = .landscapeLeft;sleep(3);shot("hero-simulator-actions-landscape");app.terminate();XCUIDevice.shared.orientation = .portrait}
 func testSplitPaneHero(){continueAfterFailure=false;executionTimeAllowance=120;app.launchArguments=["--gus-demo-server"];XCUIDevice.shared.orientation = .portrait;app.launch();XCTAssertTrue(app.tabBars.buttons["Movies"].waitForExistence(timeout:20));app.tabBars.buttons["Movies"].tap();let movie=app.buttons.matching(NSPredicate(format:"label BEGINSWITH 'President McKinley'")).firstMatch;XCTAssertTrue(movie.waitForExistence(timeout:10));movie.tap();XCTAssertTrue(app.buttons["Download"].waitForExistence(timeout:10));XCUIDevice.shared.orientation = .landscapeLeft;sleep(3);shot("hero-split-landscape");app.coordinate(withNormalizedOffset:CGVector(dx:0.8,dy:0.85)).press(forDuration:0.1,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.8,dy:0.65)),withVelocity:.slow,thenHoldForDuration:0.5);XCTAssertTrue(app.buttons["Download"].isHittable);shot("hero-split-landscape-scrolled");app.terminate();XCUIDevice.shared.orientation = .portrait}

}

final class RemainingAccessibility: XCTestCase {
 let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus")
 override func tearDown(){app.terminate();XCUIDevice.shared.orientation = .portrait;super.tearDown()}
 func capture(_ name:String){let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a);let t=XCTAttachment(string:app.debugDescription);t.name=name+"-tree";t.lifetime = .keepAlways;add(t)}
 func audit(_ name:String) throws {
  var findings:[String]=[]
  try app.performAccessibilityAudit(for:[.hitRegion,.sufficientElementDescription,.textClipped,.dynamicType]) { issue in findings.append(String(describing:issue)); return true }
  let a=XCTAttachment(string:findings.isEmpty ? "No native audit issues in requested categories" : findings.joined(separator:"\n"));a.name=name+"-audit-findings";a.lifetime = .keepAlways;add(a)
 }
 func runLarge(_ style:String) throws {
  continueAfterFailure=false;executionTimeAllowance=240
  XCUIDevice.shared.orientation = .portrait
  app.launchArguments=["--gus-demo-server","--gus-route","item/3b54b9d2d41e6a53d5fa6e1dd52b7af1","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL","-dev.ericslutz.gus.appearance",style.lowercased()]
  app.launch();XCTAssertTrue(app.buttons["Detail.play"].waitForExistence(timeout:20));capture("large-"+style+"-portrait")
  let download=app.buttons["Download"].firstMatch
  reveal(download, landscape:false);capture("large-"+style+"-actions");try audit("large-"+style)
  XCUIDevice.shared.orientation = .landscapeLeft;sleep(2)
  reveal(download, landscape:true);capture("large-"+style+"-landscape")

 }
 func reveal(_ button:XCUIElement,landscape:Bool){
  let h=landscape ? min(app.frame.width,app.frame.height) : max(app.frame.width,app.frame.height)
  for _ in 0..<22 {
   let f=button.frame
   if button.isHittable && f.minY >= 100 && f.maxY <= h-18 {break}
   let down=f.minY < 100
   app.coordinate(withNormalizedOffset:CGVector(dx:0.88,dy:down ? 0.4 : 0.75)).press(forDuration:0.1,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.88,dy:down ? 0.55 : 0.6)),withVelocity:.slow,thenHoldForDuration:0.2)
  }
  XCTAssertTrue(button.isHittable);XCTAssertGreaterThanOrEqual(button.frame.minY,100);XCTAssertLessThanOrEqual(button.frame.maxY,h-18)
 }
 func testLargeLight() throws {try runLarge("Light")}
 func testLargeDark() throws {try runLarge("Dark")}
}

final class HomeSearchRepair: XCTestCase {
 func testLandscapeSearchAndRotation(){
  continueAfterFailure=false;executionTimeAllowance=180
  let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus")
  XCUIDevice.shared.orientation = .portrait;app.launchArguments=["--gus-demo-server","--gus-route","home"];app.launch();sleep(4)
  XCUIDevice.shared.orientation = .landscapeLeft;sleep(2)
  func shot(_ name:String){let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a);let t=XCTAttachment(string:app.debugDescription);t.name=name+"-tree";t.lifetime = .keepAlways;add(t)}
  shot("home-search-landscape")
  let field=app.searchFields.firstMatch.exists ? app.searchFields.firstMatch : app.textFields.firstMatch;XCTAssertTrue(field.waitForExistence(timeout:10));XCTAssertLessThan(field.frame.midY,120);field.tap();field.typeText("Sneeze");sleep(2);shot("home-search-results")
  XCUIDevice.shared.orientation = .portrait;sleep(2);XCTAssertEqual(field.value as? String,"Sneeze");shot("home-search-preserved-portrait")
  app.terminate()
 }
}
