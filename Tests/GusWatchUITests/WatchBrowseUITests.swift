import XCTest

/// Run on a 40 mm Watch with the rights-cleared local Jellyfin demo running.
@MainActor
final class WatchBrowseUITests: XCTestCase {
    func testAlbumOpensTracksAndAudioPauses() {
        continueAfterFailure = false
        executionTimeAllowance = 180
        let app = XCUIApplication(bundleIdentifier: "dev.ericslutz.gus.watchkitapp")
        app.launchArguments = ["--gus-demo-server"]
        app.launch()
        defer { app.terminate() }
        let music = app.buttons["Music"].firstMatch
        for _ in 0 ..< 8 {
            if music.exists {
                break
            }
            if app.navigationBars["Browse"].exists, music.waitForExistence(timeout: 15) {
                break
            }
            if app.navigationBars["Settings"].exists || app.navigationBars["Downloads"].exists {
                app.swipeDown(velocity: .slow)
            } else {
                app.swipeUp(velocity: .slow)
            }
        }
        XCTAssertTrue(music.waitForExistence(timeout: 10))
        music.tap()
        let album = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "PUBLIC DOMAIN")).firstMatch
        XCTAssertTrue(album.waitForExistence(timeout: 15))
        capture(app, "watch-music")
        album.tap()
        let track = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Whispers")).firstMatch
        let tracksVisible = track.waitForExistence(timeout: 15)
        capture(app, "watch-track-state")
        if !tracksVisible {
            print(app.debugDescription)
        }
        XCTAssertTrue(tracksVisible)
        capture(app, "watch-tracks")
        track.tap()
        let pause = app.buttons["Pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 15))
        capture(app, "watch-audio")
        pause.tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
        capture(app, "watch-paused")
    }

    func testWatchSearchOpensWithoutCloudConsent() throws {
        guard #available(watchOS 27, *) else { throw XCTSkip("Watch Search requires watchOS 27.") }
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "dev.ericslutz.gus.watchkitapp")
        app.launchArguments = ["--gus-demo-server"]
        app.launch()
        defer { app.terminate() }
        let searchLink = app.buttons["Watch.Browse.search"]
        for _ in 0 ..< 8 {
            if searchLink.waitForExistence(timeout: 2), searchLink.isHittable {
                break
            }
            if app.navigationBars["Settings"].exists || app.navigationBars["Downloads"].exists {
                app.swipeDown(velocity: .slow)
            } else {
                app.swipeUp(velocity: .slow)
            }
        }
        XCTAssertTrue(searchLink.waitForExistence(timeout: 8))
        searchLink.tap()
        XCTAssertTrue(app.navigationBars["Search Library"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Natural Language"].exists)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
