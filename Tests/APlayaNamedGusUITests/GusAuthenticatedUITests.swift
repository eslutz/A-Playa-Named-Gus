import os
import XCTest
#if os(iOS)
    import CoreGraphics
    import ImageIO
    import UIKit
#endif

/// Requires Scripts/demo-server.sh start. Only the rights-cleared localhost fixture
/// is authenticated here; the token is retained in memory and never attached/logged.
@MainActor
final class GusAuthenticatedUITests: XCTestCase {
    private var fixture: [String: String] = [:]

    private func prepare() throws {
        finish()
        continueAfterFailure = false
        executionTimeAllowance = 180
        fixture = try loadFixture()
    }

    override nonisolated func tearDown() async throws {
        await MainActor.run {
            XCUIApplication().terminate()
            #if os(iOS)
                XCUIDevice.shared.orientation = .portrait
            #endif
        }
        try await super.tearDown()
    }

    private func finish() {
        XCUIApplication().terminate()
        #if os(iOS)
            XCUIDevice.shared.orientation = .portrait
        #endif
    }

    func testAudioCloseAndReopen() throws {
        try prepare()
        defer { finish() }
        let app = try launch("play/" + required("Audio"))
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 30))
        capture(app, "audio-open")
        #if os(iOS)
            rotateToLandscape(app)
            XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
            capture(app, "audio-landscape")
        #endif
        #if os(tvOS)
            XCUIRemote.shared.press(.menu)
        #else
            app.buttons["Done"].firstMatch.tap()
        #endif
        let reopen = app.buttons["NowPlaying.reopen"]
        XCTAssertTrue(reopen.waitForExistence(timeout: 10))
        capture(app, "audio-closed")
        #if os(tvOS)
            for _ in 0 ..< 40 {
                if reopen.hasFocus {
                    break
                }
                XCUIRemote.shared.press(.down)
            }
            XCTAssertTrue(reopen.hasFocus)
            XCUIRemote.shared.press(.select)
        #else
            reopen.tap()
        #endif
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 10))
        capture(app, "audio-reopened")
        #if os(tvOS)
            XCUIRemote.shared.press(.menu)
        #else
            app.buttons["Stop"].firstMatch.tap()
        #endif
    }

    func testLoadedDetailLayouts() throws {
        try prepare()
        defer { finish() }
        #if os(iOS)
            let details = [("Movie", "Play"), ("MusicAlbum", "Play"), ("Book", "Read")]
        #elseif os(tvOS)
            let details = [("Movie", "Play"), ("MusicAlbum", "Play")]
        #else
            let details = [("Movie", "Play"), ("MusicAlbum", "Play"), ("Book", "Share")]
        #endif
        for (type, action) in details {
            let app = try launch("item/" + required(type))
            XCTAssertTrue(app.buttons[action].firstMatch.waitForExistence(timeout: 30))
            capture(app, type.lowercased() + "-detail")
            #if os(iOS)
                let window = app.windows.firstMatch.frame
                let button = app.buttons[action].firstMatch
                if button.isHittable {
                    XCTAssertLessThanOrEqual(button.frame.maxX, window.maxX + 1)
                    XCTAssertGreaterThanOrEqual(button.frame.minX, window.minX - 1)
                }
                rotateToLandscape(app)
                reveal(button, in: app)
                XCTAssertTrue(button.isHittable)
                capture(app, type.lowercased() + "-landscape")
                XCUIDevice.shared.orientation = .portrait
            #endif
            app.terminate()
        }
    }

    #if os(tvOS)
        /// Exercise the native remote through the hero and the lower detail content.
        func testTVDetailFocusAndAboutLayout() throws {
            try prepare()
            defer { finish() }
            let app = try launch("item/" + required("SynopsisMovie"))
            let play = app.buttons["Play"].firstMatch
            XCTAssertTrue(play.waitForExistence(timeout: 30))
            let focused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in play.hasFocus }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [focused], timeout: 10), .completed)
            capture(app, "tv-detail-play-focused")

            let common = ["Detail.nextUp", "Detail.favorite", "Detail.watched", "Detail.playlist"].map { app.buttons[$0] }
            for button in common {
                XCTAssertTrue(button.exists)
                XCTAssertGreaterThan(button.frame.minY, play.frame.maxY)
                XCTAssertEqual(button.frame.midY, common[0].frame.midY, accuracy: 4)
            }
            XCUIRemote.shared.press(.down)
            for _ in 0 ..< 5 {
                if common[0].hasFocus {
                    break
                }
                XCUIRemote.shared.press(.left)
            }
            for (index, button) in common.enumerated() {
                let reached = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in button.hasFocus }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [reached], timeout: 5), .completed, button.identifier)
                if index == 1 || index == 2 {
                    let originalLabel = button.label
                    XCUIRemote.shared.press(.select)
                    let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in button.label != originalLabel && button.isEnabled }, object: nil)
                    XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed)
                    XCUIRemote.shared.press(.select)
                    let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in button.label == originalLabel && button.isEnabled }, object: nil)
                    XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 10), .completed)
                }
                if index == 3 {
                    XCUIRemote.shared.press(.select)
                    XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
                    XCUIRemote.shared.press(.menu)
                    let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in button.hasFocus }, object: nil)
                    XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed)
                }
                XCUIRemote.shared.press(.right)
            }
            let more = app.buttons["Detail.more"]
            let moreFocused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                more.hasFocus || more.descendants(matching: .any).allElementsBoundByIndex.contains(where: \.hasFocus)
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [moreFocused], timeout: 5), .completed, app.debugDescription)
            capture(app, "tv-detail-more-focused")
            XCUIRemote.shared.press(.select)
            // Native tvOS menu entries are exposed as Other elements inside focused cells.
            let restart = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Start from Beginning")).firstMatch
            XCTAssertTrue(restart.waitForExistence(timeout: 5), app.debugDescription)
            capture(app, "tv-detail-overflow")
            XCUIRemote.shared.press(.menu)
            XCUIRemote.shared.press(.down)
            let synopsis = app.buttons["Synopsis"]
            let synopsisFocused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in synopsis.hasFocus }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [synopsisFocused], timeout: 5), .completed, app.debugDescription)
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
            capture(app, "tv-full-synopsis")
            XCUIRemote.shared.press(.menu)

            let fullSynopsis = app.buttons["Detail.fullSynopsis"]
            for _ in 0 ..< 24 {
                if fullSynopsis.exists, fullSynopsis.hasFocus {
                    break
                }
                XCUIRemote.shared.press(.down)
            }
            // The first About card is a readable focus target to the left of Show More.
            if !fullSynopsis.hasFocus {
                XCUIRemote.shared.press(.right)
            }
            let aboutFocused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in fullSynopsis.hasFocus }, object: nil)
            let aboutResult = XCTWaiter.wait(for: [aboutFocused], timeout: 5)
            capture(app, "tv-about-focus-result")
            XCTAssertEqual(aboutResult, .completed, app.debugDescription)
            let window = app.windows.firstMatch.frame
            XCTAssertTrue(window.contains(fullSynopsis.frame))
            capture(app, "tv-about-focused")

            app.terminate()
            app.launchArguments = ["--gus-demo-server", "--gus-disable-cloud-sync"]
            app.launch()
            XCTAssertTrue(app.staticTexts["Next Up"].firstMatch.waitForExistence(timeout: 30))
            let nextUp = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "NextUp.card.")).firstMatch
            XCTAssertTrue(nextUp.waitForExistence(timeout: 10))
            let homeFocused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in nextUp.hasFocus }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [homeFocused], timeout: 10), .completed, app.debugDescription)
            capture(app, "tv-home-cards")
        }
    #endif

    #if os(iOS)
        func testRightToLeftLoadedDetails() throws {
            try prepare()
            defer { finish() }
            for (type, action) in [("Movie", "Play"), ("MusicAlbum", "Play"), ("Book", "Read")] {
                let app = XCUIApplication()
                app.launchArguments = try [
                    "--gus-demo-server",
                    "--gus-route",
                    "item/" + required(type),
                    "-AppleLanguages",
                    "(ar)",
                    "-AppleLocale",
                    "ar_SA",
                    "-AppleTextDirection",
                    "YES",
                    "-NSForceRightToLeftWritingDirection",
                    "YES",
                ]
                app.launch()
                let button = app.buttons[action].firstMatch
                XCTAssertTrue(button.waitForExistence(timeout: 30))
                reveal(button, in: app)
                XCTAssertTrue(button.isHittable)
                XCTAssertGreaterThan(app.buttons["ContentLink.detailDone"].frame.midX, app.windows.firstMatch.frame.midX)
                capture(app, type.lowercased() + "-rtl")
                rotateToLandscape(app)
                reveal(button, in: app)
                XCTAssertTrue(button.isHittable)
                capture(app, type.lowercased() + "-rtl-landscape")
                app.terminate()
                XCUIDevice.shared.orientation = .portrait
            }
        }

        func testBookReaderDismissal() throws {
            try prepare()
            defer { finish() }
            let app = try launch("item/" + required("Book"))
            let read = app.buttons["Read"].firstMatch
            XCTAssertTrue(read.waitForExistence(timeout: 30))
            for _ in 0 ..< 8 {
                if read.isHittable {
                    break
                }
                app.swipeUp()
            }
            read.tap()
            XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 30))
            // Readium nests WebKit accessibility containers and can still be
            // paginating after the web view first appears on a busy simulator.
            XCTAssertTrue(app.webViews.descendants(matching: .staticText).firstMatch.waitForExistence(timeout: 75))
            XCTAssertFalse(read.isHittable)
            capture(app, "book-reader")
            rotateToLandscape(app)
            XCTAssertTrue(app.buttons["BookReader.done"].waitForExistence(timeout: 5))
            capture(app, "book-reader-landscape")
            app.buttons["BookReader.done"].tap()
            XCTAssertFalse(app.webViews.firstMatch.exists)
            reveal(app.buttons["Read"].firstMatch, in: app)
            capture(app, "book-reader-dismissed")
            XCTAssertTrue(app.buttons["Read"].firstMatch.isHittable)
        }

        func testBookReaderNestedChapters() throws {
            try prepare()
            executionTimeAllowance = 300
            defer { finish() }
            // The rights-cleared Dracula fixture groups its chapters under the
            // book title, so a flat top-level menu cannot reach chapter I.
            let app = try launch("item/" + required("NestedBook"))
            let read = app.buttons["Read"].firstMatch
            XCTAssertTrue(read.waitForExistence(timeout: 30))
            reveal(read, in: app)
            read.tap()
            let bookText = app.webViews.descendants(matching: .staticText)
            XCTAssertTrue(bookText.firstMatch.waitForExistence(timeout: 75))
            app.buttons["Chapters"].tap()
            XCTAssertTrue(app.buttons["BookChapters.done"].waitForExistence(timeout: 5))
            capture(app, "book-chapters-top-level")
            let menuTree = XCTAttachment(string: app.debugDescription)
            menuTree.name = "book-chapters-tree"
            menuTree.lifetime = .keepAlways
            add(menuTree)
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            let group = app.buttons["BookChapters.group.Dracula"].firstMatch
            reveal(group, in: app)
            group.tap()
            let chapter = app.buttons["I"]
            XCTAssertTrue(chapter.waitForExistence(timeout: 5))
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            capture(app, "book-nested-chapters")
            chapter.tap()
            let chapterText = bookText.matching(NSPredicate(format: "label CONTAINS[c] 'Harker'")).firstMatch
            XCTAssertTrue(chapterText.waitForExistence(timeout: 30))
            let readerDone = app.buttons["BookReader.done"].firstMatch
            let chapterClosed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                !app.buttons["BookChapters.done"].firstMatch.isHittable && readerDone.isHittable
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [chapterClosed], timeout: 30), .completed)
            capture(app, "book-chapter-one")
            rotateToLandscape(app)
            XCTAssertTrue(chapterText.waitForExistence(timeout: 15))
            XCTAssertTrue(app.buttons["BookReader.done"].isHittable)
            capture(app, "book-chapter-landscape")
            // Use the actual landscape window for reader-edge input. App-level
            // coordinates and paginated WebKit text bounds can be misleading.
            let paragraph = bookText.matching(NSPredicate(format: "label CONTAINS[c] 'Bistritz'")).firstMatch
            let heading = bookText.matching(NSPredicate(format: "label == 'I'")).firstMatch
            let window = app.windows.firstMatch
            let bounds = XCTAttachment(string: "App: \(app.frame)\nWindow: \(window.frame)\nHeading: \(heading.frame)")
            bounds.name = "book-reader-input-bounds"
            bounds.lifetime = .keepAlways
            add(bounds)
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.65)).tap()
            capture(app, "book-page-forward-immediate")
            Thread.sleep(forTimeInterval: 2)
            XCTAssertTrue(paragraph.waitForExistence(timeout: 15))
            // Paginated WebKit text can span columns and have no activation
            // point. Its prose is verified by the saved screen, not hit-testing.
            capture(app, "book-prose-landscape")
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.65)).tap()
            capture(app, "book-page-back-immediate")
            // WebKit exposes the whole chapter DOM while its native spread
            // transition completes. Give the backwards page a bounded settle
            // before closing; saved screens establish which page is visible.
            Thread.sleep(forTimeInterval: 5)
            capture(app, "book-page-back-landscape")
            let doneBounds = XCTAttachment(string: "Reader Done: \(readerDone.frame)\nWindow: \(window.frame)")
            doneBounds.name = "book-reader-done-bounds"
            doneBounds.lifetime = .keepAlways
            add(doneBounds)
            XCTAssertTrue(readerDone.isHittable)
            readerDone.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                read.isHittable && !readerDone.isHittable
            }, object: nil)
            let dismissalResult = XCTWaiter.wait(for: [dismissed], timeout: 30)
            capture(app, "book-reader-close-result")
            XCTAssertEqual(dismissalResult, .completed)
            reveal(read, in: app)
            XCTAssertTrue(read.isHittable)
            capture(app, "book-chapter-dismissed")
        }

        func testConnectCurrentScreenAccessibility() throws {
            try prepare()
            defer { finish() }
            for size in [nil, UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue] as [String?] {
                let app = XCUIApplication()
                app.launchArguments = ["--gus-skip-session-restore"]
                if let size {
                    app.launchArguments += ["-UIPreferredContentSizeCategoryName", size]
                }
                app.launch()
                let field = app.textFields["ConnectServerView.serverAddress"]
                XCTAssertTrue(field.waitForExistence(timeout: 10))
                field.tap()
                field.typeText("http://127.0.0.1:8096")
                XCTAssertEqual(field.value as? String, "http://127.0.0.1:8096")
                if size != nil {
                    XCTAssertGreaterThanOrEqual(app.staticTexts["Connect to Jellyfin"].frame.height, 40)
                }
                capture(app, size == nil ? "connect-input" : "connect-input-ax5")
                try app.performAccessibilityAudit(for: [.hitRegion, .textClipped]) { issue in
                    print("Accessibility issue type: \(issue.auditType); element: \(issue.element?.debugDescription ?? "unidentified"); URL field frame: \(field.frame)")
                    // Native single-line URL entry scrolls horizontally. The audit warns
                    // about clipping even though the complete typed value is preserved.
                    // This exception is limited to this exact, hittable field and type.
                    // Its native Form row supplies the audited >=44 pt touch region;
                    // the intrinsic text rectangle is smaller than the row.
                    if issue.auditType == .textClipped,
                       issue.element?.identifier == "ConnectServerView.serverAddress",
                       field.isHittable,
                       app.cells.containing(.textField, identifier: "ConnectServerView.serverAddress").firstMatch.frame.height >= 44
                    {
                        print("Accepted URL-field textClipped: verified horizontal entry and complete value")
                        return true
                    }
                    return false
                }
                app.terminate()
            }
        }

        func testFullSynopsisHeading() throws {
            try prepare()
            defer { finish() }
            let app = try launch("item/" + required("SynopsisMovie"))
            XCTAssertTrue(app.buttons["Play"].firstMatch.waitForExistence(timeout: 30))
            let more = app.buttons["Detail.fullSynopsis"].firstMatch
            let about = app.scrollViews["Detail.aboutCards"]
            for _ in 0 ..< 10 {
                if about.isHittable {
                    break
                }
                app.swipeUp()
            }
            for _ in 0 ..< 3 {
                if more.isHittable {
                    break
                }
                about.swipeLeft()
            }
            XCTAssertTrue(more.isHittable)
            more.tap()
            let heading = app.staticTexts["Synopsis.heading"]
            XCTAssertTrue(heading.waitForExistence(timeout: 10))
            XCTAssertEqual(heading.label, try required("SynopsisMovieTitle"))
            capture(app, "full-synopsis")
            app.buttons["Synopsis.done"].tap()
            XCTAssertFalse(heading.exists)
        }

        func testLargestTextAuthenticatedDetails() throws {
            try prepare()
            defer { finish() }
            for (type, action) in [("Movie", "Play"), ("MusicAlbum", "Play"), ("Book", "Read")] {
                let app = XCUIApplication()
                app.launchArguments = try [
                    "--gus-demo-server",
                    "--gus-route",
                    "item/" + required(type),
                    "-UIPreferredContentSizeCategoryName",
                    UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
                ]
                app.launch()
                let button = app.buttons[action].firstMatch
                XCTAssertTrue(button.waitForExistence(timeout: 30))
                reveal(button, in: app)
                XCTAssertTrue(button.isHittable)
                XCTAssertGreaterThanOrEqual(button.frame.height, 44)
                capture(app, type.lowercased() + "-ax5")
                app.terminate()
            }
        }

        func testDetailCurrentScreenAccessibility() throws {
            try prepare()
            defer { finish() }
            let app = try launch("item/" + required("SynopsisMovie"))
            XCTAssertTrue(app.buttons["Play"].firstMatch.waitForExistence(timeout: 30))
            capture(app, "movie-audit")
            if UIDevice.current.userInterfaceIdiom == .pad {
                // Xcode 27's form-sheet contrast scanner samples clipped/offscreen
                // descendants against the underlying Home window (RV-015). Keep
                // native geometry/description auditing and independent rendered
                // checks; record native iPad contrast as blocked, never as passed.
                try app.performAccessibilityAudit(for: [.hitRegion, .sufficientElementDescription])
                for element in [app.buttons["ContentLink.detailDone"], app.buttons["Play"].firstMatch] {
                    XCTAssertTrue(element.isEnabled)
                    XCTAssertTrue(element.isHittable)
                    XCTAssertGreaterThanOrEqual(try renderedLabelContrast(element), 4.5)
                }
                print("Native iPad contrast blocked by documented offscreen form-sheet sampling; visible primary-control pixel checks passed")
                return
            }
            var renderedChecks: [String: XCUIElement] = [:]
            try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .sufficientElementDescription]) { issue in
                print("Strict movie audit: \(issue.auditType); element: \(issue.element?.debugDescription ?? "unlocated")")
                guard issue.auditType == .contrast else { return false }
                // Classify only documented native contrast false positives. Pixel checks
                // run after the native audit so revealing a clipped element cannot move
                // the viewport underneath the auditor's remaining cached samples.
                let done = app.buttons["ContentLink.detailDone"]
                if issue.element?.identifier == "ContentLink.detailDone",
                   done.label == "Done", done.isEnabled
                {
                    renderedChecks["ContentLink.detailDone"] = done
                    return true
                }
                let play = app.buttons["Play"].firstMatch
                if issue.element?.identifier == "Detail.play",
                   issue.element?.label == "Play", play.isEnabled
                {
                    renderedChecks["Detail.play"] = play
                    return true
                }
                return false
            }
            for key in renderedChecks.keys.sorted() {
                let element = try XCTUnwrap(renderedChecks[key])
                for _ in 0 ..< 10 {
                    if element.isHittable {
                        break
                    }
                    let contentTop = app.buttons["ContentLink.detailDone"].frame.maxY
                    if (element.exists && element.frame.maxY < contentTop) || (!element.exists && key == "Detail.play") {
                        app.swipeDown()
                    } else {
                        app.swipeUp()
                    }
                }
                XCTAssertTrue(element.isHittable, "Unreachable contrast-disposition element: " + key)
                XCTAssertGreaterThanOrEqual(try renderedLabelContrast(element), 4.5, "Rendered contrast: " + key)
                print("Accepted measured native contrast disposition: \(key)")
            }
        }
    #endif

    #if os(iOS)
        /// Sample the central text portion of these two known native labels. Frequent
        /// solid colors exclude isolated antialias pixels; this is a local contrast
        /// guard, not an all-screen image audit or permission to ignore other issues.
        private func renderedLabelContrast(_ element: XCUIElement) throws -> Double {
            let screenshot = element.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "contrast-guard-" + (element.identifier.isEmpty ? element.label : element.identifier)
            attachment.lifetime = .keepAlways
            add(attachment)
            let source = try XCTUnwrap(CGImageSourceCreateWithData(screenshot.pngRepresentation as CFData, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let width = image.width, height = image.height
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            try pixels.withUnsafeMutableBytes { storage in
                let context = try XCTUnwrap(CGContext(
                    data: storage.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
                ))
                context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            }
            var histogram: [UInt32: Int] = [:]
            for y in Int(Double(height) * 0.2) ..< Int(Double(height) * 0.8) {
                for x in Int(Double(width) * 0.48) ..< Int(Double(width) * 0.64) {
                    let index = (y * width + x) * 4
                    let rgb = UInt32(pixels[index]) << 16 | UInt32(pixels[index + 1]) << 8 | UInt32(pixels[index + 2])
                    histogram[rgb, default: 0] += 1
                }
            }
            let dominant = try XCTUnwrap(histogram.max { $0.value < $1.value }?.key)
            func luminance(_ rgb: UInt32) -> Double {
                let components = [Double((rgb >> 16) & 255), Double((rgb >> 8) & 255), Double(rgb & 255)].map { $0 / 255 }
                    .map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
                return components[0] * 0.2126 + components[1] * 0.7152 + components[2] * 0.0722
            }
            let baseline = luminance(dominant)
            let minimumCount = max(2, histogram.values.reduce(0, +) / 1000)
            let ratio = histogram.filter { $0.value >= minimumCount }.keys.map {
                let other = luminance($0)
                return (max(baseline, other) + 0.05) / (min(baseline, other) + 0.05)
            }.max() ?? 1
            print("Rendered native label contrast: \(element.identifier), ratio \(ratio)")
            return ratio
        }

        private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
            for _ in 0 ..< 10 {
                let window = app.windows.firstMatch.frame
                if element.isHittable, element.frame.height >= 44,
                   element.frame.minY >= window.minY + 44,
                   element.frame.maxY <= window.maxY - 24
                {
                    return
                }
                app.swipeUp()
            }
        }

        private func rotateToLandscape(_ app: XCUIApplication) {
            XCUIDevice.shared.orientation = .landscapeLeft
            let deadline = Date().addingTimeInterval(10)
            while app.windows.firstMatch.frame.width <= app.windows.firstMatch.frame.height, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.2)
            }
            XCTAssertGreaterThan(app.windows.firstMatch.frame.width, app.windows.firstMatch.frame.height)
        }
    #endif

    private func launch(_ route: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--gus-demo-server", "--gus-disable-cloud-sync", "--gus-route", route]
        app.launch()
        return app
    }

    private func required(_ type: String) throws -> String {
        try XCTUnwrap(fixture[type], "Required demo media missing: " + type)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func loadFixture() throws -> [String: String] {
        func request(_ path: String, body: [String: String]? = nil, token: String? = nil) throws -> [String: Any] {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:8096" + path)!)
            request.timeoutInterval = 10
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("MediaBrowser Client=\"GusValidation\", Device=\"XCTest\", DeviceId=\"gus-validation\", Version=\"1.0.0\"", forHTTPHeaderField: "Authorization")
            if let token {
                request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
            }
            if let body {
                request.httpMethod = "POST"
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            }
            // The ephemeral fixture client never follows a redirect to another host.
            let semaphore = DispatchSemaphore(value: 0)
            let box = OSAllocatedUnfairLock(initialState: FixtureResponse())
            let client = FixtureHTTPClient()
            let session = URLSession(configuration: .ephemeral, delegate: client, delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            session.dataTask(with: request) { data, response, error in
                box.withLock { state in
                    state.data = data
                    state.succeeded = error == nil && (response as? HTTPURLResponse)?.statusCode == 200 && response?.url?.host == "127.0.0.1"
                }
                semaphore.signal()
            }.resume()
            guard semaphore.wait(timeout: .now() + 15) == .success else { throw FixtureError.unavailable }
            let response = box.withLock { $0 }
            guard response.succeeded, let data = response.data,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { throw FixtureError.unavailable }
            return object
        }
        let auth = try request("/Users/AuthenticateByName", body: ["Username": "gus", "Pw": "playa-demo"])
        guard let user = auth["User"] as? [String: Any], let userID = user["Id"] as? String,
              let token = auth["AccessToken"] as? String
        else { throw FixtureError.unavailable }
        let response = try request("/Users/\(userID)/Items?Recursive=true&Limit=1000&Fields=Overview", token: token)
        let items = response["Items"] as? [[String: Any]] ?? []
        var result: [String: String] = [:]
        for type in ["Audio", "Movie", "MusicAlbum", "Book"] {
            guard let item = items.first(where: { $0["Type"] as? String == type }), let id = item["Id"] as? String else {
                throw FixtureError.missingMedia
            }
            result[type] = id
            if type == "Movie" {
                result["MovieTitle"] = item["Name"] as? String
            }
        }
        if let book = items.first(where: { $0["Type"] as? String == "Book" && $0["Name"] as? String == "Dracula" }) {
            result["NestedBook"] = book["Id"] as? String
        }
        guard let synopsisMovie = items.filter({
            $0["Type"] as? String == "Movie" && !($0["Overview"] as? String ?? "").isEmpty
        }).max(by: { ($0["Name"] as? String ?? "").count < ($1["Name"] as? String ?? "").count }),
            let id = synopsisMovie["Id"] as? String, let title = synopsisMovie["Name"] as? String
        else { throw FixtureError.missingMedia }
        result["SynopsisMovie"] = id
        result["SynopsisMovieTitle"] = title
        return result
    }

    private enum FixtureError: Error { case unavailable, missingMedia }
}

private struct FixtureResponse: Sendable {
    var data: Data?
    var succeeded = false
}

private final class FixtureHTTPClient: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
