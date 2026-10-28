import XCTest

/// The public own.audio demo, added from the welcome screen. Ported from own.audio Music.
final class DemoTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// After the demo sign-in: the accent colour, the account's listening and the way to delete
    /// it. The dialog is cancelled; the demo refuses deletion anyway.
    func testSettingsOnTheDemo() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchChecked()
        let server = app.buttons["welcome.server"]
        XCTAssertTrue(server.waitForExistence(timeout: 15))
        server.tap()
        let demo = app.buttons["addServer.demo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 15))
        demo.tap()
        let settings = app.buttons["home.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 90), "New Episodes should open on the demo")
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'settings.server.'")).firstMatch
        for _ in 0..<3 where !row.exists {
            for label in ["Not Now", "Teď ne"] where app.buttons[label].exists { app.buttons[label].tap() }
            if settings.isHittable { settings.tap() }
            _ = row.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(row.exists, "Settings should list the demo")

        let green = app.buttons["settings.accent.green"]
        for _ in 0..<8 where !green.isHittable { app.swipeUp() }
        XCTAssertTrue(green.waitForExistence(timeout: 5), "Settings should offer accent colours")
        green.tap()
        XCTAssertTrue(green.isSelected, "the chosen colour should be marked")
        app.buttons["settings.accent.app"].tap()

        for _ in 0..<8 where !row.isHittable { app.swipeDown() }
        row.tap()

        let listening = app.buttons["serverDetail.listening"]
        for _ in 0..<6 where !listening.isHittable { app.swipeUp() }
        XCTAssertTrue(listening.waitForExistence(timeout: 10))
        listening.tap()
        XCTAssertTrue(app.staticTexts["Listened"].waitForExistence(timeout: 20), "the listening statistics should load")
        app.segmentedControls.buttons["Year"].tap()
        XCTAssertTrue(app.staticTexts["Listened"].waitForExistence(timeout: 20))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let delete = app.buttons["serverDetail.deleteAccount"]
        for _ in 0..<6 where !delete.isHittable { app.swipeDown() }
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "an own.audio account can be deleted from the app")
        delete.tap()
        XCTAssertTrue(app.staticTexts["Delete Your Account?"].waitForExistence(timeout: 5))
        // Never confirmed: only the dialog is under test.
        let cancel = app.buttons["Cancel"]
        // Without a Cancel button (a popover), a tap far from the dialog's buttons closes it.
        if cancel.exists { cancel.tap() } else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap() }
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "cancelling keeps the server")
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["Delete Your Account?"])
        wait(for: [gone], timeout: 5)
    }
}
