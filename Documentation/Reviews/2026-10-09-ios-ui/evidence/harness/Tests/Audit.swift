import XCTest
import UIKit
final class Audit: XCTestCase {
 func capture(_ name: String, _ app: XCUIApplication) {
  Thread.sleep(forTimeInterval: 2)
  print("CAPTURE_READY \(name)")
  Thread.sleep(forTimeInterval: 4)
  let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
  let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
 }
 func testConnectLayouts() throws {
  let app = XCUIApplication(bundleIdentifier: "dev.ericslutz.gus")
  app.launchArguments = ["--gus-skip-session-restore"]
  app.launch()
  XCTAssertTrue(app.buttons["ConnectServerView.connectButton"].waitForExistence(timeout: 15))
  for (name, orientation) in [("portrait", UIDeviceOrientation.portrait), ("landscape-left", .landscapeLeft), ("landscape-right", .landscapeRight)] {
   XCUIDevice.shared.orientation = orientation
   capture(name, app)
   try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .sufficientElementDescription, .textClipped]) { issue in
    let evidence = XCTAttachment(string: "\(issue)"); evidence.name = name + "-audit-issue"; evidence.lifetime = .keepAlways; self.add(evidence)
    print("AUDIT_ISSUE \(name) \(issue)")
    return true
   }
  }
  XCUIDevice.shared.orientation = .portrait
 }
 func testInvalidAddressRecovery() {
  let app = XCUIApplication(bundleIdentifier: "dev.ericslutz.gus")
  app.launchArguments = ["--gus-skip-session-restore"]
  app.launch()
  let field = app.textFields.firstMatch
  XCTAssertTrue(field.waitForExistence(timeout: 15))
  field.tap(); field.typeText("://\n")
  capture("invalid-address", app)
 }
}
