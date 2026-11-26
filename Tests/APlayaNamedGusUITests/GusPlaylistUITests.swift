#if os(iOS)
    import XCTest

    /// Editing and sequencing acceptance use the task-owned local demo server.
    /// These cases establish server-backed CRUD, not physical/iCloud acceptance.
    @MainActor
    final class GusPlaylistUITests: XCTestCase {
        func testHomeShelfKeepsItsPositionAcrossTabs() throws {
            continueAfterFailure = false
            let app = XCUIApplication()
            app.launchArguments = [
                "--gus-skip-session-restore", "--gus-demo-server", "--gus-disable-cloud-sync", "--gus-route", "home",
                "--gus-intelligence-test-local", "--gus-intelligence-test-suite", UUID().uuidString,
            ]
            app.launch()
            defer { app.terminate() }
            let decline = app.buttons["Intelligence.prompt.decline"].firstMatch
            XCTAssertTrue(decline.waitForExistence(timeout: 30))
            decline.tap()
            XCTAssertTrue(decline.waitForNonExistence(timeout: 5))

            let heading = app.staticTexts["Recently Added Movies"].firstMatch
            XCTAssertTrue(heading.waitForExistence(timeout: 30))
            let window = app.frame
            for _ in 0 ..< 8 where heading.frame.minY > window.midY {
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
                let distance = min(window.height * 0.3, heading.frame.minY - window.height * 0.32)
                start.press(
                    forDuration: 0.1,
                    thenDragTo: start.withOffset(CGVector(dx: 0, dy: -distance)),
                    withVelocity: .slow,
                    thenHoldForDuration: 0.2
                )
            }
            XCTAssertTrue(heading.isHittable)
            let originalHeading = heading.frame
            let card = try XCTUnwrap(app.buttons.allElementsBoundByIndex.first { button in
                let frame = button.frame
                return !button.label.isEmpty && frame.height > 100 && frame.minX < window.midX &&
                    frame.minY >= originalHeading.maxY && frame.minY < originalHeading.maxY + 60
            })
            let originalCard = card.frame
            let title = card.label

            app.tabBars.buttons["Movies"].tap()
            XCTAssertTrue(app.navigationBars["Movies"].waitForExistence(timeout: 10))
            app.tabBars.buttons["Home"].tap()
            XCTAssertTrue(heading.waitForExistence(timeout: 5))
            XCTAssertTrue(heading.isHittable)
            XCTAssertEqual(heading.frame.minY, originalHeading.minY, accuracy: 1)
            let restored = try XCTUnwrap(app.buttons.matching(NSPredicate(format: "label == %@", title)).allElementsBoundByIndex.first {
                abs($0.frame.minY - originalCard.minY) <= 1
            })
            XCTAssertEqual(restored.frame.minX, originalCard.minX, accuracy: 1)
            XCTAssertEqual(restored.frame.size, originalCard.size)
        }

        func testWatchedPosterKeepsGridGeometry() async throws {
            continueAfterFailure = false
            executionTimeAllowance = 240
            let auth = try await demoRequest("/Users/AuthenticateByName", body: ["Username": "gus", "Pw": "playa-demo"])
            let token = try XCTUnwrap(auth["AccessToken"] as? String)
            let userID = try XCTUnwrap((auth["User"] as? [String: Any])?["Id"] as? String)
            let result = try await demoRequest("/Items?recursive=true&includeItemTypes=Movie&sortBy=SortName&sortOrder=Ascending&userId=" + userID, token: token)
            let items = try Array(XCTUnwrap(result["Items"] as? [[String: Any]]).prefix(2))
            XCTAssertEqual(items.count, 2)
            let titles = try items.map { try XCTUnwrap($0["Name"] as? String) }
            let ids = try items.map { try XCTUnwrap($0["Id"] as? String) }
            let app = XCUIApplication()
            defer { app.terminate() }
            for largeText in [false, true] {
                var original: [CGRect] = []
                for watched in [false, true, false] {
                    // Seed server states and reload the same view to isolate card
                    // geometry from context-menu preview and automatic scrolling.
                    for (index, id) in ids.enumerated() {
                        _ = try await demoRequest("/UserItems/" + id + "/UserData?userId=" + userID, token: token, body: ["Played": index == 0 && watched, "PlaybackPositionTicks": 0])
                    }
                    app.launchArguments = ["--gus-skip-session-restore", "--gus-demo-server", "--gus-disable-cloud-sync", "-dev.ericslutz.gus.appearance", "light", "-dev.ericslutz.gus.contentRatingLimit", "off"]
                    if largeText {
                        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
                    }
                    app.launch()
                    let movies = app.tabBars.buttons["Movies"]
                    XCTAssertTrue(movies.waitForExistence(timeout: 30)); movies.tap()
                    let cards = titles.map { title in app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch }
                    for card in cards {
                        XCTAssertTrue(card.waitForExistence(timeout: 30))
                    }
                    app.swipeUp()
                    // Shared media semantics include duration and other status
                    // components. Require the exact watched-state component.
                    XCTAssertTrue((cards[0].value as? String)?.components(separatedBy: ", ").contains(watched ? "Watched" : "Unwatched") == true)
                    XCTAssertTrue((cards[1].value as? String)?.components(separatedBy: ", ").contains("Unwatched") == true)
                    XCTAssertEqual(cards[0].frame.minY, cards[1].frame.minY, accuracy: 1)
                    XCTAssertEqual(cards[0].frame.height, cards[1].frame.height, accuracy: 1)
                    if original.isEmpty {
                        original = cards.map(\.frame)
                    }
                    for (card, before) in zip(cards, original) {
                        XCTAssertEqual(card.frame.height, before.height, accuracy: 1)
                        XCTAssertEqual(card.frame.width, before.width, accuracy: 1)
                    }
                    let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                    capture.name = "poster-\(largeText ? "large-text" : "standard")-\(watched ? "watched" : "unwatched")"
                    capture.lifetime = .keepAlways; add(capture)
                    app.terminate()
                }
            }
        }

        func testNextUpAlignmentAndContextActions() async throws {
            continueAfterFailure = false
            executionTimeAllowance = 300
            let auth = try await demoRequest("/Users/AuthenticateByName", body: ["Username": "gus", "Pw": "playa-demo"])
            let token = try XCTUnwrap(auth["AccessToken"] as? String)
            let user = try XCTUnwrap(auth["User"] as? [String: Any])
            let userID = try XCTUnwrap(user["Id"] as? String)
            let result = try await demoRequest("/Items?recursive=true&includeItemTypes=Movie,Episode&userId=" + userID, token: token)
            let items = try XCTUnwrap(result["Items"] as? [[String: Any]])
            let movie = try XCTUnwrap(items.first { $0["Type"] as? String == "Movie" && ($0["Name"] as? String)?.hasPrefix("President McKinley") == true })
            let episode = try XCTUnwrap(items.first { $0["Type"] as? String == "Episode" })
            let movieID = try XCTUnwrap(movie["Id"] as? String)
            let episodeID = try XCTUnwrap(episode["Id"] as? String)
            XCUIDevice.shared.orientation = .landscapeLeft
            defer { XCUIDevice.shared.orientation = .portrait }
            let app = XCUIApplication()
            let arguments = ["--gus-skip-session-restore", "--gus-demo-server", "--gus-disable-cloud-sync"]
            // Explicit saving also restores a dismissal left by an earlier run.
            for id in [movieID, episodeID] {
                app.launchArguments = arguments + ["--gus-route", "item/" + id]
                app.launch()
                XCTAssertTrue(app.buttons["ContentLink.detailDone"].waitForExistence(timeout: 30))
                let nextUpAction = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Remove from Next Up", "Add to Next Up")).firstMatch
                XCTAssertTrue(nextUpAction.waitForExistence(timeout: 30))
                if app.buttons["Remove from Next Up"].exists {
                    app.buttons["Remove from Next Up"].tap()
                }
                XCTAssertTrue(app.buttons["Add to Next Up"].waitForExistence(timeout: 10))
                app.buttons["Add to Next Up"].tap()
                app.terminate()
            }
            for item in [movie, episode] {
                let id = try XCTUnwrap(item["Id"] as? String)
                let ticks = max(1, (item["RunTimeTicks"] as? Int ?? 50_000_000) / 5)
                _ = try await demoRequest(
                    "/UserItems/" + id + "/UserData?userId=" + userID,
                    token: token,
                    body: ["Played": false, "PlaybackPositionTicks": ticks, "PlayedPercentage": 20, "LastPlayedDate": ISO8601DateFormatter().string(from: Date())]
                )
            }
            app.launchArguments = arguments
            app.launch()
            defer { app.terminate() }
            let movieCard = app.buttons["NextUp.card.media:jellyfin:" + movieID]
            let episodeCard = app.buttons["NextUp.card.media:jellyfin:" + episodeID]
            XCTAssertTrue(movieCard.waitForExistence(timeout: 30))
            XCTAssertTrue(episodeCard.waitForExistence(timeout: 10))
            let movieProgress = app.progressIndicators["NextUp.progress.media:jellyfin:" + movieID]
            let episodeProgress = app.progressIndicators["NextUp.progress.media:jellyfin:" + episodeID]
            XCTAssertTrue(movieProgress.exists)
            XCTAssertTrue(episodeProgress.exists)
            XCTAssertEqual(movieProgress.frame.midY, episodeProgress.frame.midY, accuracy: 1)
            XCTAssertEqual(movieCard.frame.height, episodeCard.frame.height, accuracy: 1)
            XCTAssertLessThan(movieProgress.frame.maxY, movieCard.frame.midY + movieCard.frame.height * 0.2)
            XCTAssertLessThan(episodeProgress.frame.maxY, episodeCard.frame.midY + episodeCard.frame.height * 0.2)
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "next-up-aligned-progress"; screenshot.lifetime = .keepAlways; add(screenshot)
            episodeCard.press(forDuration: 1)
            let menuHierarchy = XCTAttachment(string: app.debugDescription)
            menuHierarchy.name = "next-up-context-menu-hierarchy"; menuHierarchy.lifetime = .keepAlways; add(menuHierarchy)
            for label in ["Remove from Next Up", "Mark Watched", "Mark Unwatched", "Add to Playlist", "Add to Collection"] {
                XCTAssertTrue(app.buttons[label].waitForExistence(timeout: 5), label)
            }
            app.buttons["Remove from Next Up"].tap()
            let removed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !episodeCard.exists }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 10), .completed)
            let unchanged = try await demoRequest("/Items/" + episodeID + "?userId=" + userID, token: token)
            let unchangedData = try XCTUnwrap(unchanged["UserData"] as? [String: Any])
            XCTAssertEqual(unchangedData["PlaybackPositionTicks"] as? Int, 0)
            XCTAssertEqual(unchangedData["Played"] as? Bool, false)
            let resume = try await demoRequest("/UserItems/Resume?userId=" + userID + "&limit=1000", token: token)
            XCTAssertFalse((resume["Items"] as? [[String: Any]] ?? []).contains { $0["Id"] as? String == episodeID })
            app.terminate(); app.launch()
            XCTAssertTrue(movieCard.waitForExistence(timeout: 30))
            XCTAssertFalse(episodeCard.exists)
            movieCard.press(forDuration: 1)
            app.buttons["Mark Watched"].tap()
            let marked = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !movieProgress.exists }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [marked], timeout: 15), .completed)
            let watched = try await demoRequest("/Items/" + movieID + "?userId=" + userID, token: token)
            let watchedData = try XCTUnwrap(watched["UserData"] as? [String: Any])
            XCTAssertEqual(watchedData["PlaybackPositionTicks"] as? Int, 0)
            XCTAssertEqual(watchedData["Played"] as? Bool, true)
            app.terminate()
            app.launchArguments = arguments + ["--gus-route", "item/" + movieID]
            app.launch()
            XCTAssertTrue(app.buttons["Detail.actions"].waitForExistence(timeout: 30))
            app.buttons["Detail.actions"].tap(); app.buttons["Mark as Unwatched"].tap()
            let add = app.buttons["Add to Next Up"]
            XCTAssertTrue(add.waitForExistence(timeout: 10))
            // Wait for the acknowledged mutation before reading Jellyfin's state.
            let updated = try await waitForUnwatched(itemID: movieID, userID: userID, token: token)
            XCTAssertEqual(updated["PlaybackPositionTicks"] as? Int, 0)
            app.terminate(); app.launchArguments = arguments; app.launch()
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
            XCTAssertFalse(movieCard.exists)
            XCTAssertFalse(episodeCard.exists)
            app.terminate()
            app.launchArguments = arguments + ["--gus-route", "item/" + movieID]
            app.launch()
            XCTAssertTrue(app.buttons["Add to Next Up"].waitForExistence(timeout: 30))
            app.buttons["Add to Next Up"].tap()
            app.terminate(); app.launchArguments = arguments; app.launch()
            XCTAssertTrue(movieCard.waitForExistence(timeout: 30))
        }

        func testPlaylistRowStartsSelectedEntryAndSuppressesMembers() async throws {
            continueAfterFailure = false
            executionTimeAllowance = 240
            let name = "Actions 1C81D887"
            let native = try await nativeList(named: name, kind: "Playlist")
            let id = try XCTUnwrap(native?["Id"] as? String)
            let entries = try await nativeEntries(listID: id, playlist: true)
            XCTAssertGreaterThanOrEqual(entries.count, 2)
            let auth = try await demoRequest("/Users/AuthenticateByName", body: ["Username": "gus", "Pw": "playa-demo"])
            let token = try XCTUnwrap(auth["AccessToken"] as? String)
            let userID = try XCTUnwrap((auth["User"] as? [String: Any])?["Id"] as? String)
            for entry in entries {
                let itemID = try XCTUnwrap(entry["Id"] as? String)
                let ticks = max(1, (entry["RunTimeTicks"] as? Int ?? 50_000_000) / 5)
                _ = try await demoRequest("/UserItems/" + itemID + "/UserData?userId=" + userID, token: token, body: ["Played": false, "PlaybackPositionTicks": ticks, "PlayedPercentage": 20])
            }
            let app = XCUIApplication()
            app.launchArguments = ["--gus-skip-session-restore", "--gus-demo-server", "--gus-disable-cloud-sync"]
            app.launch(); defer { app.terminate() }
            openPlaylists(app)
            let row = revealPlaylistRow(named: name, in: app)
            XCTAssertTrue(row.exists); row.tap()
            XCTAssertTrue(app.buttons["Playlist.more"].waitForExistence(timeout: 10))
            let nextUp = app.buttons["Playlist.nextUp"]
            XCTAssertTrue(nextUp.waitForExistence(timeout: 10))
            if nextUp.label == "Add to Next Up" {
                nextUp.tap()
            }
            app.terminate(); app.launch()
            let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "NextUp.card.playlist:", name)).firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 30))
            for entry in entries {
                XCTAssertFalse(try app.buttons["NextUp.card.media:jellyfin:" + XCTUnwrap(entry["Id"] as? String)].exists)
            }
            openPlaylists(app); revealPlaylistRow(named: name, in: app).tap()
            let buttons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "Playlist.entry."))
            XCTAssertEqual(buttons.count, entries.count)
            buttons.element(boundBy: 1).tap()
            let expectedID = try XCTUnwrap(entries[1]["Id"] as? String)
            var observed = false
            for _ in 0 ..< 60 {
                let sessions = try await demoSessions(token: token)
                if sessions.contains(where: { (($0["NowPlayingItem"] as? [String: Any])?["Id"] as? String) == expectedID }) {
                    observed = true; break
                }
                try await Task.sleep(for: .milliseconds(250))
            }
            XCTAssertTrue(observed, "Tapping the second row must start that entry as playlist playback")
            let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            capture.name = "playlist-row-selected-playback"; capture.lifetime = .keepAlways; add(capture)
            let completed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.buttons["Playlist.play"].isHittable && app.staticTexts["Item 1 of 2"].exists }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 120), .completed)
            app.terminate(); app.launch()
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
            XCTAssertFalse(card.exists, "A completed playlist must stay out of Next Up after relaunch")
        }

        func testPlaylistCreateRenamePersistAndDelete() async throws {
            continueAfterFailure = false
            let app = XCUIApplication()
            app.launchArguments = ["--gus-skip-session-restore", "--gus-demo-server", "--gus-disable-cloud-sync"]
            let name = "Acceptance " + UUID().uuidString.prefix(8)
            let renamed = name + " Renamed"
            app.launch()
            openPlaylists(app)
            app.buttons["Playlist.create"].tap()
            let field = app.textFields["Name"].firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap(); field.typeText(name)
            app.buttons["Create"].tap()
            XCTAssertTrue(revealPlaylistRow(named: name, in: app).exists)
            let created = try await nativeList(named: name, kind: "Playlist")
            XCTAssertNotNil(created)
            app.staticTexts[name].tap()
            XCTAssertTrue(app.buttons["Add Items"].waitForExistence(timeout: 5))
            app.buttons["Playlist.more"].tap()
            app.buttons["Edit"].tap()
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
            let description = app.descendants(matching: .any)["MediaListEditor.description"].firstMatch
            XCTAssertTrue(description.waitForExistence(timeout: 5))
            description.tap()
            description.typeText("A description saved from Edit.")
            let save = app.buttons["MediaListEditor.save"]
            save.tap()
            XCTAssertTrue(save.waitForNonExistence(timeout: 20))
            app.terminate(); app.launch()
            openPlaylists(app)
            let row = revealPlaylistRow(named: renamed, in: app)
            XCTAssertTrue(row.exists)
            let persisted = try await nativeList(named: renamed, kind: "Playlist")
            XCTAssertEqual(persisted?["Overview"] as? String, "A description saved from Edit.")
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
            app.launchArguments = ["--gus-skip-session-restore", "--gus-demo-server", "--gus-disable-cloud-sync", "--gus-intelligence-test-unsupported"]
            app.launch()
            openPlaylists(app)
            let name = "Ordered Acceptance " + UUID().uuidString.prefix(8)
            app.buttons["Playlist.create"].tap()
            let field = app.textFields["Name"].firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap(); field.typeText(name)
            app.buttons["Create"].tap()
            let row = revealPlaylistRow(named: name, in: app)
            XCTAssertTrue(row.exists); row.tap()
            for (query, title) in [("Sneeze", "Edison Kinetoscopic Record of a Sneeze (1894)"), ("May Irwin", "May Irwin Kiss (1896)")] {
                app.buttons["Add Items"].tap()
                let search = app.searchFields.firstMatch
                XCTAssertTrue(search.waitForExistence(timeout: 10))
                search.tap(); search.typeText(query)
                let result = app.buttons[title].firstMatch
                XCTAssertTrue(result.waitForExistence(timeout: 20)); result.tap()
                XCTAssertTrue(app.buttons["Playlist.play"].waitForExistence(timeout: 10))
            }
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "Playlist.entry.", "Edison Kinetoscopic Record of a Sneeze (1894)")).count, 1)
            let before = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            before.name = "design-ordered-native-playlist"; before.lifetime = .keepAlways; add(before)
            let native = try await nativeList(named: name, kind: "Playlist")
            let nativeID = try XCTUnwrap(native?["Id"] as? String)
            let entries = try await nativeEntries(listID: nativeID, playlist: true)
            XCTAssertEqual(entries.compactMap { $0["Name"] as? String }, ["Edison Kinetoscopic Record of a Sneeze (1894)", "May Irwin Kiss (1896)"])
            app.buttons["Playlist.play"].tap()
            let done = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.buttons["Playlist.play"].isHittable && app.staticTexts["Item 1 of 2"].exists }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 180), .completed)
            XCTAssertFalse(app.staticTexts["Playlist Finished"].exists)
            XCTAssertEqual(app.buttons["Playlist.play"].label, "Play")
            let after = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            after.name = "design-ordered-playlist-natural-completion"; after.lifetime = .keepAlways; add(after)
            app.navigationBars[name].buttons.firstMatch.tap()
            row.press(forDuration: 1)
            app.buttons["Delete"].firstMatch.tap()
            app.buttons["Delete"].firstMatch.tap()
            app.terminate()
        }

        func testNativeCollectionCreateAddRemoveAndDelete() async throws {
            continueAfterFailure = false
            XCUIDevice.shared.orientation = .portrait
            let app = XCUIApplication()
            app.launchArguments = ["--gus-skip-session-restore", "--gus-demo-server", "--gus-disable-cloud-sync"]
            let name = "Collection Acceptance " + UUID().uuidString.prefix(8)
            app.launch()
            let movies = UIDevice.current.userInterfaceIdiom == .pad
                ? app.staticTexts["Navigation.section.category.movies"].firstMatch
                : app.buttons["Movies"].firstMatch
            if UIDevice.current.userInterfaceIdiom != .pad, !movies.exists {
                let more = app.buttons["More"].firstMatch
                XCTAssertTrue(more.waitForExistence(timeout: 20)); more.tap()
            }
            XCTAssertTrue(movies.waitForExistence(timeout: 20)); movies.tap()
            let collections = app.buttons["Library.collections"].firstMatch
            XCTAssertTrue(collections.waitForExistence(timeout: 10)); collections.tap()
            XCTAssertTrue(app.buttons["New Collection"].waitForExistence(timeout: 10))
            app.buttons["New Collection"].tap()
            let field = app.textFields["Name"].firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap(); field.typeText(name); app.buttons["Save"].tap()
            let row = app.staticTexts[name].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
            app.navigationBars.buttons["More"].firstMatch.tap(); app.buttons["Add Titles"].tap()
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 10))
            search.tap(); search.typeText("Sneeze")
            let title = "Edison Kinetoscopic Record of a Sneeze (1894)"
            let result = app.buttons[title].firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 20)); result.tap()
            let addMovies = app.navigationBars.buttons["Add"].firstMatch
            if !addMovies.exists {
                let closeSearch = app.buttons["close"].firstMatch
                XCTAssertTrue(closeSearch.waitForExistence(timeout: 5)); closeSearch.tap()
            }
            XCTAssertTrue(addMovies.waitForExistence(timeout: 10)); addMovies.tap()
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["1 title"].exists)
            let collection = try await nativeList(named: name, kind: "BoxSet")
            let id = try XCTUnwrap(collection?["Id"] as? String)
            let before = try await nativeEntries(listID: id, playlist: false)
            XCTAssertEqual(before.count, 1)
            app.navigationBars.buttons["More"].firstMatch.tap()
            app.buttons["Edit"].tap()
            let description = app.descendants(matching: .any)["MediaListEditor.description"].firstMatch
            XCTAssertTrue(description.waitForExistence(timeout: 10))
            description.tap()
            let note = "Saved from the collection editor."
            description.typeText(note)
            let save = app.buttons["MediaListEditor.save"]
            save.tap()
            XCTAssertTrue(save.waitForNonExistence(timeout: 20))
            XCTAssertTrue(app.staticTexts[note].waitForExistence(timeout: 10))
            app.staticTexts[title].firstMatch.tap()
            let membership = app.staticTexts[name].firstMatch
            XCTAssertTrue(membership.waitForExistence(timeout: 10)); membership.tap()
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10))
            let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            capture.name = "native-collection-membership"; capture.lifetime = .keepAlways; add(capture)
            app.staticTexts[title].press(forDuration: 1)
            app.buttons["Remove from " + name].firstMatch.tap()
            XCTAssertTrue(app.staticTexts["No Titles"].waitForExistence(timeout: 10))
            let after = try await nativeEntries(listID: id, playlist: false)
            XCTAssertTrue(after.isEmpty)
            app.navigationBars.buttons["More"].firstMatch.tap(); app.buttons["Delete Collection"].tap()
            app.buttons["Delete Collection"].firstMatch.tap()
            let returnedToMovie = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let play = app.buttons["Detail.play"]
                return play.exists && play.isHittable && app.staticTexts[title].firstMatch.exists && !app.buttons["Delete Collection"].exists && !app.staticTexts[name].exists
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [returnedToMovie], timeout: 10), .completed)
            let deleted = try await nativeList(named: name, kind: "BoxSet")
            XCTAssertNil(deleted)
        }

        func testPlaylistEditModeReordersRemovesAndConfirmsDeletion() async throws {
            continueAfterFailure = false
            executionTimeAllowance = 240
            let name = "Actions " + UUID().uuidString.prefix(8)
            let auth = try await demoRequest("/Users/AuthenticateByName", body: ["Username": "gus", "Pw": "playa-demo"])
            let token = try XCTUnwrap(auth["AccessToken"] as? String)
            let userID = try XCTUnwrap((auth["User"] as? [String: Any])?["Id"] as? String)
            var movieIDs: [String] = []
            for (query, title) in [("Sneeze", "Edison Kinetoscopic Record of a Sneeze (1894)"), ("May%20Irwin", "May Irwin Kiss (1896)")] {
                let result = try await demoRequest("/Items?userId=" + userID + "&recursive=true&includeItemTypes=Movie&searchTerm=" + query, token: token)
                let items = try XCTUnwrap(result["Items"] as? [[String: Any]])
                try movieIDs.append(XCTUnwrap(items.first { $0["Name"] as? String == title }?["Id"] as? String))
            }
            let native = try await demoRequest("/Playlists", token: token, body: ["Name": name, "UserId": userID, "MediaType": "Video", "IsPublic": false, "Ids": movieIDs])
            let id = try XCTUnwrap(native["Id"] as? String)
            let app = XCUIApplication()
            app.launchArguments = ["--gus-skip-session-restore", "--gus-demo-server", "--gus-disable-cloud-sync", "--gus-route", "item/" + id]
            app.launch()
            defer { app.terminate() }
            XCTAssertTrue(app.buttons["Playlist.more"].waitForExistence(timeout: 25))
            XCTAssertFalse(app.staticTexts["Entries"].exists)
            let original = try await nativeEntries(listID: id, playlist: true)
            XCTAssertEqual(original.count, 2)
            XCTAssertTrue(app.buttons["Playlist.shuffle"].waitForExistence(timeout: 20))
            XCTAssertEqual(app.buttons["Playlist.shuffle"].frame.height, app.buttons["Playlist.restart"].frame.height, accuracy: 1)
            XCTAssertLessThan(app.buttons["Playlist.restart"].frame.width, app.buttons["Playlist.play"].frame.width)
            let controlsCapture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            controlsCapture.name = "design-playlist-playback-controls"; controlsCapture.lifetime = .keepAlways; add(controlsCapture)
            XCTAssertEqual(app.buttons.matching(identifier: "Playlist.addItems").count, 1)
            let nextUp = app.buttons["Playlist.nextUp"]
            let restart = app.buttons["Playlist.restart"]
            let shuffle = app.buttons["Playlist.shuffle"]
            XCTAssertTrue(nextUp.exists)
            XCTAssertLessThanOrEqual(app.buttons["Playlist.play"].frame.maxY, nextUp.frame.minY)
            XCTAssertEqual(nextUp.frame.midY, shuffle.frame.midY, accuracy: 1)
            XCTAssertEqual(restart.frame.minX - nextUp.frame.maxX, shuffle.frame.minX - restart.frame.maxX, accuracy: 1)
            let handles = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "Playlist.reorder."))
            XCTAssertEqual(handles.count, 0)
            let rows = app.cells.containing(NSPredicate(format: "identifier BEGINSWITH %@", "Playlist.entry."))
            XCTAssertEqual(rows.count, 2)
            let lastRow = rows.element(boundBy: 1)
            if lastRow.frame.maxY > app.frame.maxY - 100 {
                app.swipeUp()
            }
            let destination = rows.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.05))
            rows.element(boundBy: 1).coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
                .press(forDuration: 1.5, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: 1.2)
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.staticTexts["May Irwin Kiss (1896)"].firstMatch.frame.minY < app.staticTexts["Edison Kinetoscopic Record of a Sneeze (1894)"].firstMatch.frame.minY
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 15), .completed)
            let reordered = try await nativeEntries(listID: id, playlist: true)
            XCTAssertEqual(reordered.map { $0["Id"] as? String }, original.reversed().map { $0["Id"] as? String })

            let firstEntry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "Playlist.entry.", "May Irwin")).firstMatch
            firstEntry.swipeLeft()
            let swipeRemove = app.buttons["Remove May Irwin Kiss (1896)"].firstMatch
            XCTAssertTrue(swipeRemove.waitForExistence(timeout: 5))
            swipeRemove.tap()
            XCTAssertTrue(firstEntry.waitForNonExistence(timeout: 15))

            app.buttons["Playlist.more"].tap(); app.buttons["Edit"].tap()
            let save = app.buttons["MediaListEditor.save"]
            XCTAssertTrue(save.waitForExistence(timeout: 5))
            let removal = app.images["minus.circle.fill"].firstMatch
            XCTAssertTrue(removal.waitForExistence(timeout: 5)); removal.tap()
            app.buttons["Delete"].firstMatch.tap()
            let staged = try await nativeEntries(listID: id, playlist: true)
            XCTAssertEqual(staged.count, 1)
            app.buttons["Cancel"].firstMatch.tap()
            app.buttons["Discard Changes"].firstMatch.tap()
            XCTAssertTrue(save.waitForNonExistence(timeout: 5))
            let afterCancel = try await nativeEntries(listID: id, playlist: true)
            XCTAssertEqual(afterCancel.count, 1)

            app.buttons["Playlist.more"].tap(); app.buttons["Edit"].tap()
            XCTAssertTrue(removal.waitForExistence(timeout: 5)); removal.tap()
            app.buttons["Delete"].firstMatch.tap()
            save.tap()
            XCTAssertTrue(save.waitForNonExistence(timeout: 15))
            let remaining = try await nativeEntries(listID: id, playlist: true)
            XCTAssertTrue(remaining.isEmpty)
            app.buttons["Playlist.more"].tap(); app.buttons["Delete Playlist"].tap()
            XCTAssertTrue(app.alerts["Delete Playlist?"].waitForExistence(timeout: 5))
            app.alerts.buttons["Cancel"].tap()
            let retained = try await nativeList(named: name, kind: "Playlist")
            XCTAssertNotNil(retained)
            app.buttons["Playlist.more"].tap(); app.buttons["Delete Playlist"].tap()
            app.alerts.buttons["Delete"].tap()
            XCTAssertTrue(app.buttons["Playlist.more"].waitForNonExistence(timeout: 10))
            let deleted = try await nativeList(named: name, kind: "Playlist")
            XCTAssertNil(deleted)
        }

        func testPlaybackHelpExplainsEachSettingWithoutChangingIt() throws {
            continueAfterFailure = false
            let app = XCUIApplication()
            app.launchEnvironment["GUS_DEMO_URL"] = ProcessInfo.processInfo.environment["GUS_DEMO_URL"]
            app.launchArguments = ["--gus-skip-session-restore", "--gus-demo-server", "--gus-disable-cloud-sync", "--gus-route", "settings"]
            app.launch()
            defer { app.terminate() }
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 30))
            let invitation = app.buttons["Intelligence.prompt.decline"]
            if invitation.waitForExistence(timeout: 3) {
                invitation.tap()
                XCTAssertTrue(invitation.waitForNonExistence(timeout: 5))
            }

            let qualityPicker = app.descendants(matching: .any).matching(identifier: "Settings.streamingQuality").firstMatch
            for (label, explanation) in [
                ("About Streaming Quality", "Maximum lets compatible files play at original quality."),
                ("About Remembering Episode Tracks", "Gus remembers the audio and subtitle choices"),
            ] {
                let help = app.buttons[label]
                for _ in 0 ..< 5 where !help.isHittable {
                    app.swipeUp()
                }
                XCTAssertTrue(help.isHittable)
                let message = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", explanation)).firstMatch
                XCTAssertFalse(message.exists)
                let toggle = app.switches["Settings.rememberEpisodeTracks"]
                let control = label == "About Streaming Quality" ? qualityPicker : toggle
                XCTAssertTrue(control.isHittable)
                let originalSetting = try XCTUnwrap(control.value as? String)
                XCTAssertLessThanOrEqual(help.frame.maxX, control.frame.minX + 1)
                XCTAssertEqual(help.frame.midY, control.frame.midY, accuracy: 2)
                help.tap()
                XCTAssertTrue(message.waitForExistence(timeout: 5))
                let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                capture.name = label
                capture.lifetime = .keepAlways
                add(capture)
                // Dismiss using the native popover's backdrop.
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.12)).tap()
                XCTAssertTrue(message.waitForNonExistence(timeout: 5))
                XCTAssertEqual(control.value as? String, originalSetting)
            }

            let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            capture.name = "Playback settings with native quality picker"
            capture.lifetime = .keepAlways
            add(capture)

            let originalQuality = try XCTUnwrap(qualityPicker.value as? String)
            let nextQuality = originalQuality == "Low (3 Mbps)" ? "High (20 Mbps)" : "Low (3 Mbps)"
            qualityPicker.tap()
            for title in ["Maximum (Original)", "High (20 Mbps)", "Medium (8 Mbps)", "Low (3 Mbps)"] {
                XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 5), title)
            }
            app.buttons[nextQuality].tap()
            XCTAssertEqual(qualityPicker.value as? String, nextQuality)
            qualityPicker.tap()
            app.buttons[originalQuality].tap()
            XCTAssertEqual(qualityPicker.value as? String, originalQuality)
        }

        func testItemDetailMoreMenuKeepsRestartSeparateFromWatched() async throws {
            continueAfterFailure = false
            let auth = try await demoRequest("/Users/AuthenticateByName", body: ["Username": "gus", "Pw": "playa-demo"])
            let token = try XCTUnwrap(auth["AccessToken"] as? String)
            let user = try XCTUnwrap(auth["User"] as? [String: Any])
            let userID = try XCTUnwrap(user["Id"] as? String)
            let result = try await demoRequest("/Items?recursive=true&includeItemTypes=Movie&userId=" + userID, token: token)
            let movies = try XCTUnwrap(result["Items"] as? [[String: Any]])
            let movie = try XCTUnwrap(movies.first)
            let movieID = try XCTUnwrap(movie["Id"] as? String)
            let ticks = max(1, (movie["RunTimeTicks"] as? Int ?? 50_000_000) / 5)
            _ = try await demoRequest("/UserItems/" + movieID + "/UserData?userId=" + userID, token: token, body: ["Played": false, "PlaybackPositionTicks": ticks])
            let app = XCUIApplication()
            app.launchArguments = ["--gus-skip-session-restore", "--gus-demo-server", "--gus-disable-cloud-sync", "--gus-route", "item/" + movieID]
            app.launch()
            defer { app.terminate() }
            XCTAssertTrue(app.buttons["Detail.play"].waitForExistence(timeout: 30))
            XCTAssertEqual(app.buttons["Detail.play"].label, "Resume")
            let next = app.buttons["Detail.nextUp"]
            let restart = app.buttons["Detail.restart"]
            XCTAssertTrue(next.exists); XCTAssertTrue(restart.exists)
            XCTAssertLessThan(next.frame.minX, restart.frame.minX)
            XCTAssertGreaterThanOrEqual(restart.frame.height, 44)
            XCTAssertFalse(app.buttons["Mark as Watched"].exists)
            app.buttons["Detail.actions"].tap()
            for label in ["Add to Playlist", "Add to Collection", "Mark as Watched"] {
                XCTAssertTrue(app.buttons[label].waitForExistence(timeout: 5), label)
            }
            let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            capture.name = "item-detail-management-menu"; capture.lifetime = .keepAlways; add(capture)
            // Another client marks it watched after this menu captured its action.
            _ = try await demoRequest("/UserItems/" + movieID + "/UserData?userId=" + userID, token: token, body: ["Played": true, "PlaybackPositionTicks": ticks])
            app.buttons["Mark as Watched"].tap()
            XCTAssertTrue(app.buttons["Detail.play"].waitForExistence(timeout: 10))
            let play = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Play"), object: app.buttons["Detail.play"])
            XCTAssertEqual(XCTWaiter.wait(for: [play], timeout: 10), .completed)
            let watched = try await demoRequest("/Items/" + movieID + "?userId=" + userID, token: token)
            let data = try XCTUnwrap(watched["UserData"] as? [String: Any])
            XCTAssertEqual(data["Played"] as? Bool, true)
            XCTAssertEqual(data["PlaybackPositionTicks"] as? Int, 0)
        }

        func testItemDetailActionsRemainAccessibleAtLargestTextSize() async throws {
            continueAfterFailure = false
            let auth = try await demoRequest("/Users/AuthenticateByName", body: ["Username": "gus", "Pw": "playa-demo"])
            let token = try XCTUnwrap(auth["AccessToken"] as? String)
            let result = try await demoRequest("/Items?recursive=true&includeItemTypes=Movie", token: token)
            let movies = try XCTUnwrap(result["Items"] as? [[String: Any]])
            let movie = try XCTUnwrap(movies.first?["Id"] as? String)
            let app = XCUIApplication()
            app.launchArguments = ["--gus-skip-session-restore", "--gus-demo-server", "--gus-disable-cloud-sync", "--gus-route", "item/" + movie, "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            app.launch()
            defer { app.terminate() }
            XCTAssertTrue(app.buttons["Detail.play"].waitForExistence(timeout: 30))
            let actions = [app.buttons["Detail.nextUp"], app.buttons["Detail.restart"]]
            for action in actions {
                XCTAssertTrue(action.exists)
                XCTAssertGreaterThanOrEqual(action.frame.width, 44)
                XCTAssertGreaterThanOrEqual(action.frame.height, 44)
            }
            XCTAssertFalse(actions[0].frame.intersects(actions[1].frame))
            XCTAssertGreaterThanOrEqual(actions[0].frame.minY, app.buttons["Detail.play"].frame.maxY)
            let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            capture.name = "item-detail-largest-text"; capture.lifetime = .keepAlways; add(capture)
        }

        private func demoSessions(token: String) async throws -> [[String: Any]] {
            var request = URLRequest(url: URL(string: "http://localhost:8096/Sessions")!)
            request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
            let (data, response) = try await URLSession.shared.data(for: request)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        }

        private func waitForUnwatched(itemID: String, userID: String, token: String) async throws -> [String: Any] {
            var data: [String: Any] = [:]
            for _ in 0 ..< 50 {
                let result = try await demoRequest("/Items/" + itemID + "?userId=" + userID, token: token)
                data = result["UserData"] as? [String: Any] ?? [:]
                if data["Played"] as? Bool == false {
                    return data
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTFail("Jellyfin did not confirm Mark Unwatched")
            return data
        }

        private func demoRequest(_ path: String, token: String? = nil, body: [String: Any]? = nil) async throws -> [String: Any] {
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
            let result = try await demoRequest("/Items?recursive=true&fields=Overview&includeItemTypes=" + kind, token: token)
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

        /// Native Lists realize rows on demand; existing demo fixtures can put
        /// this test's newly created name below the initial viewport.
        private func revealPlaylistRow(named name: String, in app: XCUIApplication) -> XCUIElement {
            let row = app.staticTexts[name]
            if row.waitForExistence(timeout: 5), row.isHittable, row.frame.maxY < app.frame.height - 140 {
                return row
            }
            for _ in 0 ..< 8 {
                app.swipeUp()
                if row.exists, row.isHittable, row.frame.maxY < app.frame.height - 140 {
                    return row
                }
            }
            return row
        }

        private func openPlaylists(_ app: XCUIApplication) {
            if UIDevice.current.userInterfaceIdiom == .pad {
                XCUIDevice.shared.orientation = .landscapeLeft
            }
            let tab = app.tabBars.buttons["Playlists"]
            if tab.waitForExistence(timeout: 3) {
                tab.tap()
            } else if app.tabBars.firstMatch.exists {
                XCTAssertTrue(app.openMoreIndex())
                let playlists = app.buttons["Playlists"].firstMatch
                XCTAssertTrue(playlists.waitForExistence(timeout: 10))
                playlists.tap()
            } else {
                let show = app.sidebarToggle
                if !app.collectionViews["Sidebar"].firstMatch.isHittable, show.isHittable {
                    show.tap()
                }
                let sidebar = app.descendants(matching: .any)["Navigation.section.playlists"].firstMatch
                XCTAssertTrue(sidebar.waitForExistence(timeout: 20))
                sidebar.tap()
            }
            XCTAssertTrue(app.buttons["Playlist.create"].waitForExistence(timeout: 10))
        }
    }
#endif
