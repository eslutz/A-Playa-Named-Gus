import os
import XCTest
#if os(iOS) || os(tvOS)
    import CoreGraphics
    import ImageIO
    import UIKit
#endif

/// Requires Scripts/demo-server.sh start. Only the rights-cleared localhost fixture
/// is authenticated here; the token is retained in memory and never attached/logged.
@MainActor
final class GusAuthenticatedUITests: XCTestCase {
    private var fixture: [String: String] = [:]

    private func prepare() throws {
        finish()
        continueAfterFailure = false
        executionTimeAllowance = 180
        fixture = try loadFixture()
    }

    override nonisolated func tearDown() async throws {
        await MainActor.run {
            XCUIApplication().terminate()
            #if os(iOS)
                XCUIDevice.shared.orientation = .portrait
            #endif
        }
        try await super.tearDown()
    }

    private func finish() {
        application().terminate()
        #if os(iOS)
            XCUIDevice.shared.orientation = .portrait
        #endif
    }

    func testAudioCloseAndReopen() throws {
        try prepare()
        defer { finish() }
        let app = try launch("play/" + required("Audio"))
        #if os(tvOS)
            XCTAssertTrue(app.cells["AVAudibleSettings"].waitForExistence(timeout: 30))
        #else
            XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 30))
        #endif
        capture(app, "audio-open")
        #if os(iOS)
            rotateToLandscape(app)
            XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
            capture(app, "audio-landscape")
        #endif
        #if os(tvOS)
            for _ in 0 ..< 3 {
                XCUIRemote.shared.press(.menu)
                if app.buttons["NowPlaying.reopen"].waitForExistence(timeout: 2) {
                    break
                }
            }
        #else
            app.buttons["Done"].firstMatch.tap()
        #endif
        let reopen = app.buttons["NowPlaying.reopen"]
        XCTAssertTrue(reopen.waitForExistence(timeout: 10))
        capture(app, "audio-closed")
        #if os(tvOS)
            XCTAssertEqual(app.buttons["NowPlaying.playPause"].label, "Pause")
            try focusTV(app, identifier: "NowPlaying.reopen")
            XCUIRemote.shared.press(.select)
        #else
            reopen.tap()
        #endif
        #if os(tvOS)
            XCTAssertTrue(app.cells["AVAudibleSettings"].waitForExistence(timeout: 10))
        #else
            XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 10))
        #endif
        capture(app, "audio-reopened")
        #if os(tvOS)
            XCUIRemote.shared.press(.menu)
        #else
            app.buttons["Stop"].firstMatch.tap()
        #endif
    }

    func testLoadedDetailLayouts() throws {
        try prepare()
        defer { finish() }
        #if os(iOS)
            let details = [("Movie", "Play"), ("MusicAlbum", "Play"), ("Book", "Read")]
        #elseif os(tvOS)
            let details = [("Movie", "Play"), ("MusicAlbum", "Play")]
        #else
            let details = [("Movie", "Play"), ("MusicAlbum", "Play"), ("Book", "Share")]
        #endif
        for (type, action) in details {
            let app = try launch("item/" + required(type))
            XCTAssertTrue(app.buttons[action].firstMatch.waitForExistence(timeout: 30))
            capture(app, type.lowercased() + "-detail")
            #if os(iOS)
                let window = app.windows.firstMatch.frame
                let button = app.buttons[action].firstMatch
                if button.isHittable {
                    XCTAssertLessThanOrEqual(button.frame.maxX, window.maxX + 1)
                    XCTAssertGreaterThanOrEqual(button.frame.minX, window.minX - 1)
                }
                rotateToLandscape(app)
                reveal(button, in: app)
                XCTAssertTrue(button.isHittable)
                capture(app, type.lowercased() + "-landscape")
                XCUIDevice.shared.orientation = .portrait
            #endif
            app.terminate()
        }
    }

    // visionOS simulator accessibility can return zero-sized spatial frames;
    // review its screen recording for this geometry check instead.
    #if os(iOS) || os(macOS)
        func testDownloadActionMatchesDetailActions() throws {
            try prepare()
            defer { finish() }
            let app = try launch("item/" + required("SynopsisMovie"))
            let download = app.buttons["Detail.download"].firstMatch
            let favorite = app.buttons["Detail.favorite"].firstMatch
            XCTAssertTrue(download.waitForExistence(timeout: 30), app.debugDescription)
            #if os(iOS)
                // The download may already be a disabled status from a prior run.
                // Use the always-interactive neighbor to reveal the action row.
                reveal(favorite, in: app)
            #endif
            capture(app, "download-action-aligned")
            XCTAssertEqual(download.frame.height, favorite.frame.height, accuracy: 1, app.debugDescription)
            XCTAssertEqual(download.frame.width, favorite.frame.width, accuracy: 1, app.debugDescription)
            if download.isEnabled {
                download.tap()
                // Background transfer completion is scheduled by the OS. This
                // regression checks the action-to-status layout transition.
                let started = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !download.isEnabled }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [started], timeout: 10), .completed, app.debugDescription)
            }
            XCTAssertEqual(download.frame.height, favorite.frame.height, accuracy: 1)
            XCTAssertEqual(download.frame.width, favorite.frame.width, accuracy: 1)
            capture(app, "download-status-aligned")
        }
    #endif

    #if os(tvOS)
        func testTVRemediationHeroAndOverflow() throws {
            try prepare()
            executionTimeAllowance = 240
            defer { finish() }
            for kind in ["SynopsisMovie", "Series", "Season"] {
                let app = try launch("item/" + required(kind))
                XCTAssertTrue(app.buttons["Detail.favorite"].waitForExistence(timeout: 30))
                XCUIRemote.shared.press(.right)
                capture(app, "tv-remediation-" + kind.lowercased())
                XCTAssertFalse(app.buttons["Detail.watched"].exists, "Watched belongs in overflow")
                try focusTV(app, identifier: "Detail.more")
                XCUIRemote.shared.press(.select)
                XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "Detail.watched").firstMatch.waitForExistence(timeout: 10))
                capture(app, "tv-remediation-overflow-" + kind.lowercased())
                XCUIRemote.shared.press(.menu)
                app.terminate()
            }
        }

        func testTVRemediationSupplementaryScreens() throws {
            try prepare()
            executionTimeAllowance = 240
            defer { finish() }
            let collection = try launch("item/" + required("BoxSet"))
            XCTAssertTrue(try collection.staticTexts[required("BoxSetTitle")].waitForExistence(timeout: 30))
            XCUIRemote.shared.press(.right)
            try focusTV(collection, label: "More")
            Thread.sleep(forTimeInterval: 1)
            capture(collection, "tv-remediation-collection")
            collection.terminate()
            let app = launch("libraries")
            try focusTV(app, label: "Playlists")
            XCUIRemote.shared.press(.select)
            let title = try required("PlaylistTitle")
            let link = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
            XCTAssertTrue(link.waitForExistence(timeout: 20))
            capture(app, "tv-remediation-playlist-thumbnails")
            try focusTV(app, label: link.label)
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.buttons["Playlist.more"].waitForExistence(timeout: 20))
            try focusTV(app, identifier: "Playlist.addItems")
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10))
            capture(app, "tv-remediation-add-media")
            XCUIRemote.shared.press(.menu)
            app.terminate()
            app.launchArguments = ["--gus-demo-server", "--gus-disable-cloud-sync", "--gus-route", "home"]
            app.launch()
            XCTAssertTrue(app.staticTexts["Recently Added Movies"].waitForExistence(timeout: 30))
            XCUIRemote.shared.press(.menu)
            try focusTV(app, label: "Discover")
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.buttons["Search Seerr"].waitForExistence(timeout: 15))
            XCTAssertFalse(app.searchFields.firstMatch.exists)
            capture(app, "tv-remediation-discover-browse")
            try focusTV(app, label: "Search Seerr")
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10))
            capture(app, "tv-remediation-seerr-search")
        }

        func testTVRemediationNativeAudio() throws {
            try prepare()
            defer { finish() }
            let app = try launch("play/" + required("Audio"))
            XCTAssertTrue(app.cells["AVAudibleSettings"].waitForExistence(timeout: 30))
            let advancing = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let marker = app.otherElements["AXElapsedTime"]
                return marker.exists && marker.label != "00:00"
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [advancing], timeout: 30), .completed)
            XCUIRemote.shared.press(.playPause)
            XCUIRemote.shared.press(.up)
            capture(app, "tv-remediation-native-audio")
            for _ in 0 ..< 3 {
                XCUIRemote.shared.press(.menu)
                if app.buttons["NowPlaying.reopen"].waitForExistence(timeout: 1) {
                    break
                }
            }
            XCTAssertTrue(app.buttons["NowPlaying.reopen"].waitForExistence(timeout: 5))
            capture(app, "tv-remediation-audio-return")
        }

        func testTVMediaReviewRound() throws {
            try prepare()
            executionTimeAllowance = 300
            defer { finish() }
            for kind in ["Movie", "Series", "Episode", "Season", "MusicAlbum", "MusicArtist", "PhotoAlbum", "Photo", "Book"] {
                let app = try launch("item/" + required(kind))
                let name = try required(kind + "Title")
                XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch.waitForExistence(timeout: 20), app.debugDescription)
                let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    !app.progressIndicators.firstMatch.exists
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 20), .completed)
                XCUIRemote.shared.press(.right)
                let sidebarClosed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    app.collectionViews.matching(NSPredicate(format: "label == %@", "Sidebar"))
                        .allElementsBoundByAccessibilityElement.allSatisfy { $0.frame.width < 1 }
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [sidebarClosed], timeout: 5), .completed)
                if kind == "Book" || kind == "PhotoAlbum" {
                    XCTAssertFalse(app.buttons["Detail.play"].exists)
                }
                if kind == "Photo" {
                    let heading = app.descendants(matching: .any)["Photo.heading"]
                    XCTAssertTrue(heading.exists)
                    XCTAssertLessThan(heading.frame.maxY, app.windows.firstMatch.frame.midY)
                }
                capture(app, "tv-aligned-" + kind.lowercased())
                app.terminate()
            }
        }

        func testTVSeerrSetupAndRequestReachability() async throws {
            // Reset only the disposable loopback fixture so this mutation path is repeatable.
            var reset = try URLRequest(url: XCTUnwrap(URL(string: "http://127.0.0.1:5059/__fixture/reset")))
            reset.httpMethod = "POST"
            reset.timeoutInterval = 10
            let resetClient = URLSession(configuration: .ephemeral, delegate: FixtureHTTPClient(), delegateQueue: nil)
            defer { resetClient.invalidateAndCancel() }
            let (_, response) = try await resetClient.data(for: reset)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            try prepare()
            executionTimeAllowance = 360
            defer { finish() }
            let app = launch("settings")
            try focusTV(app, label: "Seerr")
            XCUIRemote.shared.press(.select)
            if app.buttons["Disconnect This Device"].waitForExistence(timeout: 3) {
                try focusTV(app, label: "Disconnect This Device")
                XCUIRemote.shared.press(.select)
                try focusTV(app, label: "Disconnect")
                XCUIRemote.shared.press(.select)
            }
            try focusTV(app, label: "Connect to Seerr")
            XCUIRemote.shared.press(.select)
            try enterTV(app, identifier: "Seerr.serverURL", text: "http://127.0.0.1:5059")
            try focusTV(app, identifier: "Seerr.continue")
            XCUIRemote.shared.press(.select)
            try enterTV(app, identifier: "Seerr.username", text: "fixture@example.invalid")
            try enterTV(app, identifier: "Seerr.password", text: "gus-fixture-only")
            capture(app, "tv-seerr-signin-aligned")
            try focusTV(app, identifier: "Seerr.signIn")
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 20))
            capture(app, "tv-seerr-connected")
            app.terminate()
            app.launchArguments = ["--gus-demo-server", "--gus-disable-cloud-sync", "--gus-route", "home"]
            app.launch()
            XCTAssertTrue(app.staticTexts["Recently Added Movies"].waitForExistence(timeout: 30))
            XCUIRemote.shared.press(.menu)
            try focusTV(app, label: "Discover")
            XCUIRemote.shared.press(.select)
            try focusTV(app, identifier: "Seerr.hero.movie.950000001")
            XCUIRemote.shared.press(.select)
            try focusTV(app, identifier: "Seerr.request")
            let request = app.buttons["Seerr.request"]
            XCTAssertLessThanOrEqual(request.frame.maxY, app.windows.firstMatch.frame.maxY)
            capture(app, "tv-seerr-title-action-visible")
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.buttons["Seerr.submitRequest"].waitForExistence(timeout: 15))
            capture(app, "tv-seerr-request-review")
            try focusTV(app, identifier: "Seerr.submitRequest")
            XCTAssertTrue(app.buttons["Seerr.submitRequest"].isEnabled)
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.staticTexts["Request submitted"].waitForExistence(timeout: 15), app.debugDescription)
            capture(app, "tv-seerr-request-confirmed")
            try focusTV(app, label: "View My Requests")
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.descendants(matching: .any)["Seerr.requests.filter"].waitForExistence(timeout: 15), app.debugDescription)
            XCTAssertTrue(app.staticTexts["Gus Fixture Movie"].waitForExistence(timeout: 10), app.debugDescription)
            capture(app, "tv-seerr-request-history")
        }

        private func enterTV(_ app: XCUIApplication, identifier: String, text: String) throws {
            try focusTV(app, identifier: identifier)
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
            app.typeText(text)
            XCUIRemote.shared.press(.menu)
            let closed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !app.keyboards.firstMatch.exists }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
        }

        func testTVThemeAccentTransactionAndPersistence() throws {
            try prepare()
            executionTimeAllowance = 360
            defer { finish() }
            let app = launch("settings")
            try focusTV(app, identifier: "Settings.theme")
            XCUIRemote.shared.press(.select)
            try focusTV(app, label: "Custom")
            XCUIRemote.shared.press(.select)
            try focusTV(app, identifier: "Settings.accentColor")
            XCUIRemote.shared.press(.select)
            try focusTV(app, identifier: "Theme.preset.007AFF")
            XCUIRemote.shared.press(.select)
            try focusTV(app, label: "Save")
            XCUIRemote.shared.press(.select)
            let accent = app.buttons["Settings.accentColor"]
            XCTAssertTrue(accent.waitForExistence(timeout: 10))
            XCTAssertEqual(accent.value as? String, "007AFF")
            capture(app, "tv-theme-saved-blue")
            app.terminate()
            app.launch()
            XCTAssertTrue(accent.waitForExistence(timeout: 30))
            XCTAssertEqual(accent.value as? String, "007AFF")
            try focusTV(app, identifier: "Settings.accentColor")
            XCUIRemote.shared.press(.select)
            try focusTV(app, identifier: "Theme.preset.FF2D55")
            XCUIRemote.shared.press(.select)
            capture(app, "tv-theme-draft-pink")
            try focusTV(app, label: "Cancel")
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(accent.waitForExistence(timeout: 10))
            XCTAssertEqual(accent.value as? String, "007AFF")
            try focusTV(app, identifier: "Settings.accentColor")
            XCUIRemote.shared.press(.select)
            let erase = String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12)
            try enterTV(app, identifier: "Theme.hex", text: erase + "GG")
            XCTAssertTrue(app.staticTexts["Theme.validation"].exists)
            XCTAssertFalse(app.buttons["Save"].isEnabled)
            capture(app, "tv-theme-invalid-hex")
            try enterTV(app, identifier: "Theme.hex", text: erase + "#12abEF")
            XCTAssertTrue(app.staticTexts["#12ABEF"].exists)
            try focusTV(app, label: "Save")
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(accent.waitForExistence(timeout: 10))
            XCTAssertEqual(accent.value as? String, "12ABEF")
            capture(app, "tv-theme-saved-hex")
        }

        func testTVOnboardingAndDetailComposition() throws {
            try prepare()
            defer { finish() }
            let app = application()
            app.launchArguments = ["--gus-skip-session-restore", "--gus-disable-cloud-sync"]
            app.launch()
            XCTAssertTrue(app.staticTexts["Let’s connect."].waitForExistence(timeout: 20))
            capture(app, "tv-connect-aligned")
            try focusTV(app, identifier: "ConnectServerView.serverAddress")
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
            capture(app, "tv-connect-native-keyboard")
            app.terminate()
            let detail = try launch("item/" + required("SynopsisMovie"))
            try focusTV(detail, identifier: "Detail.play")
            capture(detail, "tv-detail-aligned")
            try focusTV(detail, identifier: "Detail.more")
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(detail.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Add to Playlist")).firstMatch.waitForExistence(timeout: 10))
            capture(detail, "tv-detail-secondary-actions")
            XCUIRemote.shared.press(.menu)
            try focusTV(detail, identifier: "Detail.more")
        }

        func testTVQuickConnectPresentation() throws {
            try prepare()
            defer { finish() }
            let app = application()
            app.launchArguments = ["--gus-skip-session-restore", "--gus-disable-cloud-sync"]
            app.launch()
            try enterTV(app, identifier: "ConnectServerView.serverAddress", text: "http://127.0.0.1:8099")
            try focusTV(app, identifier: "ConnectServerView.connectButton")
            XCUIRemote.shared.press(.select)
            try focusTV(app, label: "More sign-in options")
            XCUIRemote.shared.press(.select)
            try focusTV(app, label: "Use Quick Connect")
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.staticTexts["Authorization code"].waitForExistence(timeout: 15))
            let code = app.staticTexts["Authorization code"]
            XCTAssertTrue(app.windows.firstMatch.frame.contains(code.frame))
            try focusTV(app, label: "Cancel")
            XCUIRemote.shared.press(.select)
            XCTAssertFalse(code.exists)
        }

        private func focusTV(_ app: XCUIApplication, identifier: String? = nil, label: String? = nil) throws {
            let query = app.descendants(matching: .any)
            let target = identifier.map { query.matching(identifier: $0).firstMatch }
                ?? query.matching(NSPredicate(format: "label == %@", label!)).firstMatch
            guard target.waitForExistence(timeout: 15) else {
                XCTFail("Missing focus target " + (identifier ?? label ?? "") + "\n" + app.debugDescription)
                throw FixtureError.missingMedia
            }
            for _ in 0 ..< 30 {
                let key = identifier ?? label!
                let cells = app.cells.containing(NSPredicate(format: "identifier == %@ OR label == %@", key, key))
                let resolved = cells.allElementsBoundByAccessibilityElement.last ?? target
                let destination = resolved.frame
                guard let current = try? focusedTVFrame(app) else {
                    let focused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                        (try? self.focusedTVFrame(app)) != nil
                    }, object: nil)
                    XCTAssertEqual(XCTWaiter.wait(for: [focused], timeout: 5), .completed)
                    continue
                }
                let currentPoint = CGPoint(x: current.midX, y: current.midY)
                let sidebar = app.collectionViews.matching(NSPredicate(format: "label == %@", "Sidebar"))
                    .allElementsBoundByAccessibilityElement.first { $0.frame.contains(currentPoint) }
                if let sidebar,
                   !sidebar.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ OR label == %@", key, key)).firstMatch.exists
                {
                    XCUIRemote.shared.press(.right)
                    continue
                }
                if destination.isEmpty {
                    XCUIRemote.shared.press(.right)
                    continue
                }
                if destination.contains(CGPoint(x: current.midX, y: current.midY)) {
                    return
                }
                let direction: XCUIRemote.Button
                if destination.minY > current.maxY {
                    direction = .down
                } else if destination.maxY < current.minY {
                    direction = .up
                } else if destination.minX > current.maxX {
                    direction = .right
                } else if destination.maxX < current.minX {
                    direction = .left
                } else {
                    direction = destination.midY > current.midY ? .down : .up
                }
                XCUIRemote.shared.press(direction)
            }
            XCTFail("Could not focus " + (identifier ?? label ?? "target") + "\n" + app.debugDescription)
        }

        /// SwiftUI can put native focus on an anonymous Other inside a control.
        /// XCTest's live hierarchy includes its frame even when hasFocus predicates omit it.
        private func focusedTVFrame(_ app: XCUIApplication) throws -> CGRect {
            let description = app.debugDescription
            let pattern = #"\{\{(-?[0-9.]+), (-?[0-9.]+)\}, \{([0-9.]+), ([0-9.]+)\}\}[^\n]*Focused"#
            let expression = try NSRegularExpression(pattern: pattern)
            guard let match = expression.firstMatch(in: description, range: NSRange(description.startIndex..., in: description)) else { throw FixtureError.missingMedia }
            let values = try (1 ... 4).map { index in
                let range = try XCTUnwrap(Range(match.range(at: index), in: description))
                return try XCTUnwrap(Double(description[range]))
            }
            return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        }

        private func tvHasFocus(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
            guard let frame = try? focusedTVFrame(app) else { return false }
            return element.frame.contains(CGPoint(x: frame.midX, y: frame.midY))
        }

        /// Sample actual Settings rendering so a descendant color-scheme override cannot hide behind a saved preference.
        func testTVAppearancePreference() throws {
            try prepare()
            defer { finish() }
            let app = application()
            for appearance in ["light", "dark", "system"] {
                app.launchArguments = [
                    "--gus-demo-server",
                    "--gus-disable-cloud-sync",
                    "--gus-route",
                    "settings",
                    "-dev.ericslutz.gus.appearance",
                    appearance,
                ]
                app.launch()
                XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Account")).firstMatch.waitForExistence(timeout: 30))
                capture(app, "tv-settings-" + appearance)
                if appearance != "system" {
                    let screenshot = XCUIScreen.main.screenshot()
                    let source = try XCTUnwrap(CGImageSourceCreateWithData(screenshot.pngRepresentation as CFData, nil))
                    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
                    var pixel = [UInt8](repeating: 0, count: 4)
                    try pixel.withUnsafeMutableBytes { storage in
                        let context = try XCTUnwrap(CGContext(
                            data: storage.baseAddress,
                            width: 1,
                            height: 1,
                            bitsPerComponent: 8,
                            bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        ))
                        context.interpolationQuality = .high
                        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                    }
                    let brightness = pixel.prefix(3).map(Double.init).reduce(0, +) / 3
                    if appearance == "light" {
                        XCTAssertGreaterThan(brightness, 128, "Light must render a light Settings screen")
                    } else {
                        XCTAssertLessThan(brightness, 128, "Dark must render a dark Settings screen")
                    }
                }
                app.terminate()
            }
            for (route, landmark, name) in try [("home", "Recently Added Movies", "tv-home-light"), ("item/" + required("SynopsisMovie"), "Play", "tv-detail-light")] {
                app.launchArguments = [
                    "--gus-demo-server",
                    "--gus-disable-cloud-sync",
                    "--gus-route",
                    route,
                    "-dev.ericslutz.gus.appearance",
                    "light",
                ]
                app.launch()
                XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", landmark)).firstMatch.waitForExistence(timeout: 30))
                capture(app, name)
                app.terminate()
            }
        }

        func testTVSidebarProfile() throws {
            try prepare()
            defer { finish() }
            let app = launch("home")
            XCTAssertTrue(app.staticTexts["Recently Added Movies"].firstMatch.waitForExistence(timeout: 30))
            XCUIRemote.shared.press(.menu)
            let account = app.buttons["Account"].firstMatch
            XCTAssertTrue(account.waitForExistence(timeout: 5), app.debugDescription)
            for _ in 0 ..< 12 {
                if account.hasFocus || account.descendants(matching: .any).allElementsBoundByIndex.contains(where: \.hasFocus) {
                    break
                }
                XCUIRemote.shared.press(.up)
            }
            XCTAssertTrue(account.hasFocus || account.descendants(matching: .any).allElementsBoundByIndex.contains(where: \.hasFocus), app.debugDescription)
            capture(app, "tv-sidebar-profile")
            XCUIRemote.shared.press(.select)
            let edit = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "View and Edit Profile")).firstMatch
            XCTAssertTrue(edit.waitForExistence(timeout: 5), app.debugDescription)
            XCUIRemote.shared.press(.select)
            let username = app.textFields["Username"]
            XCTAssertTrue(username.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertEqual(username.value as? String, "gus")
            try focusTV(app, label: "Save")
            XCUIRemote.shared.press(.select)
            XCTAssertFalse(app.textFields["Username"].waitForExistence(timeout: 2))
            capture(app, "tv-profile-saved")
        }

        func testTVPlaybackDetails() throws {
            try prepare()
            defer { finish() }
            let app = try launch("play/" + required("SynopsisMovie"))
            let infoMenu = app.collectionViews["AVInfoMenuCollection"]
            XCTAssertTrue(infoMenu.waitForExistence(timeout: 30), app.debugDescription)
            XCUIRemote.shared.press(.playPause)
            // Down opens the native Info panel; Up returns from its content to
            // the tab strip, where the next tab is our custom details panel.
            XCUIRemote.shared.press(.down)
            XCUIRemote.shared.press(.down)
            XCUIRemote.shared.press(.up)
            // AVKit delegates focus to a full-viewport container, so its tab
            // strip uses native remote movement rather than SwiftUI frame matching.
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Playback Details")).firstMatch.waitForExistence(timeout: 5))
            XCUIRemote.shared.press(.right)
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.staticTexts["How this video is being played"].waitForExistence(timeout: 5), app.debugDescription)
            XCUIRemote.shared.press(.down)
            capture(app, "tv-playback-details")
        }

        /// Exercise the native remote through the hero and the lower detail content.
        func testTVDetailFocusAndAboutLayout() throws {
            try prepare()
            defer { finish() }
            let app = try launch("item/" + required("SynopsisMovie"))
            let play = app.buttons["Play"].firstMatch
            XCTAssertTrue(play.waitForExistence(timeout: 30))
            let focused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in play.hasFocus }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [focused], timeout: 10), .completed)
            capture(app, "tv-detail-play-focused")

            let common = ["Detail.nextUp", "Detail.favorite", "Detail.more"].map { app.buttons[$0] }
            for button in common {
                XCTAssertTrue(button.exists)
                XCTAssertGreaterThan(button.frame.minY, play.frame.maxY)
            }
            for (index, button) in common.enumerated() {
                try focusTV(app, identifier: button.identifier)
                if index == 1 {
                    let originalLabel = button.label
                    XCUIRemote.shared.press(.select)
                    let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in button.label != originalLabel && button.isEnabled }, object: nil)
                    XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed)
                    XCUIRemote.shared.press(.select)
                    let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in button.label == originalLabel && button.isEnabled }, object: nil)
                    XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 10), .completed)
                }
                if index == 2 {
                    XCUIRemote.shared.press(.select)
                    try focusTV(app, label: "Add to Playlist")
                    XCUIRemote.shared.press(.select)
                    XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
                    XCUIRemote.shared.press(.menu)
                    let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.tvHasFocus(button, in: app) }, object: nil)
                    XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed, app.debugDescription)
                    capture(app, "tv-playlist-return-focus")
                }
            }
            try focusTV(app, identifier: "Detail.more")
            let more = app.buttons["Detail.more"]
            let moreFocused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                self.tvHasFocus(more, in: app)
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [moreFocused], timeout: 5), .completed, app.debugDescription)
            capture(app, "tv-detail-more-focused")
            XCUIRemote.shared.press(.select)
            // Native tvOS menu entries are exposed as Other elements inside focused cells.
            let restart = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Start from Beginning")).firstMatch
            XCTAssertTrue(restart.waitForExistence(timeout: 5), app.debugDescription)
            capture(app, "tv-detail-overflow")
            XCUIRemote.shared.press(.menu)
            let menuDismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !restart.exists }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [menuDismissed], timeout: 5), .completed)
            try focusTV(app, label: "Synopsis")
            let synopsis = app.buttons["Synopsis"]
            let synopsisFocused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in synopsis.hasFocus }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [synopsisFocused], timeout: 5), .completed, app.debugDescription)
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
            capture(app, "tv-full-synopsis")
            XCUIRemote.shared.press(.menu)

            let fullSynopsis = app.buttons["Detail.fullSynopsis"]
            for _ in 0 ..< 24 {
                if fullSynopsis.exists, fullSynopsis.hasFocus {
                    break
                }
                XCUIRemote.shared.press(.down)
            }
            // The first About card is a readable focus target to the left of Show More.
            if !fullSynopsis.hasFocus {
                XCUIRemote.shared.press(.right)
            }
            let aboutFocused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in fullSynopsis.hasFocus }, object: nil)
            let aboutResult = XCTWaiter.wait(for: [aboutFocused], timeout: 5)
            capture(app, "tv-about-focus-result")
            XCTAssertEqual(aboutResult, .completed, app.debugDescription)
            let window = app.windows.firstMatch.frame
            XCTAssertTrue(window.contains(fullSynopsis.frame))
            capture(app, "tv-about-focused")

            app.terminate()
            app.launchArguments = ["--gus-demo-server", "--gus-disable-cloud-sync"]
            app.launch()
            XCTAssertTrue(app.staticTexts["Recently Added Movies"].firstMatch.waitForExistence(timeout: 30))
            let card = try app.buttons.matching(NSPredicate(format: "label CONTAINS %@", required("MovieTitle"))).firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 10))
            try focusTV(app, label: card.label)
            capture(app, "tv-home-cards")
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.buttons["Detail.play"].waitForExistence(timeout: 15))
            XCUIRemote.shared.press(.menu)
            let homeFocused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in card.hasFocus }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [homeFocused], timeout: 10), .completed, app.debugDescription)
            capture(app, "tv-home-detail-return")
        }
    #endif

    #if os(iOS)
        func testRightToLeftLoadedDetails() throws {
            try prepare()
            defer { finish() }
            for (type, action) in [("Movie", "Play"), ("MusicAlbum", "Play"), ("Book", "Read")] {
                let app = application()
                app.launchArguments = try [
                    "--gus-demo-server",
                    "--gus-route",
                    "item/" + required(type),
                    "-AppleLanguages",
                    "(ar)",
                    "-AppleLocale",
                    "ar_SA",
                    "-AppleTextDirection",
                    "YES",
                    "-NSForceRightToLeftWritingDirection",
                    "YES",
                ]
                app.launch()
                let button = app.buttons[action].firstMatch
                XCTAssertTrue(button.waitForExistence(timeout: 30))
                reveal(button, in: app)
                XCTAssertTrue(button.isHittable)
                XCTAssertGreaterThan(app.buttons["ContentLink.detailDone"].frame.midX, app.windows.firstMatch.frame.midX)
                capture(app, type.lowercased() + "-rtl")
                rotateToLandscape(app)
                reveal(button, in: app)
                XCTAssertTrue(button.isHittable)
                capture(app, type.lowercased() + "-rtl-landscape")
                app.terminate()
                XCUIDevice.shared.orientation = .portrait
            }
        }

        func testBookReaderDismissal() throws {
            try prepare()
            defer { finish() }
            let app = try launch("item/" + required("Book"))
            let read = app.buttons["Read"].firstMatch
            XCTAssertTrue(read.waitForExistence(timeout: 30))
            for _ in 0 ..< 8 {
                if read.isHittable {
                    break
                }
                app.swipeUp()
            }
            read.tap()
            XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 30))
            // Readium nests WebKit accessibility containers and can still be
            // paginating after the web view first appears on a busy simulator.
            XCTAssertTrue(app.webViews.descendants(matching: .staticText).firstMatch.waitForExistence(timeout: 75))
            XCTAssertFalse(read.isHittable)
            capture(app, "book-reader")
            rotateToLandscape(app)
            XCTAssertTrue(app.buttons["BookReader.done"].waitForExistence(timeout: 5))
            capture(app, "book-reader-landscape")
            app.buttons["BookReader.done"].tap()
            XCTAssertFalse(app.webViews.firstMatch.exists)
            reveal(app.buttons["Read"].firstMatch, in: app)
            capture(app, "book-reader-dismissed")
            XCTAssertTrue(app.buttons["Read"].firstMatch.isHittable)
        }

        func testBookReaderNestedChapters() throws {
            try prepare()
            executionTimeAllowance = 300
            defer { finish() }
            // The rights-cleared Dracula fixture groups its chapters under the
            // book title, so a flat top-level menu cannot reach chapter I.
            let app = try launch("item/" + required("NestedBook"))
            let read = app.buttons["Read"].firstMatch
            XCTAssertTrue(read.waitForExistence(timeout: 30))
            reveal(read, in: app)
            read.tap()
            let bookText = app.webViews.descendants(matching: .staticText)
            XCTAssertTrue(bookText.firstMatch.waitForExistence(timeout: 75))
            app.buttons["Chapters"].tap()
            XCTAssertTrue(app.buttons["BookChapters.done"].waitForExistence(timeout: 5))
            capture(app, "book-chapters-top-level")
            let menuTree = XCTAttachment(string: app.debugDescription)
            menuTree.name = "book-chapters-tree"
            menuTree.lifetime = .keepAlways
            add(menuTree)
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            let group = app.buttons["BookChapters.group.Dracula"].firstMatch
            reveal(group, in: app)
            group.tap()
            let chapter = app.buttons["I"]
            XCTAssertTrue(chapter.waitForExistence(timeout: 5))
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            capture(app, "book-nested-chapters")
            chapter.tap()
            let chapterText = bookText.matching(NSPredicate(format: "label CONTAINS[c] 'Harker'")).firstMatch
            XCTAssertTrue(chapterText.waitForExistence(timeout: 30))
            let readerDone = app.buttons["BookReader.done"].firstMatch
            let chapterClosed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                !app.buttons["BookChapters.done"].firstMatch.isHittable && readerDone.isHittable
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [chapterClosed], timeout: 30), .completed)
            capture(app, "book-chapter-one")
            rotateToLandscape(app)
            XCTAssertTrue(chapterText.waitForExistence(timeout: 15))
            XCTAssertTrue(app.buttons["BookReader.done"].isHittable)
            capture(app, "book-chapter-landscape")
            // Use the actual landscape window for reader-edge input. App-level
            // coordinates and paginated WebKit text bounds can be misleading.
            let paragraph = bookText.matching(NSPredicate(format: "label CONTAINS[c] 'Bistritz'")).firstMatch
            let heading = bookText.matching(NSPredicate(format: "label == 'I'")).firstMatch
            let window = app.windows.firstMatch
            let bounds = XCTAttachment(string: "App: \(app.frame)\nWindow: \(window.frame)\nHeading: \(heading.frame)")
            bounds.name = "book-reader-input-bounds"
            bounds.lifetime = .keepAlways
            add(bounds)
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.65)).tap()
            capture(app, "book-page-forward-immediate")
            Thread.sleep(forTimeInterval: 2)
            XCTAssertTrue(paragraph.waitForExistence(timeout: 15))
            // Paginated WebKit text can span columns and have no activation
            // point. Its prose is verified by the saved screen, not hit-testing.
            capture(app, "book-prose-landscape")
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.65)).tap()
            capture(app, "book-page-back-immediate")
            // WebKit exposes the whole chapter DOM while its native spread
            // transition completes. Give the backwards page a bounded settle
            // before closing; saved screens establish which page is visible.
            Thread.sleep(forTimeInterval: 5)
            capture(app, "book-page-back-landscape")
            let doneBounds = XCTAttachment(string: "Reader Done: \(readerDone.frame)\nWindow: \(window.frame)")
            doneBounds.name = "book-reader-done-bounds"
            doneBounds.lifetime = .keepAlways
            add(doneBounds)
            XCTAssertTrue(readerDone.isHittable)
            readerDone.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                read.isHittable && !readerDone.isHittable
            }, object: nil)
            let dismissalResult = XCTWaiter.wait(for: [dismissed], timeout: 30)
            capture(app, "book-reader-close-result")
            XCTAssertEqual(dismissalResult, .completed)
            reveal(read, in: app)
            XCTAssertTrue(read.isHittable)
            capture(app, "book-chapter-dismissed")
        }

        func testConnectCurrentScreenAccessibility() throws {
            try prepare()
            defer { finish() }
            for size in [nil, UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue] as [String?] {
                let app = application()
                app.launchArguments = ["--gus-skip-session-restore"]
                if let size {
                    app.launchArguments += ["-UIPreferredContentSizeCategoryName", size]
                }
                app.launch()
                let field = app.textFields["ConnectServerView.serverAddress"]
                XCTAssertTrue(field.waitForExistence(timeout: 10))
                field.tap()
                field.typeText("http://127.0.0.1:8096")
                XCTAssertEqual(field.value as? String, "http://127.0.0.1:8096")
                if size != nil {
                    XCTAssertGreaterThanOrEqual(app.staticTexts["Connect to Jellyfin"].frame.height, 40)
                }
                capture(app, size == nil ? "connect-input" : "connect-input-ax5")
                try app.performAccessibilityAudit(for: [.hitRegion, .textClipped]) { issue in
                    print("Accessibility issue type: \(issue.auditType); element: \(issue.element?.debugDescription ?? "unidentified"); URL field frame: \(field.frame)")
                    // Native single-line URL entry scrolls horizontally. The audit warns
                    // about clipping even though the complete typed value is preserved.
                    // This exception is limited to this exact, hittable field and type.
                    // Its native Form row supplies the audited >=44 pt touch region;
                    // the intrinsic text rectangle is smaller than the row.
                    if issue.auditType == .textClipped,
                       issue.element?.identifier == "ConnectServerView.serverAddress",
                       field.isHittable,
                       app.cells.containing(.textField, identifier: "ConnectServerView.serverAddress").firstMatch.frame.height >= 44
                    {
                        print("Accepted URL-field textClipped: verified horizontal entry and complete value")
                        return true
                    }
                    return false
                }
                app.terminate()
            }
        }

        func testFullSynopsisHeading() throws {
            try prepare()
            defer { finish() }
            let app = try launch("item/" + required("SynopsisMovie"))
            XCTAssertTrue(app.buttons["Play"].firstMatch.waitForExistence(timeout: 30))
            let more = app.buttons["Detail.fullSynopsis"].firstMatch
            for _ in 0 ..< 10 {
                if more.isHittable {
                    break
                }
                app.swipeUp()
            }
            for _ in 0 ..< 3 {
                if more.isHittable {
                    break
                }
                app.swipeUp()
            }
            XCTAssertTrue(more.isHittable)
            more.tap()
            let heading = app.staticTexts["Synopsis.heading"]
            XCTAssertTrue(heading.waitForExistence(timeout: 10))
            XCTAssertEqual(heading.label, try required("SynopsisMovieTitle"))
            capture(app, "full-synopsis")
            app.buttons["Synopsis.done"].tap()
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !heading.exists }, object: nil)
            let dismissalResult = XCTWaiter.wait(for: [dismissed], timeout: 10)
            capture(app, "synopsis-dismissed")
            XCTAssertEqual(dismissalResult, .completed, app.debugDescription)
        }

        func testLargestTextAuthenticatedDetails() throws {
            try prepare()
            defer { finish() }
            for (type, action) in [("Movie", "Play"), ("MusicAlbum", "Play"), ("Book", "Read")] {
                let app = application()
                app.launchArguments = try [
                    "--gus-demo-server",
                    "--gus-route",
                    "item/" + required(type),
                    "-UIPreferredContentSizeCategoryName",
                    UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
                ]
                app.launch()
                let button = app.buttons[action].firstMatch
                XCTAssertTrue(button.waitForExistence(timeout: 30))
                reveal(button, in: app)
                XCTAssertTrue(button.isHittable)
                XCTAssertGreaterThanOrEqual(button.frame.height, 44)
                capture(app, type.lowercased() + "-ax5")
                app.terminate()
            }
        }

        func testDetailCurrentScreenAccessibility() throws {
            try prepare()
            defer { finish() }
            let app = try launch("item/" + required("SynopsisMovie"))
            XCTAssertTrue(app.buttons["Play"].firstMatch.waitForExistence(timeout: 30))
            capture(app, "movie-audit")
            if UIDevice.current.userInterfaceIdiom == .pad {
                // Xcode 27's form-sheet contrast scanner samples clipped/offscreen
                // descendants against the underlying Home window (RV-015). Keep
                // native geometry/description auditing and independent rendered
                // checks; record native iPad contrast as blocked, never as passed.
                try app.performAccessibilityAudit(for: [.hitRegion, .sufficientElementDescription])
                for element in [app.buttons["ContentLink.detailDone"], app.buttons["Play"].firstMatch] {
                    XCTAssertTrue(element.isEnabled)
                    XCTAssertTrue(element.isHittable)
                    XCTAssertGreaterThanOrEqual(try renderedLabelContrast(element), 4.5)
                }
                print("Native iPad contrast blocked by documented offscreen form-sheet sampling; visible primary-control pixel checks passed")
                return
            }
            var renderedChecks: [String: XCUIElement] = [:]
            try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .sufficientElementDescription]) { issue in
                print("Strict movie audit: \(issue.auditType); element: \(issue.element?.debugDescription ?? "unlocated")")
                guard issue.auditType == .contrast else { return false }
                // Classify only documented native contrast false positives. Pixel checks
                // run after the native audit so revealing a clipped element cannot move
                // the viewport underneath the auditor's remaining cached samples.
                let done = app.buttons["ContentLink.detailDone"]
                if issue.element?.identifier == "ContentLink.detailDone",
                   done.label == "Done", done.isEnabled
                {
                    renderedChecks["ContentLink.detailDone"] = done
                    return true
                }
                let play = app.buttons["Play"].firstMatch
                if issue.element?.identifier == "Detail.play",
                   issue.element?.label == "Play", play.isEnabled
                {
                    renderedChecks["Detail.play"] = play
                    return true
                }
                return false
            }
            for key in renderedChecks.keys.sorted() {
                let element = try XCTUnwrap(renderedChecks[key])
                for _ in 0 ..< 10 {
                    if element.isHittable {
                        break
                    }
                    let contentTop = app.buttons["ContentLink.detailDone"].frame.maxY
                    if (element.exists && element.frame.maxY < contentTop) || (!element.exists && key == "Detail.play") {
                        app.swipeDown()
                    } else {
                        app.swipeUp()
                    }
                }
                XCTAssertTrue(element.isHittable, "Unreachable contrast-disposition element: " + key)
                XCTAssertGreaterThanOrEqual(try renderedLabelContrast(element), 4.5, "Rendered contrast: " + key)
                print("Accepted measured native contrast disposition: \(key)")
            }
        }
    #endif

    #if os(iOS)
        /// Sample the central text portion of these two known native labels. Frequent
        /// solid colors exclude isolated antialias pixels; this is a local contrast
        /// guard, not an all-screen image audit or permission to ignore other issues.
        private func renderedLabelContrast(_ element: XCUIElement) throws -> Double {
            let screenshot = element.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "contrast-guard-" + (element.identifier.isEmpty ? element.label : element.identifier)
            attachment.lifetime = .keepAlways
            add(attachment)
            let source = try XCTUnwrap(CGImageSourceCreateWithData(screenshot.pngRepresentation as CFData, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let width = image.width, height = image.height
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            try pixels.withUnsafeMutableBytes { storage in
                let context = try XCTUnwrap(CGContext(
                    data: storage.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
                ))
                context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            }
            var histogram: [UInt32: Int] = [:]
            for y in Int(Double(height) * 0.2) ..< Int(Double(height) * 0.8) {
                for x in Int(Double(width) * 0.48) ..< Int(Double(width) * 0.64) {
                    let index = (y * width + x) * 4
                    let rgb = UInt32(pixels[index]) << 16 | UInt32(pixels[index + 1]) << 8 | UInt32(pixels[index + 2])
                    histogram[rgb, default: 0] += 1
                }
            }
            let dominant = try XCTUnwrap(histogram.max { $0.value < $1.value }?.key)
            func luminance(_ rgb: UInt32) -> Double {
                let components = [Double((rgb >> 16) & 255), Double((rgb >> 8) & 255), Double(rgb & 255)].map { $0 / 255 }
                    .map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
                return components[0] * 0.2126 + components[1] * 0.7152 + components[2] * 0.0722
            }
            let baseline = luminance(dominant)
            let minimumCount = max(2, histogram.values.reduce(0, +) / 1000)
            let ratio = histogram.filter { $0.value >= minimumCount }.keys.map {
                let other = luminance($0)
                return (max(baseline, other) + 0.05) / (min(baseline, other) + 0.05)
            }.max() ?? 1
            print("Rendered native label contrast: \(element.identifier), ratio \(ratio)")
            return ratio
        }

        private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
            for _ in 0 ..< 10 {
                let window = app.windows.firstMatch.frame
                if element.isHittable, element.frame.height >= 44,
                   element.frame.minY >= window.minY + 44,
                   element.frame.maxY <= window.maxY - 24
                {
                    return
                }
                app.swipeUp()
            }
        }

        private func rotateToLandscape(_ app: XCUIApplication) {
            XCUIDevice.shared.orientation = .landscapeLeft
            let deadline = Date().addingTimeInterval(10)
            while app.windows.firstMatch.frame.width <= app.windows.firstMatch.frame.height, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.2)
            }
            XCTAssertGreaterThan(app.windows.firstMatch.frame.width, app.windows.firstMatch.frame.height)
        }
    #endif

    private func application() -> XCUIApplication {
        let app = XCUIApplication()
        if let address = ProcessInfo.processInfo.environment["GUS_DEMO_URL"] {
            app.launchEnvironment["GUS_DEMO_URL"] = address
        }
        return app
    }

    private func launch(_ route: String) -> XCUIApplication {
        let app = application()
        app.launchArguments = ["--gus-demo-server", "--gus-disable-cloud-sync", "--gus-route", route]
        app.launch()
        return app
    }

    private func required(_ type: String) throws -> String {
        try XCTUnwrap(fixture[type], "Required demo media missing: " + type)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func loadFixture() throws -> [String: String] {
        func request(_ path: String, body: [String: String]? = nil, token: String? = nil) throws -> [String: Any] {
            var request = URLRequest(url: URL(string: (ProcessInfo.processInfo.environment["GUS_DEMO_URL"] ?? "http://127.0.0.1:8096") + path)!)
            request.timeoutInterval = 10
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("MediaBrowser Client=\"GusValidation\", Device=\"XCTest\", DeviceId=\"gus-validation\", Version=\"1.0.0\"", forHTTPHeaderField: "Authorization")
            if let token {
                request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
            }
            if let body {
                request.httpMethod = "POST"
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            }
            // The ephemeral fixture client never follows a redirect to another host.
            let semaphore = DispatchSemaphore(value: 0)
            let box = OSAllocatedUnfairLock(initialState: FixtureResponse())
            let client = FixtureHTTPClient()
            let session = URLSession(configuration: .ephemeral, delegate: client, delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            session.dataTask(with: request) { data, response, error in
                box.withLock { state in
                    state.data = data
                    state.succeeded = error == nil && (response as? HTTPURLResponse)?.statusCode == 200 && response?.url?.host == "127.0.0.1"
                }
                semaphore.signal()
            }.resume()
            guard semaphore.wait(timeout: .now() + 15) == .success else { throw FixtureError.unavailable }
            let response = box.withLock { $0 }
            guard response.succeeded, let data = response.data,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { throw FixtureError.unavailable }
            return object
        }
        let auth = try request("/Users/AuthenticateByName", body: ["Username": "gus", "Pw": "playa-demo"])
        guard let user = auth["User"] as? [String: Any], let userID = user["Id"] as? String,
              let token = auth["AccessToken"] as? String
        else { throw FixtureError.unavailable }
        let response = try request("/Users/\(userID)/Items?Recursive=true&Limit=1000&Fields=Overview", token: token)
        let items = response["Items"] as? [[String: Any]] ?? []
        var result: [String: String] = [:]
        for type in ["Audio", "Movie", "MusicAlbum", "Book"] {
            let candidates = items.filter { $0["Type"] as? String == type }
            let selected = type == "Audio" ? candidates.max(by: { ($0["RunTimeTicks"] as? Double ?? 0) < ($1["RunTimeTicks"] as? Double ?? 0) }) : candidates.first
            guard let item = selected, let id = item["Id"] as? String else {
                throw FixtureError.missingMedia
            }
            result[type] = id
            if type == "Movie" {
                result["MovieTitle"] = item["Name"] as? String
            }
        }
        if let book = items.first(where: { $0["Type"] as? String == "Book" && $0["Name"] as? String == "Dracula" }) {
            result["NestedBook"] = book["Id"] as? String
        }
        guard let synopsisMovie = items.filter({
            $0["Type"] as? String == "Movie" && !($0["Overview"] as? String ?? "").isEmpty
        }).max(by: { ($0["Name"] as? String ?? "").count < ($1["Name"] as? String ?? "").count }),
              let id = synopsisMovie["Id"] as? String, let title = synopsisMovie["Name"] as? String
        else { throw FixtureError.missingMedia }
        result["SynopsisMovie"] = id
        result["SynopsisMovieTitle"] = title
        for type in ["Movie", "Series", "Episode", "Season", "MusicAlbum", "MusicArtist", "PhotoAlbum", "Photo", "Book", "BoxSet", "Playlist"] {
            if let item = items.first(where: { $0["Type"] as? String == type }), let id = item["Id"] as? String {
                result[type] = id
                result[type + "Title"] = item["Name"] as? String
            }
        }
        if result["MusicArtist"] == nil {
            let artists = try request("/Artists?UserId=\(userID)&Limit=1", token: token)
            if let artist = (artists["Items"] as? [[String: Any]])?.first {
                result["MusicArtist"] = artist["Id"] as? String
                result["MusicArtistTitle"] = artist["Name"] as? String
            }
        }
        return result
    }

    private enum FixtureError: Error { case unavailable, missingMedia }
}

private struct FixtureResponse: Sendable {
    var data: Data?
    var succeeded = false
}

private final class FixtureHTTPClient: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
