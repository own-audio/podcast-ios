import XCTest

/// The app at the largest accessibility text size: the screens a listener meets still work and
/// their controls are still there. Screenshots are attached for a look by eye.
final class LargeTextTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testScreensAtAccessibilityXXXL() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchChecked()
        XCTAssertTrue(app.buttons["welcome.feed"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["welcome.search"].exists && app.buttons["welcome.server"].exists, "every way in fits")
        shot(app, "large-00-welcome")
        app.terminate()

        app.launchArguments += ["-debugFeedURL", "https://feeds.podcastindex.org/pc20.xml"]
        app.launchChecked()
        let play = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'play.'")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 30))
        shot(app, "large-01-new-episodes")
        let episode = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'episode.'")).firstMatch
        episode.tap()
        XCTAssertTrue(app.buttons["episode.play"].waitForExistence(timeout: 10))
        shot(app, "large-02-episode")
        app.buttons["episode.play"].tap()
        let mini = app.buttons["miniPlayer"]
        XCTAssertTrue(mini.waitForExistence(timeout: 20))
        mini.tap()
        XCTAssertTrue(app.buttons["player.playPause"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["player.skipForward"].exists && app.buttons["player.skipBackward"].exists, "the controls fit")
        shot(app, "large-03-player")
        app.buttons["player.stop"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        let settings = app.buttons["home.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(app.buttons["settings.addServer"].waitForExistence(timeout: 10))
        shot(app, "large-04-settings")
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
