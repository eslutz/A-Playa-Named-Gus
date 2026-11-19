#if os(iOS)
    import UIKit
    import XCTest

    /// Repeatable visual walkthrough of the real demo server, shared by baseline and redesign.
    /// Attachments stay in the external result bundle; no captured pixels belong in source.
    /// Run in a dedicated simulator: optional-category captures change demo navigation
    /// preferences, which the comparison workflow backs up and restores.
    @MainActor
    final class GusDesignCaptureUITests: XCTestCase {
        private var media: [[String: String]] = []
        private var demoToken = ""

        override func setUp() async throws {
            continueAfterFailure = false
            executionTimeAllowance = 600
            XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
            var request = URLRequest(url: URL(string: "http://127.0.0.1:8096/Users/AuthenticateByName")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let device = UIDevice.current.identifierForVendor?.uuidString ?? "simulator"
            request.setValue("MediaBrowser Client=\"GusDesignReview\", Device=\"XCTest\", DeviceId=\"gus-design-review-\(device)\", Version=\"1\"", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["Username": "gus", "Pw": "playa-demo"])
            let (data, _) = try await URLSession.shared.data(for: request)
            let auth = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let token = try XCTUnwrap(auth["AccessToken"] as? String)
            demoToken = token
            let user = try XCTUnwrap(auth["User"] as? [String: Any])
            let id = try XCTUnwrap(user["Id"] as? String)
            request = URLRequest(url: URL(string: "http://127.0.0.1:8096/Users/\(id)/Items?Recursive=true&Limit=1000")!)
            request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
            let (items, _) = try await URLSession.shared.data(for: request)
            let result = try XCTUnwrap(JSONSerialization.jsonObject(with: items) as? [String: Any])
            media = (result["Items"] as? [[String: Any]] ?? []).compactMap { item in
                guard let id = item["Id"] as? String, let name = item["Name"] as? String, let type = item["Type"] as? String else { return nil }
                return ["id": id, "name": name, "type": type]
            }
        }

        override nonisolated func tearDown() async throws {
            await MainActor.run {
                XCUIApplication().terminate()
                XCUIDevice.shared.orientation = .portrait
            }
            try await super.tearDown()
        }

        func testIPadR2SearchAndSidebar() throws {
            guard UIDevice.current.userInterfaceIdiom == .pad else {
                throw XCTSkip("Requires an iPad")
            }
            XCUIDevice.shared.orientation = .landscapeLeft
            let app = launch("home")
            let hide = app.buttons["Navigation.hideSidebar"]
            XCTAssertTrue(hide.waitForExistence(timeout: 30))
            XCTAssertEqual(app.buttons.allElementsBoundByIndex.filter {
                $0.isHittable && $0.label.localizedCaseInsensitiveContains("sidebar")
            }.count, 1)
            XCTAssertFalse(app.searchFields.firstMatch.exists)
            hide.tap()
            let show = app.buttons["Navigation.showSidebar"]
            XCTAssertTrue(show.waitForExistence(timeout: 5))
            show.tap()
            let search = app.descendants(matching: .any)["Navigation.search"].firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            search.tap()
            let field = app.searchFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 10))
            field.tap()
            field.typeText("Popeye")
            hide.tap()
            XCTAssertTrue(show.waitForExistence(timeout: 5))
            show.tap()
            XCTAssertEqual(field.value as? String, "Popeye")
            let mode = app.buttons["Search.displayMode"]
            XCTAssertTrue(mode.waitForExistence(timeout: 15))
            mode.tap()
            XCTAssertEqual(mode.label, "Grid")
            XCUIDevice.shared.orientation = .portrait
            XCTAssertEqual(field.value as? String, "Popeye")
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertEqual(field.value as? String, "Popeye")
        }

        func testIPadR2MainWindowNavigation() throws {
            guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("Requires an iPad") }
            let album = try XCTUnwrap(media.first { $0["type"] == "MusicAlbum" })
            let app = try launch("item/" + XCTUnwrap(album["id"]))
            let title = try XCTUnwrap(album["name"])
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 30))
            XCTAssertTrue(app.buttons["Navigation.hideSidebar"].exists)
            XCTAssertFalse(app.buttons["ContentLink.detailDone"].exists)
            let back = app.navigationBars[title].buttons["Home"]
            XCTAssertTrue(back.exists)
            back.tap()
            XCTAssertTrue(app.navigationBars["Home"].exists)
        }

        func testIPadR2ScopedLayoutsAndProfileDraft() throws {
            guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("Requires an iPad") }
            let app = launch("home")
            XCTAssertTrue(waitForRoot(app))
            XCTAssertTrue(openDestination("Music", app))
            let mode = app.buttons["Library.displayMode"]
            XCTAssertTrue(mode.waitForExistence(timeout: 15))
            XCTAssertEqual(mode.label, "List")
            mode.tap()
            XCTAssertEqual(mode.label, "Grid")
            XCTAssertTrue(openDestination("Home", app))
            XCTAssertTrue(openDestination("Music", app))
            XCTAssertEqual(mode.label, "Grid")
            XCTAssertTrue(openDestination("Photos", app))
            XCTAssertTrue(mode.waitForExistence(timeout: 15))
            XCTAssertEqual(mode.label, "List", "A different library keeps its own display choice")
            let albums = app.buttons["Albums"].firstMatch
            XCTAssertTrue(albums.waitForExistence(timeout: 10))
            albums.tap()
            XCTAssertTrue(albums.isSelected)
            XCTAssertTrue(openDestination("Home", app))
            XCTAssertTrue(openDestination("Photos", app))
            XCTAssertTrue(albums.isSelected)

            XCTAssertTrue(openDestination("Settings", app))
            let profile = app.buttons["View and Edit Profile"].firstMatch
            XCTAssertTrue(profile.waitForExistence(timeout: 15))
            profile.tap()
            let username = app.textFields["Username"]
            XCTAssertTrue(username.waitForExistence(timeout: 15))
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: username)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
            let original = try XCTUnwrap(username.value as? String)
            username.tap()
            username.typeText(" draft")
            XCUIDevice.shared.orientation = .portrait
            XCTAssertEqual(username.value as? String, original + " draft")
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertEqual(username.value as? String, original + " draft")
            app.buttons["Cancel"].firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Profile"].waitForNonExistence(timeout: 10))
        }

        func testIPadR2SettingsScrollPositions() throws {
            guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("Requires an iPad") }
            let app = launch("settings")
            XCTAssertTrue(waitForRoot(app))
            let theme = app.buttons["Settings.theme"]
            for _ in 0 ..< 8 where !theme.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(theme.isHittable)
            capture("settings-middle")
            let version = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Version")).firstMatch
            for _ in 0 ..< 8 where !version.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(version.isHittable)
            capture("settings-lower")
        }

        func testConnection() {
            let app = launch(nil)
            XCTAssertTrue(app.textFields["ConnectServerView.serverAddress"].waitForExistence(timeout: 15))
            capture("connect")
            let field = app.textFields["ConnectServerView.serverAddress"]
            field.tap()
            field.typeText("http://127.0.0.1:8096")
            capture("connect-keyboard")
            app.buttons["ConnectServerView.connectButton"].tap()
            XCTAssertTrue(app.secureTextFields.firstMatch.waitForExistence(timeout: 20))
            dismissKeyboard(app)
            capture("sign-in")
            if let options = button("More sign-in options", app) {
                options.tap()
                capture("sign-in-options")
            }
            let quick = app.buttons["Use Quick Connect"].firstMatch
            XCTAssertTrue(quick.waitForExistence(timeout: 15))
            if quick.isHittable {
                quick.tap()
                XCTAssertTrue(app.staticTexts["Authorization code"].waitForExistence(timeout: 15))
                capture("quick-connect")
            }
        }

        func testRootDestinations() {
            for (route, name) in [("home", "home"), ("libraries", "libraries"), ("downloaded", "downloads"), ("settings", "settings")] {
                let app = launch(route)
                XCTAssertTrue(waitForRoot(app))
                capture(name)
                if route == "home", UIDevice.current.userInterfaceIdiom == .pad {
                    capture("more")
                }
                if route == "home", let show = button("Show All", app) {
                    show.tap()
                    capture("next-up")
                }
                if route == "settings" {
                    if let profile = button("View and Edit Profile", app) {
                        profile.tap()
                        capture("profile")
                        dismissSheet(app)
                    }
                    app.swipeUp()
                    capture("settings-middle")
                    app.swipeUp()
                    capture("settings-lower")
                }
            }
        }

        func testThemeAndNextUpOptions() {
            let app = launch("settings")
            let theme = app.buttons["Settings.theme"]
            for _ in 0 ..< 8 where !theme.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(theme.waitForExistence(timeout: 10))
            theme.tap(); app.buttons["Apple Default"].firstMatch.tap()
            capture("theme-apple")
            app.terminate(); app.launch()
            for _ in 0 ..< 8 where !theme.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(theme.label.contains("Apple Default"))
            theme.tap(); app.buttons["Custom"].firstMatch.tap()
            capture("theme-custom")
            let picker = app.buttons["Settings.accentColor"]
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            picker.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)).tap()
            XCTAssertTrue(app.staticTexts["Colors"].waitForExistence(timeout: 5) || app.buttons["Sliders"].exists)
            capture("theme-color-picker")
            app.buttons["Sliders"].firstMatch.tap()
            capture("theme-color-picker-sliders")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "color-picker-slider-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
            let hex = app.textFields.matching(NSPredicate(format: "label CONTAINS[c] %@ OR value MATCHES[c] %@", "Hex", "[A-F0-9]{6}")).firstMatch
            XCTAssertTrue(hex.waitForExistence(timeout: 5))
            hex.tap()
            hex.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "C66000")
            XCTAssertEqual((hex.value as? String)?.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: "# ")), "C66000")
            capture("theme-color-picker-sliders")
            app.terminate(); app.launch()
            for _ in 0 ..< 8 where !theme.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(theme.label.contains("Custom"))
            capture("theme-custom-picked")
            theme.tap()
            XCTAssertTrue(app.buttons["Gus Default"].firstMatch.waitForExistence(timeout: 5))
            app.buttons["Gus Default"].firstMatch.tap()
            capture("theme-gus")
            let home = launch("home")
            XCTAssertTrue(waitForRoot(home))
            if let show = button("Show All", home) {
                show.tap()
                let layout = home.buttons["NextUp.displayMode"]
                XCTAssertTrue(layout.waitForExistence(timeout: 10))
                capture("next-up")
                layout.tap(); capture("next-up-grid")
                layout.tap()
            }
        }

        func testProfileCancelAndSave() async throws {
            let testName = "gus-profile-" + UUID().uuidString.prefix(8)
            let password = "profile-fixture"
            var create = try URLRequest(url: XCTUnwrap(URL(string: "http://127.0.0.1:8096/Users/New")))
            create.httpMethod = "POST"
            create.setValue(demoToken, forHTTPHeaderField: "X-Emby-Token")
            create.setValue("application/json", forHTTPHeaderField: "Content-Type")
            create.httpBody = try JSONSerialization.data(withJSONObject: ["Name": testName, "Password": password])
            let (data, _) = try await URLSession.shared.data(for: create)
            let user = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let id = try XCTUnwrap(user["Id"] as? String)
            let userURL = try XCTUnwrap(URL(string: "http://127.0.0.1:8096/Users/" + id))
            let token = demoToken
            addTeardownBlock {
                var remove = URLRequest(url: userURL)
                remove.httpMethod = "DELETE"
                remove.setValue(token, forHTTPHeaderField: "X-Emby-Token")
                let (_, response) = try await URLSession.shared.data(for: remove)
                XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 204)
            }

            let app = launch("settings", environment: ["GUS_DEMO_USERNAME": testName, "GUS_DEMO_PASSWORD": password])
            let profile = app.buttons["View and Edit Profile"].firstMatch
            XCTAssertTrue(profile.waitForExistence(timeout: 30)); profile.tap()
            let save = app.buttons["Profile.save"]
            let username = app.textFields["Username"]
            XCTAssertTrue(username.waitForExistence(timeout: 15))
            let populated = NSPredicate(format: "value == %@ AND enabled == true", testName)
            await fulfillment(of: [XCTNSPredicateExpectation(predicate: populated, object: username)], timeout: 15)
            XCTAssertTrue(app.buttons["Change Profile Picture"].exists)
            XCTAssertFalse(save.exists && save.isEnabled)
            capture("profile")
            username.tap(); username.typeText(" discard")
            XCTAssertFalse(save.exists && save.isEnabled)
            app.buttons["Cancel"].firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Profile"].waitForNonExistence(timeout: 10))

            profile.tap()
            await fulfillment(of: [XCTNSPredicateExpectation(predicate: populated, object: username)], timeout: 15)
            username.tap(); username.typeText(" updated")
            username.typeText("\n")
            let current = app.secureTextFields["Current Password"]
            for _ in 0 ..< 6 where !current.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(current.isHittable)
            current.tap(); current.typeText(password)
            XCTAssertTrue(save.isEnabled)
            save.tap()
            XCTAssertTrue(app.navigationBars["Profile"].waitForNonExistence(timeout: 20))
            profile.tap()
            await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", testName + " updated"), object: username)], timeout: 15)
            XCTAssertFalse(save.exists && save.isEnabled)
        }

        func testLibraryCategories() {
            for (title, name) in [("Movies", "movies"), ("Shows", "shows"), ("Music", "music"), ("Books", "books"), ("Photos", "photos"), ("Live TV", "live-tv"), ("Discover", "discover"), ("Playlists", "playlists")] {
                let app = launch("home")
                XCTAssertTrue(waitForRoot(app))
                guard openDestination(title, app) else { continue }
                capture(name)
                if name == "movies", let filter = button("Sort and Filter", app) ?? button("Filter", app) {
                    filter.tap()
                    capture("movies-filter")
                }
                if name == "playlists", let create = button("Playlist.create", app) {
                    create.tap()
                    capture("playlist-new")
                }
                if name == "discover", let connect = button("Seerr.connect", app) ?? button("Connect Seerr", app) ?? button("Connect", app) {
                    connect.tap()
                    capture("seerr-connect")
                }
            }
        }

        func testDetails() {
            for (type, name) in [("Movie", "movie"), ("Series", "series"), ("Episode", "episode"), ("MusicArtist", "artist"), ("MusicAlbum", "album"), ("Book", "book"), ("Playlist", "playlist"), ("BoxSet", "collection")] {
                guard let item = media.first(where: { $0["type"] == type }), let id = item["id"] else { continue }
                let app = launch("item/" + id)
                if UIDevice.current.userInterfaceIdiom == .pad {
                    XCTAssertTrue(app.navigationBars[item["name"] ?? ""].waitForExistence(timeout: 30))
                    XCTAssertFalse(app.buttons["ContentLink.detailDone"].exists)
                } else {
                    XCTAssertTrue(app.buttons["ContentLink.detailDone"].waitForExistence(timeout: 30))
                }
                capture(name + "-detail")
                if type == "Movie" || type == "Episode" {
                    app.swipeUp()
                    capture(name + "-lower")
                    app.swipeUp()
                    capture(name + "-about")
                }
                if type == "Movie", let actions = button("Detail.actions", app) {
                    actions.tap()
                    capture("movie-actions")
                    if let add = button("Add to Playlist", app) {
                        add.tap()
                        capture("add-to-playlist")
                    }
                }
                if type == "Playlist", let more = button("Playlist.more", app) ?? button("More", app) {
                    more.tap()
                    capture("playlist-detail-actions")
                }
            }
        }

        func testGenreSearchOpensMembersAndRestoresQuery() {
            let app = launch("search", environment: ["GUS_DEMO_URL": "http://127.0.0.1:5061"])
            let field = app.searchFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 30))
            field.tap()
            field.typeText("Horror")
            let result = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "Search.genre.")).firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 20))
            XCTAssertTrue(result.label.contains("Horror"))
            result.tap()
            let navigation = app.navigationBars["Horror"]
            XCTAssertTrue(navigation.waitForExistence(timeout: 12))
            XCTAssertFalse(app.buttons["Detail.play"].exists)
            XCTAssertTrue(app.buttons["Library.displayMode"].exists)
            let member = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "The Lantern House")).firstMatch
            XCTAssertTrue(member.waitForExistence(timeout: 12))
            capture("genre-horror")
            navigation.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(field.waitForExistence(timeout: 8))
            XCTAssertEqual(field.value as? String, "Horror")
            XCTAssertTrue(result.exists)
        }

        func testSynopsisRespondsToWidthAndAccessibilityText() throws {
            guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("Uses an iPhone portrait and landscape width") }
            XCUIDevice.shared.orientation = .portrait
            defer { XCUIDevice.shared.orientation = .portrait }
            let fixture = ["GUS_DEMO_URL": "http://127.0.0.1:5060"]
            let long = launch("item/46000000000000000000000000000001", environment: fixture)
            let preview = long.staticTexts["Detail.heroOverview"]
            let more = long.buttons["Detail.fullSynopsis"]
            XCTAssertTrue(preview.waitForExistence(timeout: 20))
            XCTAssertTrue(more.waitForExistence(timeout: 5))
            let synopsis = preview.label
            more.tap()
            XCTAssertTrue(long.staticTexts["Synopsis.body"].waitForExistence(timeout: 5))
            XCTAssertEqual(long.staticTexts["Synopsis.body"].label, synopsis)
            long.buttons["Synopsis.done"].tap()
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(more.waitForNonExistence(timeout: 8))
            XCUIDevice.shared.orientation = .portrait
            XCTAssertTrue(more.waitForExistence(timeout: 8))
            let shortRoute = "item/46000000000000000000000000000002"
            let short = launch(shortRoute, environment: fixture)
            XCTAssertTrue(short.staticTexts["Detail.heroOverview"].waitForExistence(timeout: 20))
            XCTAssertFalse(short.buttons["Detail.fullSynopsis"].exists)
            let enlarged = launch(shortRoute, largeText: true, environment: fixture)
            XCTAssertTrue(enlarged.staticTexts["Detail.heroOverview"].waitForExistence(timeout: 20))
            XCTAssertTrue(enlarged.buttons["Detail.fullSynopsis"].waitForExistence(timeout: 8))
        }

        func testArtworkDetailsInBothAppearances() throws {
            for (type, name) in [("Movie", "movie"), ("Book", "book"), ("MusicAlbum", "album")] {
                let item = try XCTUnwrap(media.first { $0["type"] == type })
                let id = try XCTUnwrap(item["id"])
                for appearance in ["light", "dark"] {
                    let app = launch("item/" + id, appearance: appearance)
                    let detail = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", item["name"] ?? "")).firstMatch
                    XCTAssertTrue(detail.waitForExistence(timeout: 25))
                    capture(name + "-detail-" + appearance)
                }
            }
        }

        func testSearchAndNavigation() {
            let app = launch("search")
            XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 30))
            capture("search-entry")
            let field = app.searchFields.firstMatch
            field.tap()
            field.typeText("Sneeze")
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Sneeze")).firstMatch.waitForExistence(timeout: 20))
            dismissKeyboard(app)
            capture("search-results")
            field.tap()
            if let clear = button("Clear text", app) {
                clear.tap()
            }
            // A new query explicitly focuses the native field after clearing.
            field.tap()
            field.typeText("zzzz-no-match-98765")
            dismissKeyboard(app)
            XCTAssertTrue(app.staticTexts["No Results"].waitForExistence(timeout: 20))
            capture("search-empty")

            let settings = launch("settings")
            XCTAssertTrue(waitForRoot(settings))
            for _ in 0 ..< 3 {
                if let nav = button("Navigation", settings), nav.isHittable {
                    nav.tap()
                    capture("navigation")
                    if let edit = button("Edit", settings) {
                        edit.tap()
                        capture("navigation-edit")
                    }
                    break
                }
                settings.swipeUp()
            }
        }

        func testAudioAndBook() {
            if let item = media.first(where: { $0["type"] == "Audio" && !($0["name"] ?? "").hasPrefix("Repeat QA") }), let id = item["id"] {
                let app = launch("play/" + id)
                XCTAssertTrue(app.buttons[UIDevice.current.userInterfaceIdiom == .pad ? "AudioPlayer.close" : "Close"].waitForExistence(timeout: 30))
                if let pause = button("Pause", app) {
                    pause.tap()
                }
                capture("audio-player")
                let queue = app.buttons["Queue"].firstMatch
                if queue.waitForExistence(timeout: 5) {
                    let previous = app.buttons["Previous Track"].firstMatch
                    if UIDevice.current.userInterfaceIdiom != .pad {
                        XCTAssertEqual(queue.frame.midY, previous.frame.midY, accuracy: 2)
                        XCTAssertGreaterThan(queue.frame.midY, app.frame.height * 0.65)
                    }
                    queue.tap()
                    XCTAssertTrue(app.navigationBars["Queue"].waitForExistence(timeout: 5))
                    capture("audio-queue")
                    app.buttons["Close"].firstMatch.tap()
                }
                let close = app.buttons["AudioPlayer.close"]
                if close.isHittable {
                    close.tap()
                }
                capture("audio-accessory")
            }
            if let item = media.first(where: { $0["type"] == "Book" && $0["name"] == "Dracula" }), let id = item["id"] {
                let app = launch("item/" + id)
                if let read = button("Read", app), read.waitForExistence(timeout: 30) {
                    read.tap()
                    capture("book-reader")
                    if let chapters = button("Chapters", app) {
                        chapters.tap()
                        capture("book-chapters")
                    }
                }
            }
        }

        func testNextUpLibraryListReview() throws {
            for item in media.filter({ ["Movie", "Episode"].contains($0["type"] ?? "") }).prefix(6) {
                let app = try launch("item/" + XCTUnwrap(item["id"]))
                let action = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Add to Next Up", "Remove from Next Up")).firstMatch
                XCTAssertTrue(action.waitForExistence(timeout: 30))
                if action.label == "Add to Next Up" {
                    action.tap()
                }
            }
            let app = launch("home")
            let showAll = app.buttons["Show All"].firstMatch
            XCTAssertTrue(showAll.waitForExistence(timeout: 30)); showAll.tap()
            let layout = app.buttons["NextUp.displayMode"]
            XCTAssertTrue(layout.waitForExistence(timeout: 10))
            if layout.label.contains("List") {
                layout.tap()
            }
            XCTAssertFalse(app.staticTexts["Saved"].exists)
            XCTAssertFalse(app.staticTexts["Resume · Saved"].exists)
            capture("next-up-library-list")
            layout.tap()
            XCTAssertTrue(layout.label.contains("List"))
            capture("next-up-library-grid")
            layout.tap()
            XCTAssertTrue(layout.label.contains("Grid"))
        }

        func testReviewFollowUp() throws {
            // Enrich only the synthetic demo account, through the same public UI as a user.
            let candidates = Array(media.filter { ["Movie", "Episode"].contains($0["type"] ?? "") }.prefix(6))
            XCTAssertGreaterThanOrEqual(candidates.count, 4)
            for item in candidates {
                let app = try launch("item/" + XCTUnwrap(item["id"]))
                let action = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Add to Next Up", "Remove from Next Up")).firstMatch
                XCTAssertTrue(action.waitForExistence(timeout: 30))
                if action.label == "Add to Next Up" {
                    action.tap()
                }
            }
            let app = launch("home")
            let showAll = app.buttons["Show All"].firstMatch
            XCTAssertTrue(showAll.waitForExistence(timeout: 30)); showAll.tap()
            let layout = app.buttons["NextUp.displayMode"]
            XCTAssertTrue(layout.waitForExistence(timeout: 10))
            if layout.label.contains("List") {
                layout.tap()
            }
            capture("next-up")
            XCTAssertTrue(openDestination("Playlists", launch("home")))
            capture("playlists")
            capture("playlist-actions")
            let create = app.buttons["Playlist.create"]
            XCTAssertTrue(create.waitForExistence(timeout: 10))
            XCTAssertLessThan(create.frame.width, 64)
            create.tap()
            XCTAssertTrue(app.textFields["Name"].waitForExistence(timeout: 5))
            capture("playlist-new")
            app.buttons["Cancel"].firstMatch.tap()
            let playlist = try XCTUnwrap(media.first { $0["type"] == "Playlist" })
            let row = try app.staticTexts[XCTUnwrap(playlist["name"])].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
            XCTAssertTrue(app.buttons["Playlist.more"].waitForExistence(timeout: 10))
            capture("ordered-native-playlist")
            app.buttons["Playlist.more"].tap(); app.buttons["Edit"].tap()
            XCTAssertTrue(app.buttons["MediaListEditor.save"].waitForExistence(timeout: 5))
            capture("playlist-edit")
            app.buttons["Cancel"].firstMatch.tap()
            XCTAssertTrue(app.buttons["Playlist.addItems"].exists)
        }

        func testSettingsMenusAndDownloads() {
            let app = launch("settings")
            XCTAssertTrue(app.buttons["View and Edit Profile"].waitForExistence(timeout: 30))
            for (prefix, name) in [("Streaming Quality", "settings-quality"), ("Appearance", "settings-appearance"), ("Limit Content Ratings", "settings-rating")] {
                for _ in 0 ..< 6 {
                    let target = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
                    if target.exists, target.isHittable {
                        target.tap()
                        capture(name)
                        app.tap()
                        break
                    }
                    app.swipeUp()
                }
            }
            let downloads = launch("downloaded")
            XCTAssertTrue(waitForRoot(downloads))
            if let manage = button("Manage Downloads", downloads) {
                manage.tap()
                capture("downloads-manager")
            }
        }

        func testPhotoAndBookViewer() {
            for (type, name) in [("Photo", "photo-viewer"), ("PhotoAlbum", "photo-album")] {
                guard let item = media.first(where: { $0["type"] == type }), let id = item["id"] else { continue }
                let app = launch("item/" + id)
                if UIDevice.current.userInterfaceIdiom == .pad {
                    XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 30))
                } else {
                    XCTAssertTrue(app.buttons["ContentLink.detailDone"].waitForExistence(timeout: 30))
                }
                capture(name)
            }
            if let item = media.first(where: { $0["name"] == "Dracula" }), let id = item["id"] {
                let app = launch("item/" + id)
                let read = app.buttons["Read"].firstMatch
                if read.waitForExistence(timeout: 30) {
                    read.tap()
                    XCTAssertTrue(app.buttons["BookReader.done"].waitForExistence(timeout: 30))
                    capture("book-reader")
                    let chapters = app.buttons["Chapters"].firstMatch
                    if chapters.waitForExistence(timeout: 10) {
                        chapters.tap()
                        capture("book-chapters")
                    }
                }
            }
        }

        func testLibraryDisplayModes() throws {
            let libraries = launch("libraries")
            XCTAssertTrue(waitForRoot(libraries))
            let musicLibrary = libraries.buttons["Music"].firstMatch
            XCTAssertTrue(musicLibrary.waitForExistence(timeout: 30))
            let libraryMode = try XCTUnwrap(button("Libraries.displayMode", libraries))
            libraryMode.tap()
            XCTAssertTrue(musicLibrary.waitForExistence(timeout: 10))
            XCTAssertFalse(libraries.staticTexts["Something Went Wrong"].exists)
            capture("libraries-grid")

            let movies = launch("home")
            XCTAssertTrue(waitForRoot(movies))
            XCTAssertTrue(movies.staticTexts["Recently Added Movies"].firstMatch.waitForExistence(timeout: 30))
            XCTAssertFalse(movies.staticTexts["Some Content Could Not Be Refreshed"].exists)
            XCTAssertTrue(openDestination("Movies", movies))
            let collectionsLink = movies.buttons["Library.collections"]
            XCTAssertTrue(collectionsLink.waitForExistence(timeout: 10))
            let mode = try XCTUnwrap(button("Library.displayMode", movies))
            mode.tap()
            capture("movies-list")
            mode.tap()
            capture("movies-grid")
            XCTAssertTrue(collectionsLink.isHittable)
        }

        func testMusicDisplayModes() {
            let app = launch("home")
            XCTAssertTrue(waitForRoot(app))
            XCTAssertTrue(openDestination("Music", app))
            capture("music")
            if let mode = button("Library.displayMode", app) {
                XCTAssertTrue(app.staticTexts["Artists"].waitForExistence(timeout: 15))
                mode.tap()
                capture("music-list")
            }
        }

        func testPushedMediaAndCollectionScreens() {
            let app = launch("home")
            XCTAssertTrue(waitForRoot(app))
            if openDestination("Movies", app), let movie = media.first(where: { $0["type"] == "Movie" }), let name = movie["name"] {
                let row = app.buttons[name].firstMatch
                if row.waitForExistence(timeout: 20) {
                    row.tap()
                    XCTAssertTrue(app.buttons["Detail.play"].waitForExistence(timeout: 20))
                    capture("movie-pushed")
                }
            }
            let playlists = launch("home")
            XCTAssertTrue(waitForRoot(playlists))
            if openDestination("Playlists", playlists), let playlist = media.first(where: { $0["type"] == "Playlist" }), let name = playlist["name"] {
                let row = playlists.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
                if row.waitForExistence(timeout: 20) {
                    row.press(forDuration: 1)
                    capture("playlist-actions")
                    playlists.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.95)).tap()
                    row.tap()
                    capture("playlist-pushed")
                    if let more = button("Playlist.more", playlists) {
                        more.tap()
                        if let edit = button("Edit", playlists) {
                            edit.tap()
                            capture("playlist-edit")
                            if let done = button("Cancel", playlists) {
                                done.tap()
                            }
                        }
                    }
                }
            }
            let collections = launch("home")
            XCTAssertTrue(waitForRoot(collections))
            if openDestination("Collections", collections) {
                capture("collections-grid")
                if let collection = media.first(where: { $0["type"] == "BoxSet" }), let name = collection["name"] {
                    let row = collections.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
                    if row.waitForExistence(timeout: 10) {
                        row.tap(); capture("collection-pushed")
                    }
                }
            }
        }

        func testDownloadManagementStates() throws {
            let item = try XCTUnwrap(media.first { $0["type"] == "Movie" && ($0["name"] ?? "").contains("May Irwin") })
            let id = try XCTUnwrap(item["id"])
            let title = try XCTUnwrap(item["name"])
            let app = launch("item/" + id)
            XCTAssertTrue(waitForMovieDetail(app))
            let download = app.buttons["Download"].firstMatch
            let createdHere = download.waitForExistence(timeout: 5)
            if createdHere {
                download.tap()
                capture("download-in-progress", waitsForLoading: false)
            }
            let state = app.buttons["Detail.download"].firstMatch
            XCTAssertTrue(state.waitForExistence(timeout: 10))
            if !app.buttons["Downloaded"].firstMatch.waitForExistence(timeout: 30) {
                capture("download-in-progress", waitsForLoading: false)
            }
            let downloaded = launch("downloaded")
            XCTAssertTrue(waitForRoot(downloaded))
            capture("downloads-populated")
            let manage = try XCTUnwrap(button("Manage Downloads", downloaded))
            manage.tap()
            XCTAssertTrue(downloaded.buttons["Downloads.select"].waitForExistence(timeout: 10))
            XCTAssertFalse(downloaded.staticTexts["Soft Cap"].exists)
            XCTAssertFalse(downloaded.buttons["Downloads.deleteSelected"].exists)
            capture("downloads-manager-populated")
            downloaded.buttons["Downloads.select"].tap()
            XCTAssertFalse(downloaded.buttons["Downloads.deleteSelected"].exists)
            capture("downloads-select-none")
            let selectAll = downloaded.buttons["Select All"]
            XCTAssertTrue(selectAll.waitForExistence(timeout: 5))
            selectAll.tap()
            XCTAssertTrue(downloaded.buttons["Downloads.deleteSelected"].exists)
            downloaded.buttons["Deselect All"].tap()
            XCTAssertFalse(downloaded.buttons["Downloads.deleteSelected"].exists)
            let row = downloaded.staticTexts[title].firstMatch
            for _ in 0 ..< 5 where !row.isHittable {
                downloaded.swipeUp()
            }
            XCTAssertTrue(row.isHittable)
            row.tap()
            capture("downloads-select-one")
            let delete = downloaded.buttons["Downloads.deleteSelected"]
            XCTAssertTrue(delete.waitForExistence(timeout: 5))
            XCTAssertTrue(delete.isHittable)
            delete.tap()
            XCTAssertTrue(downloaded.alerts["Delete Downloads?"].waitForExistence(timeout: 5))
            capture("downloads-delete-confirmation")
            if createdHere {
                downloaded.alerts.buttons["Delete Download"].tap()
            } else {
                downloaded.alerts.buttons["Cancel"].tap()
            }
        }

        func testLargeTextDownloadedRows() {
            let settings = launch("settings")
            let theme = settings.buttons["Settings.theme"]
            for _ in 0 ..< 8 where !theme.isHittable {
                settings.swipeUp()
            }
            XCTAssertTrue(theme.waitForExistence(timeout: 10))
            theme.tap(); settings.buttons["Gus Default"].firstMatch.tap()
            guard let item = media.first(where: { $0["type"] == "Movie" && ($0["name"] ?? "").contains("Sneeze") }), let id = item["id"], let title = item["name"] else { return XCTFail("Missing rights-cleared long-title movie") }
            let detail = launch("item/" + id)
            XCTAssertTrue(waitForMovieDetail(detail))
            let download = detail.buttons["Download"].firstMatch
            let createdHere = download.waitForExistence(timeout: 5)
            if createdHere {
                download.tap()
                capture("download-in-progress", waitsForLoading: false)
            }
            let browse = launch("downloaded")
            XCTAssertTrue(browse.staticTexts[title].firstMatch.waitForExistence(timeout: 90))
            if UIDevice.current.userInterfaceIdiom == .pad {
                XCUIDevice.shared.orientation = .portrait
            }
            let large = launch("downloaded", largeText: true)
            XCTAssertTrue(large.staticTexts[title].firstMatch.waitForExistence(timeout: 30))
            if UIDevice.current.userInterfaceIdiom == .pad {
                let hide = large.buttons["Navigation.hideSidebar"]
                if hide.isHittable {
                    hide.tap()
                }
                XCTAssertTrue(large.buttons["Navigation.showSidebar"].waitForExistence(timeout: 5))
            }
            capture("downloads-browse-large-text")
            let manage = large.buttons["Manage Downloads"].firstMatch
            XCTAssertTrue(manage.waitForExistence(timeout: 10)); manage.tap()
            let row = large.staticTexts[title].firstMatch
            for _ in 0 ..< 12 where !row.isHittable {
                large.swipeUp()
            }
            XCTAssertTrue(row.isHittable)
            capture("downloads-manage-large-text")
            let normal = launch("downloaded")
            if createdHere {
                normal.buttons["Manage Downloads"].firstMatch.tap()
                normal.buttons["Downloads.select"].tap()
                let select = normal.staticTexts[title].firstMatch
                for _ in 0 ..< 8 where !select.isHittable {
                    normal.swipeUp()
                }
                XCTAssertTrue(select.isHittable); select.tap()
                let delete = normal.buttons["Downloads.deleteSelected"]
                for _ in 0 ..< 8 where !delete.isHittable {
                    normal.swipeDown()
                }
                delete.tap()
                XCTAssertTrue(normal.alerts["Delete Downloads?"].waitForExistence(timeout: 5))
                normal.alerts.buttons["Delete Download"].tap()
            }
        }

        /// Hidden categories remain available even when the demo has no matching server view.
        func testOptionalPhotoAndLiveTVSections() {
            for title in ["Photos", "Live TV"] {
                let settings = launch("settings")
                XCTAssertTrue(waitForRoot(settings))
                let nav = settings.buttons["Navigation"].firstMatch
                for _ in 0 ..< 6 where !nav.isHittable {
                    settings.swipeUp()
                }
                XCTAssertTrue(nav.isHittable)
                nav.tap()
                XCTAssertTrue(settings.buttons["Edit"].waitForExistence(timeout: 10))
                settings.buttons["Edit"].tap()
                let categoryID = title == "Photos" ? "photos" : "livetv"
                let hidden = settings.buttons["Navigation.show.category." + categoryID].firstMatch
                for _ in 0 ..< 7 {
                    if hidden.isHittable, hidden.frame.maxY < settings.frame.height - 140 {
                        break
                    }
                    settings.swipeUp()
                }
                capture("navigation-optional-edit")
                if hidden.isHittable {
                    hidden.tap()
                    XCTAssertTrue(hidden.waitForNonExistence(timeout: 10))
                }
                settings.buttons["Done"].firstMatch.tap()
                let app = settings
                XCTAssertTrue(openDestination("Home", app))
                XCTAssertTrue(openDestination(title, app))
                capture(title == "Photos" ? "photos" : "live-tv")
                if title == "Photos" {
                    let albums = app.buttons["Albums"].firstMatch
                    if albums.waitForExistence(timeout: 5) {
                        albums.tap()
                        capture("photos-albums")
                        if let mode = button("Library.displayMode", app) {
                            mode.tap()
                            capture("photos-albums-list")
                        }
                    }
                }
            }
        }

        private func launch(_ route: String?, largeText: Bool = false, appearance: String = "light", environment: [String: String] = [:]) -> XCUIApplication {
            let app = XCUIApplication()
            app.terminate()
            app.launchEnvironment.merge(environment) { _, new in new }
            app.launchArguments = ["--gus-skip-session-restore", "--gus-disable-cloud-sync", "-dev.ericslutz.gus.appearance", appearance, "-dev.ericslutz.gus.contentRatingLimit", "off"]
            if largeText {
                app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            }
            if let route {
                app.launchArguments += ["--gus-demo-server", "--gus-route", route]
            }
            app.launch()
            return app
        }

        private func waitForMovieDetail(_ app: XCUIApplication) -> Bool {
            app.buttons[UIDevice.current.userInterfaceIdiom == .pad ? "Detail.play" : "ContentLink.detailDone"].waitForExistence(timeout: 30)
        }

        private func waitForRoot(_ app: XCUIApplication) -> Bool {
            if UIDevice.current.userInterfaceIdiom == .pad {
                return app.buttons["Navigation.hideSidebar"].waitForExistence(timeout: 30)
            }
            return app.tabBars.firstMatch.waitForExistence(timeout: 30)
        }

        private func openDestination(_ title: String, _ app: XCUIApplication) -> Bool {
            let titles = title == "Shows" ? ["Shows", "Series"] : [title]
            if UIDevice.current.userInterfaceIdiom == .pad {
                let show = app.buttons["Navigation.showSidebar"]
                if show.isHittable {
                    show.tap()
                }
                if title == "Search" {
                    let search = app.descendants(matching: .any)["Navigation.search"].firstMatch
                    guard search.waitForExistence(timeout: 5) else { return false }
                    search.tap()
                    return true
                }
                let row = app.descendants(matching: .any).matching(NSPredicate(
                    format: "identifier BEGINSWITH %@ AND label IN %@", "Navigation.section.", titles
                )).firstMatch
                for _ in 0 ..< 5 {
                    if row.exists && row.isHittable {
                        row.tap(); return true
                    }
                    app.collectionViews.firstMatch.swipeUp()
                }
                return false
            }
            if let tab = app.tabBars.buttons.matching(NSPredicate(format: "label IN %@", titles)).allElementsBoundByIndex.first, tab.isHittable {
                tab.tap()
                return true
            }
            guard let more = button("More", app) else { return false }
            more.tap()
            capture("more")
            for _ in 0 ..< 4 {
                if let target = button(title, app), target.isHittable {
                    target.tap(); return true
                }
                app.swipeUp()
            }
            return false
        }

        private func button(_ label: String, _ app: XCUIApplication) -> XCUIElement? {
            app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", label, label)).allElementsBoundByIndex.first
        }

        private func dismissKeyboard(_ app: XCUIApplication) {
            guard app.keyboards.firstMatch.exists else { return }
            // A keyboard can outlive its field briefly during navigation. Tap its
            // native action instead of sending text to an unfocused application.
            let actions = ["Search", "search", "Go", "go", "Done", "done", "Return", "return", "Hide keyboard", "Dismiss keyboard"]
            if let key = app.keyboards.buttons.matching(NSPredicate(format: "label IN %@", actions))
                .allElementsBoundByIndex.first(where: \.isHittable)
            {
                key.tap()
            }
        }

        private func dismissSheet(_ app: XCUIApplication) {
            if let done = button("Close", app) ?? button("Done", app) ?? button("Cancel", app), done.isHittable {
                done.tap()
            } else if let back = button("Back", app), back.isHittable {
                back.tap()
            } else {
                app.swipeDown()
            }
        }

        private func capture(_ name: String, waitsForLoading: Bool = true) {
            // Let ordinary images settle; progress captures must retain active indicators.
            let app = XCUIApplication()
            if waitsForLoading {
                _ = app.activityIndicators.firstMatch.waitForNonExistence(timeout: 15)
            }
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "design-" + name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    final class GusBookDetailUITests: XCTestCase {
        func testSharePresentsTheOriginalBookInSystemActivities() {
            continueAfterFailure = false
            let app = XCUIApplication()
            app.launchEnvironment["GUS_DEMO_URL"] = ProcessInfo.processInfo.environment["GUS_BOOK_SHARE_FIXTURE_URL"] ?? "http://127.0.0.1:5058"
            app.launchArguments = [
                "--gus-skip-session-restore", "--gus-disable-cloud-sync", "--gus-demo-server",
                "--gus-route", "item/42000000000000000000000000000001",
                "-dev.ericslutz.gus.contentRatingLimit", "off",
            ]
            app.launch()
            defer { app.terminate() }
            let menu = app.buttons["Detail.actions"].firstMatch
            XCTAssertTrue(menu.waitForExistence(timeout: 25))
            menu.tap()
            let share = app.buttons["Book.share"].firstMatch
            XCTAssertEqual(share.label, "Share")
            share.tap()
            let filename = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "Fixture original edition")).firstMatch
            XCTAssertTrue(filename.waitForExistence(timeout: 15), app.debugDescription)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Book native share sheet"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        func testAudiobookSynopsisAtLargestTextSize() throws {
            continueAfterFailure = false
            let app = XCUIApplication()
            app.launchEnvironment["GUS_DEMO_URL"] = "http://127.0.0.1:5058"
            app.launchArguments = [
                "--gus-skip-session-restore", "--gus-disable-cloud-sync", "--gus-demo-server",
                "--gus-route", "item/42000000000000000000000000000002",
                "-dev.ericslutz.gus.contentRatingLimit", "off",
                "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
            ]
            app.launch()
            defer { app.terminate() }
            let byline = app.staticTexts["Narrated by Fixture Reader"].firstMatch
            XCTAssertTrue(byline.waitForExistence(timeout: 25))
            let showMore = app.buttons["Detail.fullSynopsis"].firstMatch
            for _ in 0 ..< 8 where !showMore.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(showMore.isHittable)
            showMore.tap()
            let heading = app.staticTexts["Synopsis.heading"].firstMatch
            XCTAssertTrue(heading.waitForExistence(timeout: 10))
            XCTAssertEqual(heading.label, "Fixture Audiobook")
            XCTAssertTrue(app.staticTexts["Synopsis.body"].firstMatch.label.contains("A second paragraph."))
            try app.performAccessibilityAudit(for: [.sufficientElementDescription])
        }

        func testMixedLibraryBookAndAudiobookDetails() {
            continueAfterFailure = false
            let app = XCUIApplication()
            defer { app.terminate() }
            for (index, title, action) in [
                (1, "Fixture Printed Book", "Continue Reading"),
                (2, "Fixture Audiobook", "Resume"),
            ] {
                app.terminate()
                app.launchEnvironment["GUS_DEMO_URL"] = "http://127.0.0.1:5058"
                app.launchArguments = [
                    "--gus-skip-session-restore", "--gus-disable-cloud-sync", "--gus-demo-server",
                    "--gus-route", "item/4200000000000000000000000000000\(index)",
                    "-dev.ericslutz.gus.contentRatingLimit", "off",
                ]
                app.launch()
                XCTAssertTrue(app.staticTexts[title].firstMatch.waitForExistence(timeout: 25))
                XCTAssertTrue(app.buttons[action].firstMatch.exists)
                XCTAssertTrue(app.descendants(matching: .any)["Detail.bookProgress"].firstMatch.exists)
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = title
                screenshot.lifetime = .keepAlways
                add(screenshot)
                XCTAssertFalse(app.staticTexts["Cast & Crew"].exists)
                XCTAssertFalse(app.staticTexts["Fixture Studio"].exists)

                XCTAssertFalse(app.staticTexts["Credits"].exists)
                XCTAssertTrue(app.staticTexts["By Fixture Author"].exists)
                if index == 2 {
                    XCTAssertTrue(app.staticTexts["Narrated by Fixture Reader"].exists)
                    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Released 2025", "Duration")).firstMatch.exists)
                } else {
                    XCTAssertTrue(app.staticTexts["Published 2024"].exists)
                    XCTAssertFalse(app.buttons["Share"].exists)
                }

                let menu = app.buttons["Detail.actions"].firstMatch
                menu.tap()
                XCTAssertTrue(app.buttons[index == 1 ? "Mark as Read" : "Mark as Finished"].firstMatch.exists)
                XCTAssertEqual(app.buttons["Book.share"].exists, index == 1)
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.8)).tap()

                let preview = app.staticTexts["Detail.heroOverview"].firstMatch
                XCTAssertFalse(preview.label.contains(#"\n"#))
                let showMore = app.buttons["Detail.fullSynopsis"].firstMatch
                for _ in 0 ..< 4 where !showMore.isHittable {
                    app.swipeUp()
                }
                showMore.tap()
                XCTAssertTrue(app.staticTexts["Synopsis.heading"].firstMatch.waitForExistence(timeout: 5))
                let end = index == 1 ? "Second printed paragraph." : "A second paragraph."
                let fullText = app.staticTexts["Synopsis.body"].firstMatch
                XCTAssertTrue(fullText.label.contains("\n\n" + end))
                app.buttons["Synopsis.done"].tap()

                let genre = app.staticTexts[index == 1 ? "Fantasy" : "Movie, TV & Video Game Tie-Ins"].firstMatch
                for _ in 0 ..< 5 where !genre.exists {
                    app.swipeUp()
                }
                XCTAssertTrue(genre.exists)
                XCTAssertTrue(app.staticTexts["Adventure"].exists)
            }
        }

        private func openShelf(_ destination: String, in app: XCUIApplication) {
            if UIDevice.current.userInterfaceIdiom == .pad {
                let show = app.buttons["Navigation.showSidebar"]
                if show.isHittable {
                    show.tap()
                }
                let row = app.descendants(matching: .any).matching(NSPredicate(
                    format: "identifier BEGINSWITH %@ AND label == %@", "Navigation.section.", destination
                )).firstMatch
                let sidebar = app.collectionViews.firstMatch
                XCTAssertTrue(sidebar.waitForExistence(timeout: 25))
                for _ in 0 ..< 5 where !row.isHittable {
                    sidebar.swipeUp()
                }
                XCTAssertTrue(row.isHittable)
                row.tap()
                XCTAssertTrue(app.navigationBars[destination].waitForExistence(timeout: 10))
                return
            }
            let home = app.tabBars.buttons["Home"].firstMatch
            XCTAssertTrue(home.waitForExistence(timeout: 25))
            home.tap()
            let tab = app.tabBars.buttons[destination].firstMatch
            if tab.isHittable {
                tab.tap()
            } else {
                let more = app.tabBars.buttons["More"].firstMatch
                XCTAssertTrue(more.waitForExistence(timeout: 25))
                more.tap()
                let entry = app.buttons[destination].firstMatch
                XCTAssertTrue(entry.waitForExistence(timeout: 15))
                entry.tap()
            }
            XCTAssertTrue(app.navigationBars[destination].waitForExistence(timeout: 10))
        }

        func testEditBookSeriesAndReviewPartialSave() throws {
            guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("Uses the compact navigation tabs") }
            continueAfterFailure = false
            let app = XCUIApplication()
            app.launchEnvironment["GUS_DEMO_URL"] = "http://127.0.0.1:5059"
            app.launchArguments = [
                "--gus-skip-session-restore", "--gus-disable-cloud-sync", "--gus-demo-server",
                "-dev.ericslutz.gus.contentRatingLimit", "off",
            ]
            app.launch()
            defer { app.terminate() }
            openShelf("Books", in: app)

            let new = app.buttons["New Series"].firstMatch
            XCTAssertTrue(new.waitForExistence(timeout: 15))
            new.tap()
            let bookID = "42000000000000000000000000000001"
            let member = app.buttons["BookSeries.member." + bookID].firstMatch
            XCTAssertTrue(member.waitForExistence(timeout: 10))
            member.tap()
            XCTAssertTrue(member.isSelected)
            let name = app.textFields["Name"].firstMatch
            name.tap()
            name.typeText("Created Series")
            XCTAssertEqual(name.value as? String, "Created Series")
            let review = app.buttons["Review Changes"].firstMatch
            XCTAssertTrue(review.isEnabled)
            review.tap()
            let save = app.buttons["Save"].firstMatch
            XCTAssertTrue(save.waitForExistence(timeout: 8))
            XCTAssertTrue(save.isEnabled)
            let preview = app.descendants(matching: .any)["BookSeries.review." + bookID].firstMatch
            XCTAssertTrue(preview.waitForExistence(timeout: 5))
            XCTAssertTrue(preview.label.contains("Fixture Printed Book"))
            XCTAssertTrue(preview.label.contains("Created Series"))
            save.tap()
            let created = app.buttons["Created Series"].firstMatch
            XCTAssertTrue(created.waitForExistence(timeout: 20))

            app.buttons["Fixture Saga"].firstMatch.tap()
            let edit = app.buttons["Edit Series"].firstMatch
            XCTAssertTrue(edit.waitForExistence(timeout: 12))
            edit.tap()
            name.tap()
            name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Fixture Saga".count) + "Interrupted Series")
            XCTAssertEqual(name.value as? String, "Interrupted Series")
            XCTAssertTrue(review.isEnabled)
            review.tap()
            XCTAssertTrue(save.waitForExistence(timeout: 8))
            save.tap()

            let confirmed = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "BookSeries.confirmed.")).firstMatch
            let unconfirmed = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "BookSeries.unconfirmed.")).firstMatch
            XCTAssertTrue(confirmed.waitForExistence(timeout: 20))
            XCTAssertTrue(unconfirmed.exists)
            XCTAssertEqual(Set([confirmed.label, unconfirmed.label]), ["First Volume", "Second Volume"])
            app.buttons["Done"].firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Fixture Saga"].waitForExistence(timeout: 10))
        }

        func testCustomCollectionAcrossBookShelves() {
            continueAfterFailure = false
            let app = XCUIApplication()
            app.launchEnvironment["GUS_DEMO_URL"] = "http://127.0.0.1:5059"
            app.launchArguments = [
                "--gus-skip-session-restore", "--gus-disable-cloud-sync", "--gus-demo-server",
                "-dev.ericslutz.gus.contentRatingLimit", "off",
            ]
            app.launch()
            defer { app.terminate() }
            openShelf("Books", in: app)
            let book = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Fixture Printed Book")).firstMatch
            XCTAssertTrue(book.waitForExistence(timeout: 12))
            book.press(forDuration: 1)
            app.buttons["Add to Collection"].firstMatch.tap()
            let name = "Reading Together"
            let field = app.textFields["Name"].firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 10))
            field.tap()
            field.typeText(name)
            XCTAssertEqual(field.value as? String, name)
            field.typeText("\n")
            let create = app.buttons["Create and Add"].firstMatch
            XCTAssertTrue(create.isEnabled)
            create.tap()
            XCTAssertTrue(field.waitForNonExistence(timeout: 10))

            let link = app.buttons["Library.collections"].firstMatch
            XCTAssertTrue(link.waitForExistence(timeout: 10))
            link.tap()
            let collection = app.staticTexts[name].firstMatch
            XCTAssertTrue(collection.waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["Empty Collection"].firstMatch.exists)
            collection.tap()
            XCTAssertTrue(app.staticTexts["Fixture Printed Book"].firstMatch.waitForExistence(timeout: 10))
            app.navigationBars.buttons["More"].firstMatch.tap()
            app.buttons["Add Titles"].firstMatch.tap()
            app.buttons["Audiobooks"].firstMatch.tap()
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 10))
            search.tap()
            search.typeText("Fixture Audiobook")
            let audio = app.buttons["Fixture Audiobook"].firstMatch
            XCTAssertTrue(audio.waitForExistence(timeout: 12))
            audio.tap()
            let add = app.navigationBars.buttons["Add"].firstMatch
            if !add.isHittable {
                let closeSearch = app.buttons["close"].firstMatch
                XCTAssertTrue(closeSearch.waitForExistence(timeout: 5))
                closeSearch.tap()
            }
            XCTAssertTrue(add.isEnabled)
            add.tap()
            XCTAssertTrue(app.staticTexts["Fixture Audiobook"].firstMatch.waitForExistence(timeout: 15))
            openShelf("Audiobooks", in: app)
            link.tap()
            XCTAssertTrue(collection.waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["Empty Collection"].firstMatch.exists)
            app.buttons["All"].firstMatch.tap()
            XCTAssertTrue(app.staticTexts["Empty Collection"].firstMatch.waitForExistence(timeout: 10))

            openShelf("Movies", in: app)
            link.tap()
            XCTAssertTrue(app.staticTexts["No Matching Collections"].waitForExistence(timeout: 10))
            XCTAssertFalse(collection.exists)
            openShelf("Collections", in: app)
            XCTAssertTrue(collection.waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Empty Collection"].firstMatch.exists)
        }

        func testFormatsBrowseTheSameMixedLibrarySeparately() {
            if UIDevice.current.userInterfaceIdiom == .pad {
                XCUIDevice.shared.orientation = .landscapeLeft
            }
            defer {
                if UIDevice.current.userInterfaceIdiom == .pad {
                    XCUIDevice.shared.orientation = .portrait
                }
            }
            continueAfterFailure = false
            let app = XCUIApplication()
            app.launchEnvironment["GUS_DEMO_URL"] = "http://127.0.0.1:5058"
            app.launchArguments = [
                "--gus-skip-session-restore", "--gus-disable-cloud-sync", "--gus-demo-server",
                "-dev.ericslutz.gus.contentRatingLimit", "off",
            ]
            app.launch()
            defer { app.terminate() }
            for (destination, title, other) in [
                ("Books", "Fixture Printed Book", "Fixture Audiobook"),
                ("Audiobooks", "Fixture Audiobook", "Fixture Printed Book"),
            ] {
                openShelf(destination, in: app)
                let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
                XCTAssertTrue(card.waitForExistence(timeout: 12))
                XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", other)).firstMatch.exists)
                XCTAssertTrue(card.label.contains("Fixture Author"))
                XCTAssertTrue(card.label.contains(destination == "Books" ? "2024" : "2025"))

                let stack = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Fixture Saga")).firstMatch
                XCTAssertTrue(stack.waitForExistence(timeout: 10))
                if destination == "Books" {
                    XCTAssertEqual(stack.value as? String, "Fixture Author · 2 books")
                    app.buttons["Library.displayMode"].tap()
                    XCTAssertEqual(stack.value as? String, "Fixture Author · 2 books")
                    XCTAssertTrue(card.label.contains("Fixture Author"))
                    XCTAssertTrue(card.label.contains("2024"))
                    XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "First Volume")).firstMatch.exists)
                }
                stack.tap()
                let member = destination == "Books" ? "First Volume" : "Spoken Volume"
                let memberButton = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", member)).firstMatch
                XCTAssertTrue(memberButton.waitForExistence(timeout: 10))
                XCTAssertTrue(memberButton.label.contains("Fixture Author"))
                memberButton.tap()
                XCTAssertTrue(app.staticTexts[member].firstMatch.waitForExistence(timeout: 10))
                XCTAssertEqual(app.staticTexts["Detail.heroOverview"].firstMatch.label, "A short synopsis.")
                XCTAssertFalse(app.buttons["Detail.fullSynopsis"].exists)
            }
        }
    }
#endif
