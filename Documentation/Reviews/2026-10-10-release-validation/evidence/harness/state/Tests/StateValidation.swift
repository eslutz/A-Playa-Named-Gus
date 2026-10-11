import XCTest

@MainActor
final class StateValidation: XCTestCase {
    private var preferenceBaseline: [String: String] = [:]
    private func accessibilitySettings(_ section: String) -> XCUIApplication {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        for _ in 0 ..< 10 {
            if settings.buttons["MOTION_TITLE"].exists {
                break
            }
            if settings.buttons["BackButton"].exists {
                settings.buttons["BackButton"].tap()
            } else if settings.staticTexts["Accessibility"].firstMatch.isHittable {
                settings.staticTexts["Accessibility"].firstMatch.tap()
            } else {
                settings.swipeUp()
            }
        }
        let row = settings.buttons[section]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        return settings
    }

    private func setPreference(_ id: String, value: String, settings: XCUIApplication) {
        let control = settings.switches[id]
        for _ in 0 ..< 6 {
            if control.isHittable {
                break
            }
            settings.swipeUp()
        }
        XCTAssertTrue(control.isHittable)
        if control.value as? String != value {
            let toggle = control.switches.firstMatch
            if toggle.exists {
                toggle.tap()
            } else {
                control.tap()
            }
        }
        XCTAssertTrue(NSPredicate(format: "value == %@", value).evaluate(with: control) || XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: control)], timeout: 5) == .completed)
        XCTAssertEqual(control.value as? String, value)
    }

    private func restorePreferences() {
        guard !preferenceBaseline.isEmpty else { return }
        let motion = accessibilitySettings("MOTION_TITLE")
        if let value = preferenceBaseline["REDUCE_MOTION"] {
            setPreference("REDUCE_MOTION", value: value, settings: motion)
        }
        let display = accessibilitySettings("DISPLAY_AND_TEXT")
        for id in ["ENHANCE_TEXT_LEGIBILITY", "REDUCE_TRANSPARENCY", "DIFFERENTIATE_WITHOUT_COLOR"] {
            if let value = preferenceBaseline[id] {
                setPreference(id, value: value, settings: display)
            }
        }
        let a = XCTAttachment(string: "Restored accessibility baseline: \(preferenceBaseline)")
        a.name = "accessibility-preferences-restored"; a.lifetime = .keepAlways; add(a)
        preferenceBaseline.removeAll()
    }

    func testReducedEffectsAndColorIndependence() throws {
        continueAfterFailure = false
        let motion = accessibilitySettings("MOTION_TITLE")
        preferenceBaseline["REDUCE_MOTION"] = motion.switches["REDUCE_MOTION"].value as? String
        let display = accessibilitySettings("DISPLAY_AND_TEXT")
        for id in ["ENHANCE_TEXT_LEGIBILITY", "REDUCE_TRANSPARENCY", "DIFFERENTIATE_WITHOUT_COLOR"] {
            preferenceBaseline[id] = display.switches[id].value as? String
        }
        XCTAssertEqual(preferenceBaseline.count, 4)
        let a = XCTAttachment(string: "Accessibility baseline: \(preferenceBaseline)")
        a.name = "accessibility-preferences-baseline"; a.lifetime = .keepAlways; add(a)
        for id in ["ENHANCE_TEXT_LEGIBILITY", "REDUCE_TRANSPARENCY", "DIFFERENTIATE_WITHOUT_COLOR"] {
            setPreference(id, value: "1", settings: display)
        }
        let motionAgain = accessibilitySettings("MOTION_TITLE")
        setPreference("REDUCE_MOTION", value: "1", settings: motionAgain)
        motionAgain.terminate()
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "fixture", withExtension: "json"))
        let fixture = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: file))
        let app = try application("item/" + XCTUnwrap(fixture["movie"]))
        let play = app.buttons["Play"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 30))
        XCTAssertGreaterThanOrEqual(play.frame.height, 44)
        try app.performAccessibilityAudit(for: [.hitRegion, .sufficientElementDescription])
        capture("movie-reduced-motion-transparency-differentiate")
        app.terminate()
        restorePreferences()
    }

    override nonisolated func tearDown() async throws {
        await MainActor.run {
            self.restorePreferences()
            XCUIApplication(bundleIdentifier: "dev.ericslutz.gus").terminate()
            XCUIApplication(bundleIdentifier: "com.apple.Preferences").terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        try await super.tearDown()
    }

    func testAccessibilitySettingsInventory() {
        continueAfterFailure = false
        let settings = accessibilitySettings("MOTION_TITLE")
        print("Motion settings inventory: \(settings.debugDescription)")
        capture("motion-settings")
        settings.buttons["BackButton"].tap()
        print("Accessibility settings inventory: \(settings.debugDescription)")
        capture("accessibility-settings")
        settings.buttons["DISPLAY_AND_TEXT"].tap()
        print("Display settings inventory: \(settings.debugDescription)")
        capture("display-settings")
        settings.terminate()
    }

    private func application(_ route: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "dev.ericslutz.gus")
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--gus-demo-server", "--gus-route", route]
        app.launch()
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func rotate(_ app: XCUIApplication) {
        XCUIDevice.shared.orientation = .landscapeLeft
        let deadline = Date().addingTimeInterval(10)
        while app.windows.firstMatch.frame.width <= app.windows.firstMatch.frame.height, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertGreaterThan(app.windows.firstMatch.frame.width, app.windows.firstMatch.frame.height)
    }

    func testDownloadsManagementRotation() {
        let app = application("downloaded")
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        let manage = app.buttons["Manage Downloads"].firstMatch
        XCTAssertTrue(manage.waitForExistence(timeout: 30))
        manage.tap()
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 10))
        capture("downloads-management")
        rotate(app)
        XCTAssertTrue(app.navigationBars["Downloads"].exists)
        capture("downloads-management-landscape")
    }

    func testMoreSettingsNavigationRotation() {
        let app = application("home")
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.buttons["More"].firstMatch.waitForExistence(timeout: 30))
        app.buttons["More"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        let navigation = app.buttons["Navigation"]
        for _ in 0 ..< 6 {
            if navigation.isHittable {
                break
            }
            app.swipeUp()
        }
        XCTAssertTrue(navigation.isHittable)
        navigation.tap()
        XCTAssertTrue(app.navigationBars["Navigation"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.navigationBars.count, 1)
        capture("more-settings-navigation")
        rotate(app)
        XCTAssertTrue(app.navigationBars["Navigation"].exists)
        capture("more-settings-navigation-landscape")
    }

    func testConnectPendingCancellation() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "dev.ericslutz.gus")
        app.launchArguments = ["--gus-skip-session-restore"]
        app.launch()
        defer { app.terminate() }
        let field = app.textFields["ConnectServerView.serverAddress"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("http://127.0.0.1:8098")
        app.buttons["ConnectServerView.connectButton"].tap()
        let cancel = app.buttons["ConnectServerView.cancelButton"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        capture("connect-pending")
        cancel.tap()
        XCTAssertTrue(app.buttons["ConnectServerView.connectButton"].isEnabled)
        XCTAssertFalse(cancel.exists)
        capture("connect-cancelled")
    }

    func testConnectFailureRecovery() throws {
        continueAfterFailure = false
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "fixture", withExtension: "json"))
        let fixture = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: file))
        let app = XCUIApplication(bundleIdentifier: "dev.ericslutz.gus")
        app.launchArguments = ["--gus-skip-session-restore"]
        app.launch()
        let field = app.textFields["ConnectServerView.serverAddress"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        try field.typeText("http://127.0.0.1:" + XCTUnwrap(fixture["unreachablePort"]))
        app.buttons["ConnectServerView.connectButton"].tap()
        let error = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Couldn't reach that server.")).firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 120))
        XCTAssertTrue(app.buttons["ConnectServerView.connectButton"].isEnabled)
        XCTAssertFalse(app.buttons["ConnectServerView.cancelButton"].exists)
        capture("connect-error-recoverable")
    }

    func testPhotoOpeningRotationAndSlideshow() throws {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "fixture", withExtension: "json"))
        let fixture = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: file))
        let app = try application("item/" + XCTUnwrap(fixture["photo"]))
        XCTAssertTrue(try app.navigationBars[XCTUnwrap(fixture["photoTitle"])].waitForExistence(timeout: 30))
        let play = app.buttons["Play Slideshow"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 0"), object: app.progressIndicators)], timeout: 15) == .completed)
        capture("photo-opened")
        rotate(app)
        XCTAssertTrue(play.isHittable)
        capture("photo-landscape")
        play.tap()
        let pause = app.buttons["Pause Slideshow"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        pause.tap()
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        app.buttons["ContentLink.detailDone"].tap()
        XCTAssertFalse(app.buttons["ContentLink.detailDone"].exists)
        capture("photo-dismissed")
    }

    func testPausedVideoRotation() throws {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "fixture", withExtension: "json"))
        let fixture = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: file))
        let movie = try XCTUnwrap(fixture["movie"])
        let app = application("play/" + movie)
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.otherElements["Video"].firstMatch.waitForExistence(timeout: 30))
        app.windows.firstMatch.tap()
        let transport = app.buttons.matching(NSPredicate(format: "identifier == 'Play/Pause' OR label == 'Pause' OR label == 'Play'")).firstMatch
        XCTAssertTrue(transport.waitForExistence(timeout: 30))
        if transport.label == "Pause" {
            transport.tap()
        }
        XCTAssertEqual(transport.label, "Play")
        capture("video-paused")
        rotate(app)
        if !transport.exists {
            app.windows.firstMatch.tap()
        }
        XCTAssertTrue(transport.waitForExistence(timeout: 10))
        XCTAssertEqual(transport.label, "Play")
        capture("video-paused-landscape")
        if !app.buttons["Close Button"].exists {
            app.windows.firstMatch.tap()
        }
        let close = app.buttons["Close Button"]
        if !close.exists {
            print("Paused video native controls: \(app.debugDescription)")
        }
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
    }
}
