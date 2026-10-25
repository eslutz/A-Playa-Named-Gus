#if os(iOS)
    import Foundation
    import XCTest

    /// Requires the localhost Jellyfin demo and Scripts/discover-fixture-server.py.
    /// All credentials, titles and mutations belong to synthetic loopback fixtures.
    @MainActor
    final class GusSeerrUITests: XCTestCase {
        func testConnectPersistRequestHistoryAndCancel() async throws {
            let app = try await prepare()
            defer { app.terminate() }
            connect(app)
            openDiscover(app)
            capture("seerr-connected-catalog")
            openMovieReview(app)
            submit(app)
            assertPendingConfirmation(app)
            capture("seerr-movie-pending")
            app.buttons["Done"].firstMatch.tap()

            // A new app process must restore the cookie without another login.
            app.terminate()
            app.launch()
            openIntegration(app)
            XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 20))
            var state = try await fixtureState()
            XCTAssertEqual(state.events.filter { $0.method == "POST" && $0.path == "/api/v1/auth/local" }.count, 1)
            XCTAssertEqual(requestPosts(state), 1)
            XCTAssertEqual(state.requests.count, 1)

            openDiscover(app)
            openHistory(app)
            openRequestRow(app)
            XCTAssertTrue(app.staticTexts["Media Availability"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Gus Fixture Manager"].exists)
            let cancel = app.buttons["Cancel My Request"].firstMatch
            reveal(cancel, in: app)
            cancel.tap()
            confirm("Cancel My Request", in: app)
            XCTAssertTrue(app.staticTexts["Request Removed"].waitForExistence(timeout: 15))
            capture("seerr-own-request-removed")
            state = try await fixtureState()
            XCTAssertTrue(state.requests.isEmpty)
            XCTAssertEqual(state.events.filter { $0.method == "DELETE" && $0.path == "/api/v1/request/1" }.count, 1)
            XCTAssertEqual(requestPosts(state), 1)
        }

        func testLostSubmissionResponseReadsBackWithoutDuplicatePost() async throws {
            let app = try await prepare(uncertainNext: true)
            defer { app.terminate() }
            connect(app)
            openDiscover(app)
            openMovieReview(app)
            submit(app)
            XCTAssertTrue(app.staticTexts["Check Request Before Retrying"].waitForExistence(timeout: 20))
            XCTAssertFalse(app.buttons["Seerr.submitRequest"].exists)
            var state = try await fixtureState()
            XCTAssertEqual(state.requests.count, 1, "The fixture committed before returning HTTP 500")
            XCTAssertEqual(requestPosts(state), 1)
            capture("seerr-uncertain-submission")

            let check = app.buttons["Check Request"].firstMatch
            reveal(check, in: app)
            check.tap()
            assertPendingConfirmation(app)
            capture("seerr-uncertain-readback-confirmed")
            state = try await fixtureState()
            XCTAssertEqual(state.requests.count, 1)
            XCTAssertEqual(state.requests.first?.status, 1)
            XCTAssertEqual(requestPosts(state), 1, "Readback must not repeat the create request")
        }

        func testManagerReviewsPendingRequestBeforeApproval() async throws {
            let app = try await prepare()
            defer { app.terminate() }
            connect(app)
            openDiscover(app)
            openMovieReview(app)
            submit(app)
            assertPendingConfirmation(app)
            app.buttons["Done"].firstMatch.tap()
            backToDiscover(app)
            let menu = app.buttons["Seerr.menu"].firstMatch
            XCTAssertTrue(menu.waitForExistence(timeout: 10))
            menu.tap()
            let manage = app.buttons["Manage Requests"].firstMatch
            XCTAssertTrue(manage.waitForExistence(timeout: 5))
            manage.tap()
            XCTAssertTrue(app.navigationBars["Manage Requests"].waitForExistence(timeout: 10))
            openRequestRow(app)
            let approve = app.buttons["Approve Request"].firstMatch
            reveal(approve, in: app)
            XCTAssertTrue(app.staticTexts["Pending Approval"].exists)
            capture("seerr-manager-request-review")
            approve.tap()
            confirm("Approve Request", in: app)
            XCTAssertTrue(app.staticTexts["Seerr confirmed this request is approved."].waitForExistence(timeout: 15))
            capture("seerr-manager-approved-readback")
            let state = try await fixtureState()
            XCTAssertEqual(state.requests.first?.status, 2)
            XCTAssertEqual(state.events.filter { $0.method == "POST" && $0.path == "/api/v1/request/1/approve" }.count, 1)
            XCTAssertEqual(requestPosts(state), 1)
        }

        private func prepare(uncertainNext: Bool = false) async throws -> XCUIApplication {
            continueAfterFailure = false
            executionTimeAllowance = 240
            let app = XCUIApplication()
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
            let health = try JSONDecoder().decode(FixtureHealth.self, from: await fixtureData("/__fixture/health"))
            XCTAssertEqual(health.fixture, "gus-discover")
            let reset = try JSONEncoder().encode(FixtureReset(uncertainNext: uncertainNext))
            _ = try await fixtureData("/__fixture/reset", method: "POST", body: reset)
            app.launchArguments = [
                "--gus-skip-session-restore", "--gus-demo-server", "--gus-disable-cloud-sync", "--gus-route", "settings",
                "-dev.ericslutz.gus.contentRatingLimit", "off",
                "-dev.ericslutz.gus.contentRatingHideUnrated", "NO",
            ]
            app.launch()
            openIntegration(app)
            return app
        }

        private func openIntegration(_ app: XCUIApplication) {
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 30))
            let integration = app.buttons["Seerr"].firstMatch
            reveal(integration, in: app)
            integration.tap()
            XCTAssertTrue(app.navigationBars["Discover Settings"].waitForExistence(timeout: 10))
        }

        private func connect(_ app: XCUIApplication) {
            // Keychain entries outlive app processes and test cases. Reset the
            // connection through its public UI rather than relying on install state.
            let disconnect = app.buttons["Disconnect This Device"].firstMatch
            if disconnect.waitForExistence(timeout: 2) {
                reveal(disconnect, in: app)
                disconnect.tap()
                confirm("Disconnect", in: app)
            }
            let visibility = app.switches["Show Discover"].firstMatch
            if visibility.exists, visibility.value as? String == "0" {
                reveal(visibility, in: app)
                visibility.tap()
            }
            let connect = app.buttons["Connect to Seerr"].firstMatch
            reveal(connect, in: app)
            connect.tap()
            let address = app.textFields["Seerr.serverURL"]
            XCTAssertTrue(address.waitForExistence(timeout: 10))
            address.tap()
            address.typeText("http://127.0.0.1:5056")
            let next = app.buttons["Seerr.continue"].firstMatch
            reveal(next, in: app)
            next.tap()
            let username = app.textFields["Seerr.username"]
            XCTAssertTrue(username.waitForExistence(timeout: 15))
            username.tap()
            username.typeText("fixture@example.invalid")
            let password = app.secureTextFields["Seerr.password"]
            XCTAssertTrue(password.exists)
            password.tap()
            password.typeText("gus-fixture-only")
            let signIn = app.buttons["Seerr.signIn"].firstMatch
            reveal(signIn, in: app)
            signIn.tap()
            XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 20))
        }

        private func openDiscover(_ app: XCUIApplication) {
            let tab = app.tabBars.buttons["Discover"]
            if tab.exists {
                tab.tap()
            } else {
                if app.navigationBars["Discover Settings"].exists {
                    let back = app.navigationBars.buttons["Settings"].firstMatch
                    XCTAssertTrue(back.waitForExistence(timeout: 5))
                    back.tap()
                }
                let backToMore = app.navigationBars.buttons["More"].firstMatch
                if backToMore.waitForExistence(timeout: 2) {
                    backToMore.tap()
                } else {
                    let more = app.tabBars.buttons["More"]
                    if more.exists {
                        more.tap()
                    }
                }
                let discover = app.buttons["Discover"].firstMatch
                reveal(discover, in: app)
                discover.tap()
            }
            XCTAssertTrue(app.navigationBars["Discover"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["View Title"].firstMatch.waitForExistence(timeout: 20))
        }

        private func openMovieReview(_ app: XCUIApplication) {
            let title = app.buttons["View Title"].firstMatch
            reveal(title, in: app)
            title.tap()
            XCTAssertTrue(app.navigationBars["Gus Fixture Movie"].waitForExistence(timeout: 15))
            let request = app.buttons["Request"].firstMatch
            reveal(request, in: app)
            request.tap()
            XCTAssertTrue(app.navigationBars["Review Request"].waitForExistence(timeout: 10))
        }

        private func submit(_ app: XCUIApplication) {
            let submit = app.buttons["Seerr.submitRequest"].firstMatch
            XCTAssertTrue(submit.waitForExistence(timeout: 20))
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: submit)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
            reveal(submit, in: app)
            submit.tap()
        }

        private func assertPendingConfirmation(_ app: XCUIApplication) {
            XCTAssertTrue(app.staticTexts["Request Confirmed"].waitForExistence(timeout: 20))
            XCTAssertTrue(app.staticTexts["Pending Approval"].exists)
        }

        private func backToDiscover(_ app: XCUIApplication) {
            let back = app.navigationBars.buttons["Discover"].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 10))
            back.tap()
            XCTAssertTrue(app.navigationBars["Discover"].waitForExistence(timeout: 10))
        }

        private func openHistory(_ app: XCUIApplication) {
            let history = app.buttons["My Requests"].firstMatch
            XCTAssertTrue(history.waitForExistence(timeout: 10))
            history.tap()
            XCTAssertTrue(app.navigationBars["My Requests"].waitForExistence(timeout: 10))
        }

        private func openRequestRow(_ app: XCUIApplication) {
            let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Gus Fixture Movie")).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 20))
            reveal(row, in: app)
            row.tap()
            XCTAssertTrue(app.navigationBars["Gus Fixture Movie"].waitForExistence(timeout: 15))
        }

        private func confirm(_ title: String, in app: XCUIApplication) {
            let sheet = app.sheets.buttons[title].firstMatch
            if sheet.waitForExistence(timeout: 3) {
                sheet.tap()
            } else if app.alerts.buttons[title].firstMatch.exists {
                app.alerts.buttons[title].firstMatch.tap()
            } else {
                let matches = app.buttons.matching(identifier: title).allElementsBoundByIndex.filter(\.isHittable)
                guard let button = matches.last else { XCTFail("Missing native confirmation action: " + title); return }
                button.tap()
            }
        }

        private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
            _ = element.waitForExistence(timeout: 2)
            for _ in 0 ..< 10 {
                if element.exists, element.isHittable {
                    break
                }
                app.swipeUp()
            }
            XCTAssertTrue(element.exists)
            XCTAssertTrue(element.isHittable)
        }

        private func capture(_ name: String) {
            let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            image.name = name; image.lifetime = .keepAlways; add(image)
        }

        private func requestPosts(_ state: FixtureState) -> Int {
            state.events.filter { $0.method == "POST" && $0.path == "/api/v1/request" }.count
        }

        private func fixtureState() async throws -> FixtureState {
            try JSONDecoder().decode(FixtureState.self, from: await fixtureData("/__fixture/state"))
        }

        private func fixtureData(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
            let url = try XCTUnwrap(URL(string: "http://127.0.0.1:5056" + path))
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.httpBody = body
            request.timeoutInterval = 10
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let session = URLSession(configuration: .ephemeral)
            defer { session.invalidateAndCancel() }
            let (data, response) = try await session.data(for: request)
            let http = try XCTUnwrap(response as? HTTPURLResponse)
            XCTAssertEqual(http.statusCode, 200, "The loopback Seerr fixture must be running")
            return data
        }
    }

    private struct FixtureHealth: Decodable { let fixture: String }
    private struct FixtureReset: Encodable { let uncertainNext: Bool }
    private struct FixtureState: Decodable {
        let requests: [FixtureRequest]
        let events: [FixtureEvent]
    }

    private struct FixtureRequest: Decodable { let id: Int; let status: Int }
    private struct FixtureEvent: Decodable { let method: String; let path: String }
#endif
