import XCTest
#if os(iOS)
    import UIKit
#endif

@MainActor
final class GusLaunchUITests: XCTestCase {
    func testConnectScreenRendersOnLaunch() {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(connectButton(in: app).waitForExistence(timeout: 5))
    }

    #if os(iOS)
        func testLocalServersClosesBackToConnect() {
            continueAfterFailure = false
            let app = makeApp()
            app.launch()
            let find = app.buttons["Find a local server"]
            for _ in 0 ..< 4 where !find.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(find.isHittable)
            find.tap()

            let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let permission = system.alerts.firstMatch
            let prompt = permission.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "local network")).firstMatch
            if prompt.waitForExistence(timeout: 2) {
                permission.buttons.matching(NSPredicate(format: "label IN %@", ["Don’t Allow", "Don't Allow"])).firstMatch.tap()
            }
            let sheet = app.navigationBars["Local Servers"]
            XCTAssertTrue(sheet.waitForExistence(timeout: 5))
            let close = sheet.buttons["Close"]
            XCTAssertTrue(close.isHittable)
            close.tap()
            XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
            XCTAssertTrue(find.isHittable)
        }

        func testAgeRangeOfferCanBeDeferredAcrossLaunches() async throws {
            continueAfterFailure = false
            let base = try await navigationFixture()
            let app = makeApp()
            app.launchEnvironment["GUS_DEMO_URL"] = base.absoluteString
            app.launchEnvironment["GUS_DEMO_USERNAME"] = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            app.launchArguments += ["--gus-demo-server", "--gus-test-age-offer", "--gus-disable-cloud-sync", "--gus-intelligence-test-unsupported", "--gus-route", "settings"]
            app.launch()
            defer { app.terminate() }

            let later = app.buttons["Not Now"]
            XCTAssertTrue(later.waitForExistence(timeout: 20))
            XCTAssertTrue(app.buttons["Check Age Range"].isHittable)
            later.tap()
            XCTAssertTrue(app.buttons["Settings.profile"].waitForExistence(timeout: 15))
            app.terminate()
            app.launch()
            XCTAssertTrue(app.buttons["Settings.profile"].waitForExistence(timeout: 15))
            XCTAssertFalse(later.exists)
        }

        func testProfileQuickConnectRejectsExpiredCodesAndAuthorizes() async throws {
            continueAfterFailure = false
            let app = try await openProfileFixture("profile-enabled")
            defer { app.terminate() }
            let authorizer = app.buttons["Profile.quickConnect"]
            for _ in 0 ..< 6 where !authorizer.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(authorizer.isHittable)
            authorizer.tap()
            let field = app.textFields["Six-digit code"]
            XCTAssertTrue(field.waitForExistence(timeout: 10))
            let authorize = app.buttons["Authorize Device"]
            field.tap()
            field.typeText("12345")
            XCTAssertFalse(authorize.isEnabled)
            field.typeText("6")
            authorize.tap()
            XCTAssertTrue(app.staticTexts["That code is invalid or has expired. Get a new code on the other device."].waitForExistence(timeout: 10))
            field.tap()
            field.typeText("012345")
            authorize.tap()
            XCTAssertTrue(app.staticTexts["Device authorized."].waitForExistence(timeout: 10))
            XCTAssertFalse(authorize.isEnabled)
        }

        func testProfilePhotoRemovalCanBeCanceledWithQuickConnectDisabled() async throws {
            continueAfterFailure = false
            let app = try await openProfileFixture("profile-disabled")
            defer { app.terminate() }
            let photo = app.buttons["Profile.picture"]
            XCTAssertTrue(photo.waitForExistence(timeout: 10))
            photo.tap()
            let remove = app.buttons["Remove Photo"].firstMatch
            XCTAssertTrue(remove.waitForExistence(timeout: 5))
            remove.tap()
            XCTAssertTrue(app.buttons["Profile.save"].isEnabled)
            for _ in 0 ..< 3 {
                app.swipeUp()
            }
            XCTAssertFalse(app.buttons["Profile.quickConnect"].exists)
            app.buttons["Cancel"].firstMatch.tap()
            app.buttons["Settings.profile"].firstMatch.tap()
            XCTAssertTrue(photo.waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["Profile.save"].isEnabled)
            photo.tap()
            XCTAssertTrue(remove.waitForExistence(timeout: 5))
        }

        func testClientLogsOpensRecordedEventFromFullList() async throws {
            continueAfterFailure = false
            let app = try await openProfileFixture("profile-disabled")
            defer { app.terminate() }
            app.buttons["Cancel"].firstMatch.tap()
            let logs = app.buttons["Client Logs"].firstMatch
            for _ in 0 ..< 12 where !logs.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(logs.isHittable)
            logs.tap()
            let all = app.buttons["ClientLogs.allEvents"]
            for _ in 0 ..< 6 where !all.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(all.isHittable)
            all.tap()
            let event = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ClientLogs.event.")).firstMatch
            XCTAssertTrue(event.waitForExistence(timeout: 5))
            event.tap()
            XCTAssertTrue(app.navigationBars["Event Details"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Recorded"].exists)
        }

        private func openProfileFixture(_ username: String) async throws -> XCUIApplication {
            let base = try await navigationFixture()
            let app = makeApp()
            app.launchEnvironment["GUS_DEMO_URL"] = base.absoluteString
            app.launchEnvironment["GUS_DEMO_USERNAME"] = username
            app.launchArguments += ["--gus-demo-server", "--gus-disable-cloud-sync", "--gus-intelligence-test-unsupported", "--gus-route", "settings"]
            app.launch()
            let open = app.buttons["Settings.profile"].firstMatch
            XCTAssertTrue(open.waitForExistence(timeout: 20))
            open.tap()
            XCTAssertTrue(app.textFields["Username"].waitForExistence(timeout: 10))
            return app
        }

        func testProfileCanCloseDuringLoadingAndAfterFailure() async throws {
            continueAfterFailure = false
            let base = try await navigationFixture()
            let userID = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            let app = makeApp()
            app.launchEnvironment["GUS_DEMO_URL"] = base.absoluteString
            app.launchEnvironment["GUS_DEMO_USERNAME"] = userID
            app.launchArguments += ["--gus-demo-server", "--gus-disable-cloud-sync", "--gus-intelligence-test-unsupported", "--gus-route", "settings"]
            app.launch()
            defer { app.terminate() }

            let open = app.buttons["Settings.profile"].firstMatch
            XCTAssertTrue(open.waitForExistence(timeout: 20))
            open.tap()
            let sheet = app.navigationBars["Profile"]
            let close = sheet.buttons["Close"]
            XCTAssertTrue(close.waitForExistence(timeout: 10))
            XCTAssertFalse(app.textFields["Username"].exists)
            close.tap()
            XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))

            open.tap()
            XCTAssertTrue(close.waitForExistence(timeout: 10))
            try await updateNavigationFixture(base, action: "fail-profile", id: userID)
            XCTAssertTrue(app.buttons["Try Again"].waitForExistence(timeout: 15))
            XCTAssertFalse(app.buttons["Profile.save"].exists)
            close.tap()
            XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
            XCTAssertTrue(open.isHittable)
        }

        func testUnavailableNextUpRowOffersRecoveryWithoutNavigating() async throws {
            continueAfterFailure = false
            let base = try await navigationFixture()
            let account = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            let app = makeApp()
            app.launchEnvironment["GUS_DEMO_URL"] = base.absoluteString
            app.launchEnvironment["GUS_DEMO_USERNAME"] = "queue-" + account
            let arguments = app.launchArguments + ["--gus-demo-server", "--gus-disable-cloud-sync", "--gus-intelligence-test-unsupported", "-nextUpDisplayGrid", "NO", "--gus-route"]
            app.launchArguments = arguments + ["item/" + account]
            app.launch()
            defer { app.terminate() }

            let add = app.buttons["Add to Next Up"].firstMatch
            XCTAssertTrue(add.waitForExistence(timeout: 20))
            add.tap()
            XCTAssertTrue(app.buttons["Remove from Next Up"].firstMatch.waitForExistence(timeout: 10))
            try await updateNavigationFixture(base, action: "remove-movie", id: account)
            app.terminate()
            app.launchArguments = arguments + ["home"]
            app.launch()

            let showAll = app.buttons["NextUp.showAll"]
            XCTAssertTrue(showAll.waitForExistence(timeout: 30))
            showAll.tap()
            let status = app.staticTexts["Unavailable on this server"].firstMatch
            XCTAssertTrue(status.waitForExistence(timeout: 20))
            let movie = NSPredicate(format: "label == %@", "Recoverable Movie")
            XCTAssertTrue(app.descendants(matching: .any).matching(movie).firstMatch.exists)
            XCTAssertFalse(app.buttons.matching(movie).firstMatch.exists)
            XCTAssertFalse(app.links.matching(movie).firstMatch.exists)
            let retry = app.buttons["Retry"].firstMatch
            XCTAssertTrue(retry.isHittable)
            retry.tap()
            app.buttons["Choose Replacement"].firstMatch.tap()
            let replacement = app.navigationBars["Choose Replacement"]
            XCTAssertTrue(replacement.waitForExistence(timeout: 5))
            replacement.buttons["Cancel"].tap()
            XCTAssertTrue(status.waitForExistence(timeout: 5))
            app.buttons["Remove"].firstMatch.tap()
            XCTAssertTrue(status.waitForNonExistence(timeout: 10))
        }

        private func updateNavigationFixture(_ base: URL, action: String, id: String) async throws {
            var request = URLRequest(url: base.appending(path: "fixture/" + action + "/" + id))
            request.httpMethod = "POST"
            let (_, response) = try await URLSession.shared.data(for: request)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 204)
        }

        func testVideoCanCloseDuringPreparationAndAfterFailure() async throws {
            continueAfterFailure = false
            let base = try await navigationFixture()
            let movieID = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            let app = makeApp()
            app.launchEnvironment["GUS_DEMO_URL"] = base.absoluteString
            app.launchEnvironment["GUS_DEMO_USERNAME"] = "queue-" + movieID
            app.launchArguments += ["--gus-demo-server", "--gus-disable-cloud-sync", "--gus-intelligence-test-unsupported", "--gus-route", "item/" + movieID]
            app.launch()
            defer { app.terminate() }

            let play = app.buttons["Detail.play"].firstMatch
            let close = app.buttons["VideoPlayer.close"]
            let failure = app.staticTexts["Can't Play This"].firstMatch
            XCTAssertTrue(play.waitForExistence(timeout: 20))
            try await updateNavigationFixture(base, action: "hold-playback", id: movieID)
            play.tap()
            XCTAssertTrue(close.waitForExistence(timeout: 10))
            XCTAssertTrue(app.activityIndicators.firstMatch.exists)
            XCTAssertFalse(failure.exists)
            close.tap()
            XCTAssertTrue(close.waitForNonExistence(timeout: 5))
            XCTAssertTrue(play.isHittable)

            try await updateNavigationFixture(base, action: "fail-playback", id: movieID)
            play.tap()
            XCTAssertTrue(failure.waitForExistence(timeout: 15))
            XCTAssertTrue(app.buttons["Try Again"].isHittable)
            XCTAssertTrue(close.isHittable)
            close.tap()
            XCTAssertTrue(close.waitForNonExistence(timeout: 5))
            XCTAssertFalse(failure.exists)
            XCTAssertTrue(play.isHittable)
        }

        func testSeasonMenuLoadsSelectedSeasonEpisodes() async throws {
            continueAfterFailure = false
            let base = try await navigationFixture()
            let app = makeApp()
            app.launchEnvironment["GUS_DEMO_URL"] = base.absoluteString
            app.launchArguments += ["--gus-demo-server", "--gus-disable-cloud-sync", "--gus-intelligence-test-unsupported", "--gus-route", "item/49000000000000000000000000000000"]
            app.launch()
            defer { app.terminate() }

            XCTAssertTrue(app.staticTexts["Navigation Series"].firstMatch.waitForExistence(timeout: 20))
            selectSeason("Second Season", replacing: "First Season", in: app)
            let episode = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Episode of Second Season")).firstMatch
            XCTAssertTrue(episode.waitForExistence(timeout: 10))
            selectSeason("First Season", replacing: "Second Season", in: app)
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Episode of First Season")).firstMatch.waitForExistence(timeout: 10))
        }

        func testSearchSeasonAndEpisodeSurviveRotation() async throws {
            guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("Uses iPhone tab navigation") }
            continueAfterFailure = false
            XCUIDevice.shared.orientation = .portrait
            let app = try await launchNavigationFixture(route: "search")
            defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }

            let query = "Navigation Series"
            let field = app.searchFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 20))
            field.tap()
            field.typeText(query + "\n")
            let series = app.buttons["Search.result.49000000000000000000000000000000"]
            XCTAssertTrue(series.waitForExistence(timeout: 12))
            series.tap()
            selectSeason("Second Season", replacing: "First Season", in: app)
            let episode = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Episode of Second Season")).firstMatch
            XCTAssertTrue(episode.waitForExistence(timeout: 10))
            for _ in 0 ..< 3 where !episode.isHittable {
                app.swipeUp(velocity: .slow)
            }
            episode.tap()
            let overview = app.staticTexts["Detail.heroOverview"].firstMatch
            XCTAssertTrue(overview.waitForExistence(timeout: 10))
            for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
                rotate(app, to: orientation)
                XCTAssertTrue(overview.waitForExistence(timeout: 5))
                XCTAssertEqual(overview.label, "Navigation episode details for Second Season.")
            }

            app.navigationBars.buttons["BackButton"].firstMatch.tap()
            XCTAssertTrue(episode.waitForExistence(timeout: 10))
            XCTAssertEqual(app.buttons["Series.seasonPicker"].firstMatch.value as? String, "Second Season")
            app.navigationBars.buttons["BackButton"].firstMatch.tap()
            XCTAssertTrue(series.waitForExistence(timeout: 10))
            XCTAssertTrue((field.exists && field.value as? String == query) || app.navigationBars[query].exists)
            app.buttons["Search.clearResults"].tap()
            let recent = app.buttons["Search.recent.typed:navigation series"].firstMatch
            XCTAssertTrue(recent.waitForExistence(timeout: 5))
        }

        func testDownloadsKeepsFilterAndSearchAcrossRotation() async throws {
            guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("Uses iPhone toolbar placement") }
            continueAfterFailure = false
            XCUIDevice.shared.orientation = .portrait
            let app = try await launchNavigationFixture(route: "downloaded")
            defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }

            let field = app.searchFields["Downloads.search"].firstMatch
            let filters = app.segmentedControls
            XCTAssertTrue(filters.buttons["All"].waitForExistence(timeout: 20))
            for title in ["Movies", "All", "Movies"] {
                let option = filters.buttons[title].firstMatch
                option.tap()
                XCTAssertTrue(option.isSelected)
                XCTAssertTrue(field.waitForExistence(timeout: 5))
                XCTAssertTrue(field.isHittable, "The native Downloads search field must be reachable above the tab bar")
                XCTAssertEqual(field.placeholderValue, "Search Downloads")
                XCTAssertGreaterThan(field.frame.midY, app.frame.midY)
                XCTAssertLessThanOrEqual(field.frame.maxY, app.tabBars.firstMatch.frame.minY)
            }
            field.tap()
            field.typeText("Recent")
            if app.keyboards.firstMatch.exists {
                XCTAssertLessThanOrEqual(field.frame.maxY, app.keyboards.firstMatch.frame.minY)
            }
            for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
                rotate(app, to: orientation)
                XCTAssertTrue(filters.buttons["Movies"].firstMatch.isSelected)
                XCTAssertTrue(field.waitForExistence(timeout: 5))
                XCTAssertEqual(field.value as? String, "Recent")
            }
        }

        private func launchNavigationFixture(route: String) async throws -> XCUIApplication {
            let base = try await navigationFixture()
            let app = makeApp()
            app.launchEnvironment["GUS_DEMO_URL"] = base.absoluteString
            app.launchArguments += ["--gus-demo-server", "--gus-disable-cloud-sync", "--gus-intelligence-test-unsupported", "--gus-route", route]
            app.launch()
            return app
        }

        private func selectSeason(_ name: String, replacing previous: String, in app: XCUIApplication) {
            let picker = app.buttons["Series.seasonPicker"].firstMatch
            for _ in 0 ..< 8 where !picker.isHittable {
                app.swipeUp(velocity: .slow)
            }
            XCTAssertTrue(picker.isHittable)
            XCTAssertEqual(picker.value as? String, previous)
            picker.tap()
            let option = app.buttons[name].firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 5))
            option.tap()
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", name), object: picker)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        }

        private func rotate(_ app: XCUIApplication, to orientation: UIDeviceOrientation) {
            XCUIDevice.shared.orientation = orientation
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let frame = app.frame
                return !frame.isEmpty && (orientation.isLandscape ? frame.width > frame.height : frame.height > frame.width)
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 10), .completed)
        }

        private func navigationFixture() async throws -> URL {
            let base = try XCTUnwrap(URL(string: "http://127.0.0.1:5062"))
            let data: Data
            do {
                (data, _) = try await URLSession.shared.data(from: base.appending(path: "health"))
            } catch let error as URLError where error.code == .cannotConnectToHost {
                throw XCTSkip("Run Scripts/book-details-fixture.py --navigation for the profile and season fixtures.")
            }
            let health = try JSONDecoder().decode([String: String].self, from: data)
            XCTAssertEqual(health["fixture"], "gus-navigation", "Run Scripts/book-details-fixture.py --navigation")
            return base
        }

        func testConnectScreenRendersAtLargestAccessibilityContentSize() {
            let app = makeApp()
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
            ]
            app.launch()

            let headline = app.staticTexts["Connect to Jellyfin"].firstMatch
            XCTAssertTrue(headline.waitForExistence(timeout: 10))
            XCTAssertGreaterThanOrEqual(headline.frame.height, 40)
            capture("connect-verified-ax5-top")
            revealConnect(in: app)
            capture("connect-verified-ax5-action")
        }

        func testConnectScreenRendersWithPseudolocalizationAtLargestAccessibilityContentSize() {
            let app = makeApp()
            app.launchArguments += [
                "-NSDoubleLocalizedStrings",
                "YES",
                "-UIPreferredContentSizeCategoryName",
                UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
            ]
            app.launch()

            revealConnect(in: app)
            XCTAssertGreaterThan(connectButton(in: app).label.count, "Connect".count)
            capture("connect-native-double-length-ax5")
        }
    #endif

    #if os(iOS)
        private func revealConnect(in app: XCUIApplication) {
            let button = connectButton(in: app)
            for _ in 0 ..< 8 {
                if button.exists, button.isHittable {
                    break
                }
                app.swipeUp()
            }
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            XCTAssertTrue(button.isHittable)
        }

    #endif

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--gus-skip-session-restore"]
        return app
    }

    private func connectButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons["ConnectServerView.connectButton"]
    }
}
