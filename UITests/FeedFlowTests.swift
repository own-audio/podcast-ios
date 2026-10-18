import XCTest

/// The no-server path end to end against a real feed: follow it by address from the first
/// screen, find its newest episode in New Episodes, play it, seek, change the speed, set the
/// sleep timer, stop. Then Offline Mode beside Settings. Needs the network, nothing else.
final class FeedFlowTests: XCTestCase {
    /// Podcasting 2.0's own show: chapters, transcripts, and a feed that is always up.
    private let feed = "https://feeds.podcastindex.org/pc20.xml"

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extra
        app.launch()
        return app
    }

    func testFollowByAddressAndPlay() {
        let app = launch()
        let addFeed = app.buttons["welcome.feed"]
        XCTAssertTrue(addFeed.waitForExistence(timeout: 15))
        addFeed.tap()
        let field = app.textFields["addFeed.address"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(feed)
        app.buttons["addFeed.follow"].tap()

        // The show's newest episode is new to the listener.
        let play = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'play.'")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 30), "New Episodes holds the newest episode")
        play.tap()

        let mini = app.buttons["miniPlayer"]
        XCTAssertTrue(mini.waitForExistence(timeout: 15))
        mini.tap()
        let elapsed = app.staticTexts["player.elapsed"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 10))
        // Playing: the clock moves.
        let started = Date()
        while elapsed.label == "0:00", Date().timeIntervalSince(started) < 30 { RunLoop.current.run(until: Date().addingTimeInterval(0.5)) }
        XCTAssertNotEqual(elapsed.label, "0:00", "the episode plays")

        let before = seconds(elapsed.label)
        app.buttons["player.skipForward"].tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertGreaterThanOrEqual(seconds(elapsed.label), before + 25, "skip forward moves 30 s")

        app.buttons["player.speed"].tap()
        // The books app's presets, so both spoken-word apps offer the same steps.
        for preset in ["0.75", "1.0", "1.25", "1.5", "1.75", "2.0", "2.5", "3.0"] {
            XCTAssertTrue(app.buttons["speed.preset.\(preset)"].waitForExistence(timeout: 3), "preset \(preset)")
        }
        app.buttons["speed.preset.1.5"].tap()
        XCTAssertEqual(app.staticTexts["speed.value"].label, "1.50×")
        app.buttons["Done"].firstMatch.tap()

        app.buttons["player.sleep"].tap()
        let fifteen = app.buttons["sleep.15"]
        XCTAssertTrue(fifteen.waitForExistence(timeout: 5))
        fifteen.tap()
        XCTAssertTrue(app.staticTexts["player.sleepBadge"].waitForExistence(timeout: 5) || app.otherElements["player.sleepBadge"].exists, "the sleep timer shows on the picture")

        app.buttons["player.stop"].tap()
        XCTAssertFalse(app.buttons["miniPlayer"].waitForExistence(timeout: 3), "stop lets go of the episode")
    }

    func testOfflineModeBesideSettings() {
        let app = launch(["-debugFeedURL", feed])
        let toggle = app.buttons["home.offlineMode"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["home.settings"].exists, "Settings sits beside it")
        toggle.tap()
        XCTAssertTrue(app.staticTexts["Offline Mode is on"].waitForExistence(timeout: 5))
        toggle.tap()
        XCTAssertFalse(app.staticTexts["Offline Mode is on"].waitForExistence(timeout: 3))
    }

    private func seconds(_ clock: String) -> Int {
        clock.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) }
    }
}
