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

            let open = app.buttons["View and Edit Profile"].firstMatch
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

            let first = app.buttons["First Season"].firstMatch
            XCTAssertTrue(app.staticTexts["Navigation Series"].firstMatch.waitForExistence(timeout: 20))
            for _ in 0 ..< 8 where !first.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(first.isHittable)
            first.tap()
            let second = app.buttons["Second Season"].firstMatch
            XCTAssertTrue(second.waitForExistence(timeout: 5))
            second.tap()
            let episode = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Episode of Second Season")).firstMatch
            XCTAssertTrue(episode.waitForExistence(timeout: 10))
            XCTAssertTrue(second.isHittable)
            second.tap()
            first.tap()
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Episode of First Season")).firstMatch.waitForExistence(timeout: 10))
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
