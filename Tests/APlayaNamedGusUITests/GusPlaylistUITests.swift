#if os(iOS)
    import XCTest

    /// Editing and sequencing acceptance use the task-owned local demo server.
    /// These cases establish server-backed CRUD, not physical/iCloud acceptance.
    @MainActor
    final class GusPlaylistUITests: XCTestCase {
        func testPlaylistCreateRenamePersistAndDelete() async throws {
            continueAfterFailure = false
            let app = XCUIApplication()
            app.launchArguments = ["--gus-skip-session-restore", "--gus-demo-server", "--gus-disable-cloud-sync"]
            let name = "Acceptance " + UUID().uuidString.prefix(8)
            let renamed = name + " Renamed"
            app.launch()
            openPlaylists(app)
            app.buttons["New List"].tap(); app.buttons["New Playlist"].tap()
            let field = app.textFields["Name"].firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap(); field.typeText(name)
            app.buttons["Create"].tap()
            XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 10))
            let created = try await nativeList(named: name, kind: "Playlist")
            XCTAssertNotNil(created)
            app.staticTexts[name].tap()
            XCTAssertTrue(app.buttons["Add Media"].waitForExistence(timeout: 5))
            app.buttons["Rename"].tap()
            let renameField = app.textFields["Name"].firstMatch
            renameField.tap()
            // Native select-all replacement is more reliable than a string of
            // backspaces across hardware/software keyboard configurations.
            renameField.press(forDuration: 1)
            if app.buttons["Select All"].exists {
                app.buttons["Select All"].tap()
            } else {
                renameField.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
                renameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: name.count))
            }
            renameField.typeText(renamed)
            XCTAssertEqual(renameField.value as? String, renamed)
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "playlist-rename-input"; screenshot.lifetime = .keepAlways; add(screenshot)
            app.buttons["Save"].tap()
            app.terminate(); app.launch()
            openPlaylists(app)
            let row = app.staticTexts[renamed]
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            let persisted = try await nativeList(named: renamed, kind: "Playlist")
            XCTAssertNotNil(persisted)
            row.press(forDuration: 1)
            app.buttons["Delete"].firstMatch.tap()
            let confirmation = app.buttons["Delete"].firstMatch
            XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
            confirmation.tap()
            XCTAssertFalse(app.staticTexts[renamed].waitForExistence(timeout: 2))
            let deleted = try await nativeList(named: renamed, kind: "Playlist")
            XCTAssertNil(deleted)
            app.terminate()
        }

        func testDemoPlaylistEntriesPlayInOrderToCompletion() async throws {
            continueAfterFailure = false
            executionTimeAllowance = 300
            let app = XCUIApplication()
            app.launchArguments = ["--gus-skip-session-restore", "--gus-demo-server", "--gus-disable-cloud-sync"]
            app.launch()
            openPlaylists(app)
            let name = "Ordered Acceptance " + UUID().uuidString.prefix(8)
            app.buttons["New List"].tap(); app.buttons["New Playlist"].tap()
            let field = app.textFields["Name"].firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap(); field.typeText(name)
            app.buttons["Create"].tap()
            let row = app.staticTexts[name]
            XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
            for (query, title) in [("Sneeze", "Edison Kinetoscopic Record of a Sneeze (1894)"), ("May Irwin", "May Irwin Kiss (1896)")] {
                app.buttons["Add Media"].tap()
                let search = app.searchFields.firstMatch
                XCTAssertTrue(search.waitForExistence(timeout: 10))
                search.tap(); search.typeText(query)
                let result = app.buttons[title].firstMatch
                XCTAssertTrue(result.waitForExistence(timeout: 20)); result.tap()
                XCTAssertTrue(app.buttons["Play from Beginning"].waitForExistence(timeout: 10))
            }
            XCTAssertEqual(app.staticTexts.matching(identifier: "Edison Kinetoscopic Record of a Sneeze (1894)").count, 1)
            let before = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            before.name = "ordered-native-playlist"; before.lifetime = .keepAlways; add(before)
            let native = try await nativeList(named: name, kind: "Playlist")
            let nativeID = try XCTUnwrap(native?["Id"] as? String)
            let entries = try await nativeEntries(listID: nativeID, playlist: true)
            XCTAssertEqual(entries.compactMap { $0["Name"] as? String }, ["Edison Kinetoscopic Record of a Sneeze (1894)", "May Irwin Kiss (1896)"])
            app.buttons["Play from Beginning"].tap()
            let done = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.staticTexts["Playlist Finished"].isHittable }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 180), .completed)
            let after = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            after.name = "ordered-playlist-natural-completion"; after.lifetime = .keepAlways; add(after)
            app.navigationBars.buttons.firstMatch.tap()
            row.press(forDuration: 1)
            app.buttons["Delete"].firstMatch.tap()
            app.buttons["Delete"].firstMatch.tap()
            app.terminate()
        }

        func testNativeCollectionCreateAddRemoveAndDelete() async throws {
            continueAfterFailure = false
            let app = XCUIApplication()
            app.launchArguments = ["--gus-skip-session-restore", "--gus-demo-server", "--gus-disable-cloud-sync"]
            let name = "Collection Acceptance " + UUID().uuidString.prefix(8)
            app.launch(); openPlaylists(app)
            app.buttons["New List"].tap(); app.buttons["New Collection"].tap()
            let field = app.textFields["Name"].firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap(); field.typeText(name); app.buttons["Create"].tap()
            let row = app.staticTexts[name]
            XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
            XCTAssertTrue(app.buttons["Add Media"].waitForExistence(timeout: 10))
            app.buttons["Add Media"].tap()
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 10))
            search.tap(); search.typeText("Sneeze")
            let title = "Edison Kinetoscopic Record of a Sneeze (1894)"
            let result = app.buttons[title].firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 20)); result.tap()
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10))
            let collection = try await nativeList(named: name, kind: "BoxSet")
            let id = try XCTUnwrap(collection?["Id"] as? String)
            let before = try await nativeEntries(listID: id, playlist: false)
            XCTAssertEqual(before.count, 1)
            let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            capture.name = "native-collection-membership"; capture.lifetime = .keepAlways; add(capture)
            app.staticTexts[title].press(forDuration: 1)
            app.buttons["Remove"].firstMatch.tap()
            XCTAssertTrue(app.staticTexts["Add titles to this collection."].waitForExistence(timeout: 10))
            let after = try await nativeEntries(listID: id, playlist: false)
            XCTAssertTrue(after.isEmpty)
            app.navigationBars.buttons.firstMatch.tap()
            row.press(forDuration: 1); app.buttons["Delete"].firstMatch.tap(); app.buttons["Delete"].firstMatch.tap()
            XCTAssertFalse(row.waitForExistence(timeout: 2))
            let deleted = try await nativeList(named: name, kind: "BoxSet")
            XCTAssertNil(deleted)
            app.terminate()
        }

        /// Read back the task-owned demo server independently of Gus's cache.
        private func demoRequest(_ path: String, token: String? = nil, body: [String: String]? = nil) async throws -> [String: Any] {
            var request = try URLRequest(url: XCTUnwrap(URL(string: "http://localhost:8096" + path)))
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("MediaBrowser Client=\"Gus UI Acceptance\", Device=\"Simulator\", DeviceId=\"gus-native-lists-test\", Version=\"1.0.0\"", forHTTPHeaderField: "X-Emby-Authorization")
            request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
            if let body {
                request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: body)
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }

        private func nativeList(named name: String, kind: String) async throws -> [String: Any]? {
            let auth = try await demoRequest("/Users/AuthenticateByName", body: ["Username": "gus", "Pw": "playa-demo"])
            let token = try XCTUnwrap(auth["AccessToken"] as? String)
            let result = try await demoRequest("/Items?recursive=true&includeItemTypes=" + kind, token: token)
            let items = try XCTUnwrap(result["Items"] as? [[String: Any]])
            return items.first { $0["Name"] as? String == name }
        }

        private func nativeEntries(listID: String, playlist: Bool) async throws -> [[String: Any]] {
            let auth = try await demoRequest("/Users/AuthenticateByName", body: ["Username": "gus", "Pw": "playa-demo"])
            let token = try XCTUnwrap(auth["AccessToken"] as? String)
            let user = try XCTUnwrap(auth["User"] as? [String: Any])
            let userID = try XCTUnwrap(user["Id"] as? String)
            let path = playlist ? "/Playlists/" + listID + "/Items?userId=" + userID : "/Items?parentId=" + listID + "&userId=" + userID
            let result = try await demoRequest(path, token: token)
            return try XCTUnwrap(result["Items"] as? [[String: Any]])
        }

        private func openPlaylists(_ app: XCUIApplication) {
            let tab = app.tabBars.buttons["Playlists"]
            XCTAssertTrue(tab.waitForExistence(timeout: 20))
            tab.tap()
            XCTAssertTrue(app.buttons["New List"].waitForExistence(timeout: 10))
        }
    }
#endif
