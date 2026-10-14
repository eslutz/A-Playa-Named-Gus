#if os(macOS)
    import XCTest

    @MainActor final class GusMacPlaybackActionUITests: XCTestCase {
        func testRepeatedRestartReusesThePlayerWindow() async throws {
            continueAfterFailure = false
            executionTimeAllowance = 180
            let auth = try await request("/Users/AuthenticateByName", body: ["Username": "gus", "Pw": "playa-demo"])
            let token = try XCTUnwrap(auth["AccessToken"] as? String)
            let result = try await request("/Items?recursive=true&includeItemTypes=Movie", token: token)
            let movies = try XCTUnwrap(result["Items"] as? [[String: Any]])
            let movie = try XCTUnwrap(movies.first { ($0["Name"] as? String)?.contains("Sneeze") == true })
            let id = try XCTUnwrap(movie["Id"] as? String)
            let app = XCUIApplication()
            app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "--gus-skip-session-restore", "--gus-demo-server", "--gus-disable-cloud-sync", "--gus-route", "item/" + id]
            app.launch()
            defer { app.terminate() }
            XCTAssertTrue(app.buttons["Detail.play"].waitForExistence(timeout: 30))
            let baseline = app.windows.count
            app.buttons["Detail.play"].click()
            let opened = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.windows.count == baseline + 1 }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [opened], timeout: 15), .completed)
            for _ in 0 ..< 2 {
                app.buttons["Detail.restart"].click()
                XCTAssertEqual(app.windows.count, baseline + 1)
            }
        }

        private func request(_ path: String, token: String? = nil, body: [String: Any]? = nil) async throws -> [String: Any] {
            var request = try URLRequest(url: XCTUnwrap(URL(string: "http://localhost:8096" + path)))
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("MediaBrowser Client=\"Gus UI Acceptance\", Device=\"Mac\", DeviceId=\"gus-mac-actions\", Version=\"1.0.0\"", forHTTPHeaderField: "X-Emby-Authorization")
            request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
            if let body {
                request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: body)
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
    }
#endif
