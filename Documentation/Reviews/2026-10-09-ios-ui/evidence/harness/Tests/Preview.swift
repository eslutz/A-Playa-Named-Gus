import XCTest
import UIKit
final class PreviewAudit: XCTestCase {
 func capture(_ name: String, _ app: XCUIApplication) {
  Thread.sleep(forTimeInterval: 2)
  print("CAPTURE_READY \(name)")
  Thread.sleep(forTimeInterval: 4)
  let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
  let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
 }
 func tap(_ label: String, _ app: XCUIApplication) {
  let b = app.buttons[label].firstMatch
  if b.waitForExistence(timeout: 5) { b.tap() } else { app.staticTexts[label].firstMatch.tap() }
 }
 func testPreviewSurfaces() throws {
  let app = XCUIApplication(bundleIdentifier: "dev.ericslutz.gus")
  app.launchArguments = ["--gus-skip-session-restore", "--gus-debug-preview-session"]
  XCUIDevice.shared.orientation = .portrait
  app.launch()
  tap("Settings", app)
  capture("preview-settings-portrait", app)
  XCUIDevice.shared.orientation = .landscapeLeft
  capture("preview-settings-landscape", app)
  XCUIDevice.shared.orientation = .portrait
  tap("Downloaded Media", app)
  capture("preview-manage-downloads-portrait", app)
  XCUIDevice.shared.orientation = .landscapeLeft
  capture("preview-manage-downloads-after-rotation", app)
  print("ROTATION_DOWNLOADS_STILL_PRESENT \(app.navigationBars["Downloads"].exists)")
  XCUIDevice.shared.orientation = .portrait
  app.terminate(); app.launch()
  tap("Downloaded", app)
  capture("preview-downloaded-portrait", app)
  XCUIDevice.shared.orientation = .landscapeLeft
  capture("preview-downloaded-landscape", app)
  try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .sufficientElementDescription, .textClipped]) { issue in
   let a = XCTAttachment(string: "\(issue)"); a.name = "preview-download-audit-issue"; a.lifetime = .keepAlways; self.add(a)
   print("AUDIT_ISSUE preview-download \(issue)"); return true
  }
  XCUIDevice.shared.orientation = .portrait
 }
}
