import XCTest

/// The ways into the app from outside it: a `feed://` link from a web page or another app opens
/// Add a Feed with the address filled in; the widget's and Live Activity's `ownpodcast://play/`
/// link reaches the player (here with an episode the app doesn't know, which it says). Needs
/// the network.
final class PlatformTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    func testFeedLinkOpensAddAFeed() {
        let app = launch()
        XCTAssertTrue(app.buttons["welcome.feed"].waitForExistence(timeout: 15))
        app.open(URL(string: "feed://feeds.podcastindex.org/pc20.xml")!)
        let field = app.textFields["addFeed.address"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Add a Feed opens")
        XCTAssertEqual(field.value as? String, "feed://feeds.podcastindex.org/pc20.xml", "with the address filled in")
        app.buttons["addFeed.follow"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'play.'")).firstMatch.waitForExistence(timeout: 30), "and it follows")
    }

    func testPlayLinkReachesTheApp() {
        let app = launch()
        XCTAssertTrue(app.buttons["welcome.feed"].waitForExistence(timeout: 15))
        app.open(URL(string: "ownpodcast://play/phone%2Fnobody%7Cnothing")!)
        XCTAssertTrue(app.staticTexts["That episode is not here any more."].waitForExistence(timeout: 10), "the link is handled")
    }
}
