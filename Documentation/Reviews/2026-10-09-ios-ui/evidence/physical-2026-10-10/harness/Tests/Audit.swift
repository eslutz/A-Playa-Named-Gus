import XCTest
import UIKit
final class PhysicalAudit: XCTestCase {
 func capture(_ name: String, _ app: XCUIApplication) {
  Thread.sleep(forTimeInterval: 3)
  let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
  let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
  print("CAPTURE_READY \(name)")
  Thread.sleep(forTimeInterval: 3)
 }
 func testSignedInHome() throws {
  let app = XCUIApplication(bundleIdentifier: "dev.ericslutz.gus")
  app.activate()
  XCUIDevice.shared.orientation = .portrait
  capture("physical-home-portrait", app)
  XCUIDevice.shared.orientation = .landscapeLeft
  capture("physical-home-landscape", app)
  XCUIDevice.shared.orientation = .portrait
 }
 func testSignedInDetailAndLibrary() throws {
  let app = XCUIApplication(bundleIdentifier: "dev.ericslutz.gus")
  app.activate()
  XCUIDevice.shared.orientation = .portrait
  let home = app.tabBars.buttons["Home"].firstMatch
  if home.waitForExistence(timeout: 5) { home.tap() }
  let episode = app.buttons["In Living Color, S1·E5"].firstMatch
  XCTAssertTrue(episode.waitForExistence(timeout: 8))
  episode.tap()
  capture("physical-episode-detail-portrait", app)
  XCUIDevice.shared.orientation = .landscapeLeft
  capture("physical-episode-detail-after-rotation", app)
  XCUIDevice.shared.orientation = .portrait
  let libraries = app.tabBars.buttons["Libraries"].firstMatch
  XCTAssertTrue(libraries.waitForExistence(timeout: 5))
  libraries.tap()
  capture("physical-libraries-portrait", app)
  XCUIDevice.shared.orientation = .landscapeLeft
  capture("physical-libraries-landscape", app)
  XCUIDevice.shared.orientation = .portrait
 }

}
