#if os(iOS)
    import XCTest

    /// Editing and sequencing acceptance use the task-owned local demo server.
    /// These cases establish server-backed CRUD, not physical/iCloud acceptance.
    @MainActor
    final class GusPlaylistUITests: XCTestCase {
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
            let auth = try await demoRequest("/Users/AuthenticateByName", body: ["Username": "gus", "Pw": "playa-demo"])
            let token = try XCTUnwrap(auth["AccessToken"] as? String)
            let userID = try XCTUnwrap((auth["User"] as? [String: Any])?["Id"] as? String)
            let native = try await nativeList(named: name, kind: "Playlist")
            let id = try XCTUnwrap(native?["Id"] as? String)
            let entries = try await nativeEntries(listID: id, playlist: true)
            XCTAssertGreaterThanOrEqual(entries.count, 2)
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
            app.buttons["Playlist.more"].tap()
            if app.buttons["Add to Next Up"].exists {
                app.buttons["Add to Next Up"].tap()
            } else {
                app.tap()
            }
            app.terminate(); app.launch()
            let card = try app.buttons["NextUp.card.playlist:" + XCTUnwrap(UUID(uuidString: id)).uuidString]
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
            let row = revealPlaylistRow(named: renamed, in: app)
            XCTAssertTrue(row.exists)
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
            XCTAssertEqual(app.staticTexts.matching(identifier: "Edison Kinetoscopic Record of a Sneeze (1894)").count, 1)
            let before = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            before.name = "ordered-native-playlist"; before.lifetime = .keepAlways; add(before)
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
            after.name = "ordered-playlist-natural-completion"; after.lifetime = .keepAlways; add(after)
            app.navigationBars.buttons.firstMatch.tap()
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
            let movies = app.buttons["Movies"].firstMatch
            if !movies.exists {
                let more = app.buttons["More"].firstMatch
                XCTAssertTrue(more.waitForExistence(timeout: 20)); more.tap()
            }
            XCTAssertTrue(movies.waitForExistence(timeout: 20)); movies.tap()
            let seeAll = app.buttons["See All"].firstMatch
            XCTAssertTrue(seeAll.waitForExistence(timeout: 10)); seeAll.tap()
            XCTAssertTrue(app.buttons["New Collection"].waitForExistence(timeout: 10))
            app.buttons["New Collection"].tap()
            let field = app.textFields["Name"].firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap(); field.typeText(name); app.buttons["Save"].tap()
            let row = app.staticTexts[name].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
            app.navigationBars.buttons["More"].firstMatch.tap(); app.buttons["Add Movies"].tap()
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
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10))
            let deleted = try await nativeList(named: name, kind: "BoxSet")
            XCTAssertNil(deleted)
        }

        func testPlaylistEditModeReordersRemovesAndConfirmsDeletion() async throws {
            continueAfterFailure = false
            executionTimeAllowance = 240
            let app = XCUIApplication()
            app.launchArguments = ["--gus-skip-session-restore", "--gus-demo-server", "--gus-disable-cloud-sync"]
            let name = "Actions " + UUID().uuidString.prefix(8)
            let auth = try await demoRequest("/Users/AuthenticateByName", body: ["Username": "gus", "Pw": "playa-demo"])
            let token = try XCTUnwrap(auth["AccessToken"] as? String)
            let user = try XCTUnwrap(auth["User"] as? [String: Any])
            let userID = try XCTUnwrap(user["Id"] as? String)
            _ = try await demoRequest("/Playlists", token: token, body: ["Name": name, "UserId": userID, "MediaType": "Video", "IsPublic": false])
            app.launch()
            defer { app.terminate() }
            openPlaylists(app)
            let row = revealPlaylistRow(named: name, in: app)
            XCTAssertTrue(row.exists); row.tap()
            for (query, title) in [("Sneeze", "Edison Kinetoscopic Record of a Sneeze (1894)"), ("May Irwin", "May Irwin Kiss (1896)")] {
                XCTAssertTrue(app.buttons["Add Items"].waitForExistence(timeout: 10)); app.buttons["Add Items"].tap()
                let search = app.searchFields.firstMatch
                XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText(query)
                let result = app.buttons[title].firstMatch
                XCTAssertTrue(result.waitForExistence(timeout: 20)); result.tap()
            }
            XCTAssertTrue(app.buttons["Playlist.more"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["Entries"].exists)
            let fetched = try await nativeList(named: name, kind: "Playlist")
            let native = try XCTUnwrap(fetched)
            let id = try XCTUnwrap(native["Id"] as? String)
            let original = try await nativeEntries(listID: id, playlist: true)
            XCTAssertEqual(original.count, 2)
            XCTAssertTrue(app.buttons["Playlist.shuffle"].exists)
            XCTAssertEqual(app.buttons["Playlist.shuffle"].frame.height, app.buttons["Playlist.restart"].frame.height, accuracy: 1)
            XCTAssertLessThan(app.buttons["Playlist.restart"].frame.width, app.buttons["Playlist.play"].frame.width)
            let controlsCapture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            controlsCapture.name = "playlist-playback-controls"; controlsCapture.lifetime = .keepAlways; add(controlsCapture)
            XCTAssertEqual(app.buttons.matching(identifier: "Playlist.addItems").count, 1)
            XCTAssertFalse(app.buttons["Playlist.nextUp"].exists)
            app.buttons["Playlist.more"].tap(); app.buttons["Edit Items"].tap()
            XCTAssertTrue(app.buttons["Playlist.done"].waitForExistence(timeout: 5))
            let handles = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "Playlist.reorder."))
            XCTAssertEqual(handles.count, 2)
            XCTAssertFalse(app.buttons["Playlist.play"].isEnabled)
            // Cross the first row's midpoint so UIKit inserts above it rather than at the same boundary.
            let destination = handles.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
            handles.element(boundBy: 1).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.5, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: 1.5)
            let dragCapture = XCTAttachment(string: app.debugDescription)
            dragCapture.name = "playlist-drag-receiver-hierarchy"; dragCapture.lifetime = .keepAlways; add(dragCapture)
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.staticTexts["May Irwin Kiss (1896)"].firstMatch.frame.minY < app.staticTexts["Edison Kinetoscopic Record of a Sneeze (1894)"].firstMatch.frame.minY
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed)
            let settledMove = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["Playlist.done"])
            XCTAssertEqual(XCTWaiter.wait(for: [settledMove], timeout: 15), .completed)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "playlist-after-drag-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
            let reordered = try await nativeEntries(listID: id, playlist: true)
            XCTAssertEqual(reordered.map { $0["Id"] as? String }, original.reversed().map { $0["Id"] as? String })
            let lowerTarget = handles.element(boundBy: 1).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            handles.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.5, thenDragTo: lowerTarget, withVelocity: .slow, thenHoldForDuration: 1.5)
            let movedDown = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.staticTexts["Edison Kinetoscopic Record of a Sneeze (1894)"].firstMatch.frame.minY < app.staticTexts["May Irwin Kiss (1896)"].firstMatch.frame.minY
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [movedDown], timeout: 10), .completed)
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["Playlist.done"])], timeout: 15), .completed)
            let restoredOrder = try await nativeEntries(listID: id, playlist: true)
            XCTAssertEqual(restoredOrder.map { $0["Id"] as? String }, original.map { $0["Id"] as? String })
            let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            capture.name = "playlist-native-row-reordering"; capture.lifetime = .keepAlways; add(capture)
            let trash = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "Playlist.remove.")).firstMatch
            XCTAssertTrue(trash.waitForExistence(timeout: 5)); trash.tap()
            let settledRemoval = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["Playlist.done"])
            XCTAssertEqual(XCTWaiter.wait(for: [settledRemoval], timeout: 15), .completed)
            let oneRemainingHandle = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in handles.count == 1 }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [oneRemainingHandle], timeout: 5), .completed)
            let remaining = try await nativeEntries(listID: id, playlist: true)
            XCTAssertEqual(remaining.count, 1)
            app.buttons["Playlist.done"].tap()
            XCTAssertFalse(app.buttons["Playlist.done"].exists)
            app.buttons["Playlist.more"].tap(); app.buttons["Delete Playlist"].tap()
            XCTAssertTrue(app.alerts["Delete Playlist?"].waitForExistence(timeout: 5))
            app.alerts.buttons["Cancel"].tap()
            let retained = try await nativeList(named: name, kind: "Playlist")
            XCTAssertNotNil(retained)
            app.buttons["Playlist.more"].tap(); app.buttons["Delete Playlist"].tap()
            app.alerts.buttons["Delete"].tap()
            XCTAssertTrue(app.buttons["Playlist.create"].waitForExistence(timeout: 10))
            let deleted = try await nativeList(named: name, kind: "Playlist")
            XCTAssertNil(deleted)
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
            let tab = app.tabBars.buttons["Playlists"]
            if tab.waitForExistence(timeout: 3) {
                tab.tap()
            } else if app.tabBars.firstMatch.exists {
                let more = app.tabBars.buttons["More"]
                XCTAssertTrue(more.waitForExistence(timeout: 5))
                more.tap()
                let playlists = app.buttons["Playlists"].firstMatch
                XCTAssertTrue(playlists.waitForExistence(timeout: 10))
                playlists.tap()
            } else {
                let sidebar = app.collectionViews["Sidebar"].staticTexts["Playlists"]
                XCTAssertTrue(sidebar.waitForExistence(timeout: 20))
                sidebar.tap()
            }
            XCTAssertTrue(app.buttons["Playlist.create"].waitForExistence(timeout: 10))
        }
    }
#endif
