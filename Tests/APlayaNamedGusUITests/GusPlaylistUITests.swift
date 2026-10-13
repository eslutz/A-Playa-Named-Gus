#if os(iOS)
    import XCTest

    /// Local-first editing acceptance uses an isolated preview account without
    /// provider access or iCloud. This does not establish live sync/playback.
    @MainActor
    final class GusPlaylistUITests: XCTestCase {
        func testPlaylistCreateRenamePersistAndDelete() {
            continueAfterFailure = false
            let app = XCUIApplication()
            app.launchArguments = ["--gus-skip-session-restore", "--gus-debug-preview-session", "--gus-disable-cloud-sync"]
            let name = "Acceptance " + UUID().uuidString.prefix(8)
            let renamed = name + " Renamed"
            app.launch()
            openPlaylists(app)
            app.buttons["New Playlist"].tap()
            let field = app.textFields["Name"].firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap(); field.typeText(name)
            app.buttons["Create"].tap()
            XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 10))
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
            row.press(forDuration: 1)
            app.buttons["Delete Playlist"].firstMatch.tap()
            let confirmation = app.buttons["Delete Playlist"].firstMatch
            XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
            confirmation.tap()
            XCTAssertFalse(app.staticTexts[renamed].waitForExistence(timeout: 2))
            app.terminate()
        }

        func testDemoPlaylistDuplicateEntriesPlayInOrderToCompletion() {
            continueAfterFailure = false
            executionTimeAllowance = 300
            let app = XCUIApplication()
            app.launchArguments = ["--gus-skip-session-restore", "--gus-demo-server", "--gus-disable-cloud-sync"]
            app.launch()
            openPlaylists(app)
            let name = "Ordered Acceptance " + UUID().uuidString.prefix(8)
            app.buttons["New Playlist"].tap()
            let field = app.textFields["Name"].firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap(); field.typeText(name)
            app.buttons["Create"].tap()
            let row = app.staticTexts[name]
            XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
            for (query, title) in [("Sneeze", "Edison Kinetoscopic Record of a Sneeze (1894)"), ("Sneeze", "Edison Kinetoscopic Record of a Sneeze (1894)"), ("May Irwin", "May Irwin Kiss (1896)")] {
                app.buttons["Add Media"].tap()
                let search = app.searchFields.firstMatch
                XCTAssertTrue(search.waitForExistence(timeout: 10))
                search.tap(); search.typeText(query)
                let result = app.buttons[title].firstMatch
                XCTAssertTrue(result.waitForExistence(timeout: 20)); result.tap()
                XCTAssertTrue(app.buttons["Play from Beginning"].waitForExistence(timeout: 10))
            }
            XCTAssertEqual(app.staticTexts.matching(identifier: "Edison Kinetoscopic Record of a Sneeze (1894)").count, 2)
            let before = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            before.name = "ordered-playlist-duplicates"; before.lifetime = .keepAlways; add(before)
            app.buttons["Play from Beginning"].tap()
            let done = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.staticTexts["Playlist Finished"].isHittable }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 180), .completed)
            let after = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            after.name = "ordered-playlist-natural-completion"; after.lifetime = .keepAlways; add(after)
            app.navigationBars.buttons["Playlists"].firstMatch.tap()
            row.press(forDuration: 1)
            app.buttons["Delete Playlist"].firstMatch.tap()
            app.buttons["Delete Playlist"].firstMatch.tap()
            app.terminate()
        }

        private func openPlaylists(_ app: XCUIApplication) {
            let tab = app.tabBars.buttons["Playlists"]
            XCTAssertTrue(tab.waitForExistence(timeout: 20))
            tab.tap()
            XCTAssertTrue(app.buttons["New Playlist"].waitForExistence(timeout: 10))
        }
    }
#endif
