import XCTest
@MainActor final class TVInspect: XCTestCase {
    let app = XCUIApplication(bundleIdentifier:"dev.ericslutz.gus")
    let remote = XCUIRemote.shared
    func capture(_ name:String) {
        Thread.sleep(forTimeInterval:1)
        let shot=XCUIScreen.main.screenshot()
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("GusTVRuntimeScreens")
        try! FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let destination=directory.appendingPathComponent(name+".png")
        try! shot.pngRepresentation.write(to:destination)
        print("GUS_SCREEN_PATH " + destination.path)
        let a=XCTAttachment(screenshot:shot); a.name=name; a.lifetime = .keepAlways; add(a)
        let t=XCTAttachment(string:app.debugDescription);t.name=name+"-tree";t.lifetime = .keepAlways;add(t)
        print("GUS_TREE_"+name+" "+Data(app.debugDescription.utf8).base64EncodedString())
    }
    func launch(_ user:String="gus") {
        app.launchArguments=["--gus-demo-server","--gus-skip-session-restore","--gus-disable-cloud-sync", "--gus-route", "home"]
        app.launchEnvironment=["GUS_DEMO_USERNAME":user,"GUS_DEMO_PASSWORD":"playa-demo"]
        app.launch()
        XCTAssertTrue(app.buttons["Account"].waitForExistence(timeout:30))
        Thread.sleep(forTimeInterval:1)

    }
    func hasFocus(_ element: XCUIElement) -> Bool {
        element.hasFocus || element.descendants(matching:.any).allElementsBoundByIndex.contains { $0.hasFocus }
    }
    func press(_ button:XCUIRemote.Button) { remote.press(button); Thread.sleep(forTimeInterval:1) }
    func focus(_ element:XCUIElement, direction:XCUIRemote.Button, limit:Int=8) {
        for _ in 0..<limit {
            if hasFocus(element) { return }
            press(direction);Thread.sleep(forTimeInterval:0.3)
        }
        XCTAssertTrue(hasFocus(element))
    }
    func testAccountAndRemote() throws {
        launch("bob"); app.terminate(); launch()
        let movie=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","Edison Kinetoscopic")).firstMatch
        XCTAssertTrue(movie.waitForExistence(timeout:30))
        capture("home")
        focus(app.buttons["Account"],direction:.up,limit:12)
        press(.select);capture("accounts")
        focus(app.cells.containing(.other,identifier:"bob").firstMatch,direction:.down)
        press(.select)
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout:10))
        XCTAssertEqual(app.buttons["Account"].value as? String,"gus")
        capture("reauthentication")
        press(.menu)
        XCTAssertFalse(app.buttons["Cancel"].exists)
        XCTAssertEqual(app.buttons["Account"].value as? String,"gus")
        capture("reauthCancelled")
        focus(app.buttons["Account"],direction:.up,limit:12);press(.select)
        focus(app.cells.containing(.other,identifier:"bob").firstMatch,direction:.down)
        press(.select);XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout:10))
        press(.menu);XCTAssertFalse(app.buttons["Cancel"].exists)
        XCTAssertEqual(app.buttons["Account"].value as? String,"gus")

    }
    func testDetailPlaybackAndSidebar() throws {
        launch()
        let movie=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","Edison Kinetoscopic")).firstMatch
        XCTAssertTrue(movie.waitForExistence(timeout:30));focus(movie,direction:.down,limit:12)
        let second=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","President McKinley")).firstMatch
        XCTAssertTrue(second.waitForExistence(timeout:30))
        press(.right);XCTAssertTrue(second.hasFocus);press(.select)
        XCTAssertTrue(app.buttons["Detail.play"].waitForExistence(timeout:15))
        press(.menu);XCTAssertTrue(second.hasFocus)
        press(.select);XCTAssertTrue(app.buttons["Detail.play"].waitForExistence(timeout:15));capture("detail")
        press(.right);XCTAssertTrue(hasFocus(app.buttons["Detail.more"]))
        press(.select);capture("more");press(.menu)
        XCTAssertTrue(hasFocus(app.buttons["Detail.more"]))
        focus(app.buttons["Synopsis"],direction:.down,limit:3)
        press(.select);capture("synopsis");press(.menu)
        XCTAssertTrue(hasFocus(app.buttons["Synopsis"]))
        focus(app.buttons["Detail.play"],direction:.up,limit:3)
        press(.select);Thread.sleep(forTimeInterval:3);capture("player")
        XCTAssertTrue(app.otherElements["AXElapsedTime"].exists)
        press(.playPause);capture("pausedPlayer")
        let pausedTime=app.otherElements["AXElapsedTime"].label
        Thread.sleep(forTimeInterval:2)
        XCTAssertEqual(app.otherElements["AXElapsedTime"].label,pausedTime)
        for _ in 0..<3 {
            if app.buttons["Detail.play"].hasFocus { break }
            press(.menu)
        }
        XCTAssertTrue(app.buttons["Detail.play"].hasFocus);capture("playerBack")
        press(.menu)
        let remaining=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","President McKinley"))
        if remaining.count > 0 {
            XCTAssertTrue(remaining.allElementsBoundByIndex.contains { $0.hasFocus })
        } else {
            let neighbor=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","May Irwin Kiss")).firstMatch
            XCTAssertTrue(neighbor.waitForExistence(timeout:10))
            XCTAssertTrue(neighbor.hasFocus)
        }
        capture("restored")
        for _ in 0..<4 {
            if app.buttons["house"].isEnabled { break }
            press(.left)
        }
        capture("sidebar")
        for _ in 0..<3 {press(.down)};press(.select);Thread.sleep(forTimeInterval:2)
        capture("moviesLibrary")
    }
    func testAccessibilityAudit() throws {
        launch()
        let movie=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","Edison Kinetoscopic")).firstMatch
        XCTAssertTrue(movie.waitForExistence(timeout:30));focus(movie,direction:.down,limit:12)
        try app.performAccessibilityAudit(for:[.contrast,.elementDetection,.sufficientElementDescription]) { issue in
            print("GUS_A11Y_ISSUE " + issue.compactDescription + " | " + issue.detailedDescription + " | " + (issue.element?.label ?? "unknown"))
            return false
        }
        remote.press(.right);remote.press(.select)
        XCTAssertTrue(app.buttons["Detail.play"].waitForExistence(timeout:15))
        try app.performAccessibilityAudit(for:[.contrast,.elementDetection,.sufficientElementDescription]) { issue in
            print("GUS_A11Y_ISSUE " + issue.compactDescription + " | " + issue.detailedDescription + " | " + (issue.element?.label ?? "unknown"))
            return false
        }
    }

}
