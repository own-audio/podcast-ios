import XCTest

/// Up Next, searching your own shows, sorting and filtering, against a real feed. Needs the
/// network.
final class LibraryFlowTests: XCTestCase {
    /// Podcasting 2.0's own show, as in FeedFlowTests.
    private let feed = "https://feeds.podcastindex.org/pc20.xml"

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-debugFeedURL", feed]
        app.launchChecked()
        return app
    }

    private func tab(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", label))
        _ = matches.firstMatch.waitForExistence(timeout: 10)
        return matches.allElementsBoundByIndex.first { $0.isHittable } ?? matches.firstMatch
    }

    private func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end, !condition() { RunLoop.current.run(until: Date().addingTimeInterval(0.5)) }
        return condition()
    }

    private func openShow(_ app: XCUIApplication) {
        tab(app, "Shows").tap()
        let show = app.descendants(matching: .any)["show.Podcasting 2.0"]
        XCTAssertTrue(show.waitForExistence(timeout: 20))
        show.tap()
        XCTAssertTrue(app.descendants(matching: .any)["show.filter"].firstMatch.waitForExistence(timeout: 20))
    }

    /// The `index`th episode of the open show: its page.
    private func openEpisode(_ app: XCUIApplication, _ index: Int) -> String {
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'episode.' AND NOT identifier IN %@", ["episode.title", "episode.play"]))
        XCTAssertTrue(rows.element(boundBy: index).waitForExistence(timeout: 10))
        let id = rows.element(boundBy: index).identifier
        rows.element(boundBy: index).tap()
        return String(id.dropFirst("episode.".count))
    }

    /// On the short fixture feed (`LOCAL_FEED_URL`, served by scripts/test-servers.sh): queue two
    /// episodes, see Play Next go first, remove one, and hear the other play when the first ends.
    func testUpNextQueuesReordersAndPlaysOn() throws {
        guard let local = ProcessInfo.processInfo.environment["LOCAL_FEED_URL"] else { throw XCTSkip("LOCAL_FEED_URL is not set") }
        let app = XCUIApplication()
        // A copy still running from an earlier test (playing in the background) would be reused
        // without these arguments.
        if app.state != .notRunning { app.terminate() }
        app.launchArguments = ["-uiTestReset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-debugFeedURL", local]
        app.launchChecked()
        XCTAssertTrue(app.buttons["home.settings"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons["home.settings"].label, "Settings", "launched fresh, in English")
        tab(app, "Shows").tap()
        let show = app.descendants(matching: .any)["show.own.audio Test Fixtures"]
        XCTAssertTrue(show.waitForExistence(timeout: 20))
        show.tap()
        XCTAssertTrue(app.buttons["episode.fixture-3"].waitForExistence(timeout: 10))
        app.buttons["episode.fixture-2"].tap()
        app.buttons["episode.playLater"].tap()
        XCTAssertTrue(app.buttons["episode.removeFromUpNext"].waitForExistence(timeout: 5), "queued")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["episode.fixture-1"].tap()
        app.buttons["episode.playNext"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["play.fixture-3"].tap()
        XCTAssertTrue(app.buttons["miniPlayer"].waitForExistence(timeout: 15))
        app.buttons["miniPlayer"].tap()
        app.buttons["player.upNext"].tap()
        let first = app.buttons["upNext.fixture-1"], second = app.buttons["upNext.fixture-2"]
        XCTAssertTrue(first.waitForExistence(timeout: 5) && second.exists, "both in Up Next")
        XCTAssertLessThan(first.frame.minY, second.frame.minY, "Play Next goes first")
        first.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(first.waitForNonExistence(timeout: 5), "swiped away")
        app.buttons["Done"].firstMatch.tap()

        // Episode 3 is twelve seconds long: when it ends, episode 2 plays on.
        let title = app.staticTexts["player.title"]
        XCTAssertTrue(waitUntil(40) { title.exists && title.label == "Fixture Episode 2" }, "the next in Up Next plays when the episode ends: \(title.label)")
        app.buttons["player.upNext"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["upNext.empty"].waitForExistence(timeout: 5), "and leaves the queue")
        app.buttons["Done"].firstMatch.tap()
        app.buttons["player.stop"].tap()
    }

    func testSearchFindsYourOwnShowsOffline() {
        let app = launch()
        XCTAssertTrue(app.buttons["home.offlineMode"].firstMatch.waitForExistence(timeout: 30))
        app.buttons["home.offlineMode"].firstMatch.tap()
        tab(app, "Discover").tap()
        let field = app.searchFields.firstMatch
        for _ in 0..<3 where !field.exists { tab(app, "Discover").tap(); _ = field.waitForExistence(timeout: 3) }
        field.tap()
        field.typeText("podcasting")
        XCTAssertTrue(app.descendants(matching: .any)["search.mine.Podcasting 2.0"].waitForExistence(timeout: 10), "your own show, with no network")
        XCTAssertFalse(app.staticTexts["Search Isn't Available"].exists, "no dead end while something matches")
    }

    func testSortShowsAndFilterEpisodes() {
        let app = launch()
        tab(app, "Shows").tap()
        let more = app.buttons.matching(NSPredicate(format: "label IN %@", ["More", "Sort"])).firstMatch
        XCTAssertTrue(app.descendants(matching: .any)["show.Podcasting 2.0"].waitForExistence(timeout: 20))
        // In the toolbar's overflow menu, the choices one level down under Sort.
        more.tap()
        let sortMenu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sort'")).firstMatch
        if sortMenu.waitForExistence(timeout: 3) { sortMenu.tap() }
        let choice = app.buttons["New Episodes First"].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5), "the sort choices")
        XCTAssertTrue(app.buttons["Recently Followed"].firstMatch.exists)
        choice.tap()

        openShow(app)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'play.'"))
        XCTAssertGreaterThan(rows.count, 1)
        app.descendants(matching: .any)["show.filter"].firstMatch.buttons["Downloaded"].tap()
        XCTAssertTrue(waitUntil(5) { rows.count == 0 }, "nothing downloaded yet")
        app.descendants(matching: .any)["show.filter"].firstMatch.buttons["Unplayed"].tap()
        XCTAssertTrue(waitUntil(5) { rows.count > 1 }, "every episode is unplayed")
    }
}
