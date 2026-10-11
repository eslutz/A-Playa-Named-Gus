import XCTest
final class Remediation: XCTestCase {
    override func setUp() { continueAfterFailure = false; executionTimeAllowance = 180 }
    func capture(_ app: XCUIApplication, _ name: String) {
        sleep(2)
        print("TREE_BASE64 \(name) \(Data(app.debugDescription.utf8).base64EncodedString())")
        print("CAPTURE_READY \(name)")
        fflush(stdout)
        let device=ProcessInfo.processInfo.environment["SIMULATOR_UDID"] ?? ""
        let done=expectation(description:"Native capture")
        let url=URL(string:"http://127.0.0.1:8097/capture?device=\(device)&name=\(name)")!
        URLSession.shared.dataTask(with:url) { _,response,error in
            XCTAssertNil(error)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode,200)
            done.fulfill()
        }.resume()
        wait(for:[done],timeout:50)
    }
    func testLayouts() {
        let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus")
        let routes=[("home","home"),("movie","item/3b54b9d2d41e6a53d5fa6e1dd52b7af1"),("book","item/778975ecc43b55232b4330c87917f4eb"),("album","item/c3cbbf1aaa7b731f859cdddccb9609c8")]
        for (name,route) in routes {
            XCUIDevice.shared.orientation = .portrait
            app.launchArguments=["--gus-demo-server","--gus-route",route]
            app.launch();sleep(5);capture(app,name+"-portrait")
            XCUIDevice.shared.orientation = .landscapeLeft
            capture(app,name+"-landscape")
            app.terminate()
        }
        XCUIDevice.shared.orientation = .portrait
    }
    func testAudioExitAndRotation() {
        let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus")
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments=["--gus-demo-server","--gus-route","play/271583dbfa9d4bb50f11e5195373cb84"]
        app.launch()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout:20))
        capture(app,"audio-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout:5))
        capture(app,"audio-landscape")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["NowPlaying.reopen"].waitForExistence(timeout:5))
        capture(app,"audio-closed-now-playing")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["NowPlaying.reopen"].waitForExistence(timeout:5))
        capture(app,"audio-closed-compact")
        app.buttons["NowPlaying.reopen"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout:5))
        capture(app,"audio-reopened")
        app.buttons["Stop"].tap()
        app.terminate();XCUIDevice.shared.orientation = .portrait
    }
    func testDownloadsRotation() {
        let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus")
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments=["--gus-demo-server","--gus-route","downloaded"]
        app.launch()
        sleep(6);capture(app,"downloaded-root")
        let manage=app.buttons["Manage Downloads"].firstMatch
        XCTAssertTrue(manage.waitForExistence(timeout:15));manage.tap()
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout:5))
        capture(app,"downloads-management-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout:5))
        capture(app,"downloads-management-landscape")
        app.terminate();XCUIDevice.shared.orientation = .portrait
    }
    func testMoreSettingsRotation() {
        let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus")
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments=["--gus-demo-server","--gus-route","home"]
        app.launch()
        XCTAssertTrue(app.buttons["More"].firstMatch.waitForExistence(timeout:20))
        app.buttons["More"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout:5))
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout:5))
        let link=app.buttons["Navigation"]
        for _ in 0..<4 { if link.isHittable {break}; app.swipeUp() }
        XCTAssertTrue(link.exists);link.tap()
        XCTAssertTrue(app.navigationBars["Navigation"].waitForExistence(timeout:5))
        XCTAssertEqual(app.navigationBars.count,1)
        capture(app,"more-settings-navigation-portrait")
        if app.buttons["Edit"].exists { app.buttons["Edit"].tap(); app.buttons["Done"].tap() }
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.navigationBars["Navigation"].waitForExistence(timeout:5))
        capture(app,"more-settings-navigation-landscape")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.navigationBars["Navigation"].waitForExistence(timeout:5))
        app.terminate()
    }
    func testPausedVideoRotation() {
        let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus")
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments=["--gus-demo-server","--gus-route","play/e324275401dd350d45914c3388b5c8e0"]
        app.launch()
        sleep(5)
        capture(app,"video-start-state")
        app.windows.firstMatch.tap()
        let transport=app.buttons.matching(NSPredicate(format:"identifier == 'Play/Pause' OR label == 'Pause' OR label == 'Play'")).firstMatch
        XCTAssertTrue(transport.waitForExistence(timeout:5))
        if transport.label == "Pause" { transport.tap() }
        capture(app,"video-paused-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        if !transport.exists { app.windows.firstMatch.tap() }
        XCTAssertTrue(transport.waitForExistence(timeout:5))
        XCTAssertEqual(transport.label,"Play")
        capture(app,"video-paused-landscape")
        if app.buttons["Close Button"].exists { app.buttons["Close Button"].tap() }
        app.terminate();XCUIDevice.shared.orientation = .portrait
    }
    func testZAlbumAudioReturn() {
        let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus")
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments=["--gus-demo-server","--gus-route","item/c3cbbf1aaa7b731f859cdddccb9609c8"]
        app.launch()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout:20));app.buttons["Play"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout:15))
        capture(app,"album-audio-player")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.buttons["NowPlaying.reopen"].waitForExistence(timeout:5))
        capture(app,"album-audio-return")
        XCTAssertEqual(app.buttons.matching(identifier:"NowPlaying.reopen").count,1)
        XCTAssertGreaterThanOrEqual(app.buttons["NowPlaying.reopen"].frame.height,44)
        app.buttons["NowPlaying.reopen"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout:5));app.buttons["Stop"].tap()
        app.terminate()
    }
    func testBookReaderRotation() {
        let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus")
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments=["--gus-demo-server","--gus-route","item/778975ecc43b55232b4330c87917f4eb"]
        app.launch()
        let read=app.buttons["Read"]
        XCTAssertTrue(read.waitForExistence(timeout:20));read.tap()
        sleep(4)
        XCTAssertFalse(read.isHittable)
        capture(app,"book-reader-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout:5))
        XCTAssertFalse(read.isHittable)
        capture(app,"book-reader-landscape")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Read"].waitForExistence(timeout:5))
        app.terminate();XCUIDevice.shared.orientation = .portrait
    }
    func testConnectContrastCandidate() throws {
        let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus")
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments=["--gus-skip-session-restore"]
        app.launch()
        sleep(3);capture(app,"connect-top")
        let connect=app.buttons["ConnectServerView.connectButton"]
        for _ in 0..<8 { if connect.exists {break};app.swipeUp() }
        XCTAssertTrue(connect.exists)
        let refresh=app.buttons["Refresh"]
        for _ in 0..<8 { if refresh.isHittable {break};app.swipeUp() }
        XCTAssertTrue(refresh.exists)
        XCTAssertGreaterThanOrEqual(refresh.frame.height,44)
        XCTAssertGreaterThanOrEqual(refresh.frame.width,44)
        capture(app,"connect-standard")
        try app.performAccessibilityAudit(for:[.contrast,.hitRegion,.textClipped]) { issue in
            print("AUDIT_ISSUE connect \(issue)");return true
        }
        app.terminate()
    }
    func testMovieContrast() {
        let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus")
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments=["--gus-demo-server","--gus-route","item/3b54b9d2d41e6a53d5fa6e1dd52b7af1"]
        app.launch();XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout:20))
        capture(app,"movie-contrast")
        app.terminate()
    }
    func testAccessibleBookActions() {
        let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus")
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments=["--gus-demo-server","--gus-route","item/778975ecc43b55232b4330c87917f4eb"]
        app.launch()
        let read=app.buttons["Read"]
        XCTAssertTrue(read.waitForExistence(timeout:20))
        capture(app,"book-large-top")
        for _ in 0..<6 { if read.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(read.isHittable)
        capture(app,"book-large-actions")
        app.terminate()
    }
    func testFullSynopsis() {
        let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus")
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments=["--gus-demo-server","--gus-route","item/e324275401dd350d45914c3388b5c8e0"]
        app.launch();XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout:20))
        let more=app.buttons["Show More"].firstMatch
        for _ in 0..<10 { if more.isHittable {break};app.swipeUp() }
        if !more.isHittable { app.scrollViews.element(boundBy:1).swipeLeft() }
        XCTAssertTrue(more.isHittable);capture(app,"synopsis-card");more.tap()
        capture(app,"full-synopsis")
        XCTAssertTrue(app.buttons["Done"].firstMatch.exists);app.buttons["Done"].firstMatch.tap()
        app.terminate()
    }
    func testConnectCancel() {
        let app=XCUIApplication(bundleIdentifier:"dev.ericslutz.gus")
        app.launchArguments=["--gus-skip-session-restore"]
        app.launch()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout:5))
        app.textFields.firstMatch.tap();app.textFields.firstMatch.typeText("http://127.0.0.1:1")
        app.buttons["ConnectServerView.connectButton"].tap()
        let cancel=app.buttons["ConnectServerView.cancelButton"]
        XCTAssertTrue(cancel.waitForExistence(timeout:3))
        capture(app,"connect-pending")
        cancel.tap()
        XCTAssertTrue(app.buttons["ConnectServerView.connectButton"].isEnabled)
        capture(app,"connect-cancelled")
        app.terminate()
    }
}
