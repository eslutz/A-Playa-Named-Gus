#if os(iOS) && canImport(AppIntentsTesting)
    import AppIntentsTesting
    import XCTest

    @MainActor
    final class GusIntentContractUITests: XCTestCase {
        func testPrivateEntityQueriesAndDownloadsNavigation() async throws {
            let app = XCUIApplication()
            app.launchArguments = ["--gus-debug-preview-session", "--gus-disable-cloud-sync"]
            app.launch()
            defer { app.terminate() }
            XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 15))
            let definitions = IntentDefinitions(bundleIdentifier: "dev.ericslutz.gus")
            let foreign = "1." + ["media", "jellyfin", "other-server", "other-user", "one"].map { Data($0.utf8).base64EncodedString() }.joined(separator: ".")
            let library = definitions.entities["GusMediaEntity"]
            let items = try await library.entities(identifiers: [foreign, "malformed"])
            XCTAssertTrue(items.isEmpty)
            let suggestions = try await library.suggestedEntities()
            XCTAssertTrue(suggestions.isEmpty)

            try await definitions.intents["OpenDownloadsIntent"].makeIntent().run()
            XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 10))
        }
    }
#endif
