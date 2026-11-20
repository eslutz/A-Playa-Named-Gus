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

    func testWatchSearchOpensWithoutCloudConsent() {
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

    func testWatchForYouInvitationPersistsNotNow() throws {
        guard #available(watchOS 27, *) else { throw XCTSkip("Watch intelligence requires watchOS 27.") }
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "dev.ericslutz.gus.watchkitapp")
        app.launchArguments = ["--gus-demo-server", "--gus-intelligence-test-cloud", "--gus-intelligence-test-suite", UUID().uuidString]
        app.launch()
        defer { app.terminate() }
        let title = app.staticTexts["Enable For You?"]
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        let message = app.staticTexts["Intelligence.prompt.message"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertEqual(message.label, "Get recommendations based on your Jellyfin favorites and playback history. You can change this in Gus Settings → Library Intelligence → Show For You.")
        let decline = app.buttons["Intelligence.prompt.decline"]
        for _ in 0 ..< 5 where !decline.isHittable {
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(decline.isHittable)
        decline.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["Remote"].waitForExistence(timeout: 20))
        XCTAssertFalse(title.waitForExistence(timeout: 2))
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
