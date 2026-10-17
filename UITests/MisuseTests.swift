import XCTest

/// Things a listener isn't meant to do, done anyway: bad feed addresses, wrong sign-ins,
/// buttons hammered, stop pressed mid-load, tabs and searches thrown at the app, the app sent
/// away and killed mid-episode. Nothing here checks a feature; each checks the app is still
/// usable after. Needs the network and nothing else.
final class MisuseTests: XCTestCase {
    private let feed = "https://feeds.podcastindex.org/pc20.xml"

    override func setUp() {
        continueAfterFailure = false
    }

    /// Addresses that are no feed say so and leave the form usable; the right one still works,
    /// typed with spaces around it and as a feed:// link.
    func testBadFeedAddresses() {
        let app = launch()
        XCTAssertTrue(app.buttons["welcome.feed"].waitForExistence(timeout: 15))
        app.buttons["welcome.feed"].tap()
        let field = app.textFields["addFeed.address"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        for bad in ["not an address at all", "https://example.com", "https://nothing-here.invalid/feed.xml"] {
            replace(field, with: bad)
            app.buttons["addFeed.follow"].tap()
            XCTAssertTrue(app.staticTexts["addFeed.error"].waitForExistence(timeout: 30), "\(bad) is refused with a reason")
            XCTAssertTrue(app.buttons["addFeed.follow"].waitForExistence(timeout: 5), "the form stays usable")
        }
        replace(field, with: "  feed://feeds.podcastindex.org/pc20.xml  ")
        app.buttons["addFeed.follow"].tap()
        XCTAssertTrue(playButton(app).waitForExistence(timeout: 30), "the right address still works")
    }

    /// A wrong password and an address nothing answers at each say why; the form stays usable.
    func testWrongSignIns() {
        let app = launch()
        XCTAssertTrue(app.buttons["welcome.server"].waitForExistence(timeout: 15))
        app.buttons["welcome.server"].tap()
        for (address, user) in [("https://demopi.own.audio", "nobody@example.com"), ("10.255.255.1:9", "someone@example.com")] {
            for (id, text) in [("addServer.address", address), ("addServer.username", user)] {
                let field = app.textFields[id]
                XCTAssertTrue(field.waitForExistence(timeout: 10))
                replace(field, with: text)
            }
            let secret = app.secureTextFields["addServer.password"]
            secret.tap()
            secret.typeText("wrong-password")
            app.buttons["addServer.add"].tap()
            XCTAssertTrue(app.staticTexts["addServer.error"].waitForExistence(timeout: 60), "\(address) says why it failed")
            dismissSavePasswordPrompt(app)
            secret.tap()
            secret.press(forDuration: 1)
            if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap(); secret.typeText(XCUIKeyboardKey.delete.rawValue) }
        }
        XCTAssertTrue(app.buttons["addServer.demo"].exists, "the form stays usable")
    }

    /// Skips and play/pause hammered faster than anything can load: afterwards the episode still
    /// plays and the position moves.
    func testHammeredPlayer() {
        let app = launch(["-debugFeedURL", feed])
        playFirst(app)
        app.buttons["miniPlayer"].tap()
        let elapsed = app.staticTexts["player.elapsed"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 10))
        for round in 0..<24 {
            app.buttons[["player.skipForward", "player.skipBackward", "player.playPause", "player.skipForward"][round % 4]].tap()
        }
        let playPause = app.buttons["player.playPause"]
        let settle = Date()
        while playPause.label != "Pause", Date().timeIntervalSince(settle) < 15 {
            if playPause.label == "Play" { playPause.tap() }
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        let before = elapsed.label
        let started = Date()
        while elapsed.label == before, Date().timeIntervalSince(started) < 20 { RunLoop.current.run(until: Date().addingTimeInterval(0.5)) }
        XCTAssertNotEqual(elapsed.label, before, "still plays after the hammering")
    }

    /// Stop pressed while the episode is still loading: nothing starts playing when the load
    /// lands, and playing again works.
    func testStopWhileLoading() {
        let app = launch(["-debugFeedURL", feed])
        let play = playButton(app)
        XCTAssertTrue(play.waitForExistence(timeout: 30))
        play.tap()
        let mini = app.buttons["miniPlayer"]
        XCTAssertTrue(mini.waitForExistence(timeout: 15))
        mini.tap()
        app.buttons["player.stop"].tap()
        XCTAssertFalse(mini.waitForExistence(timeout: 6), "nothing comes back after stop")
        playFirst(app)
    }

    /// Tabs switched as fast as they can be tapped and searches nobody would type: the app keeps
    /// answering and an episode still plays.
    func testRestlessNavigationAndOddSearches() {
        let app = launch(["-debugFeedURL", feed])
        XCTAssertTrue(playButton(app).waitForExistence(timeout: 30))
        for round in 0..<16 {
            let tab = tabButton(app, ["Shows", "Downloads", "New Episodes"][round % 3])
            if tab.exists { tab.tap() }
        }
        let search = openSearch(app)
        for text in ["%", "' OR 1=1 --", "😀🎙️", "<script>alert(1)</script>", "\\", "   ", String(repeating: "podcast ", count: 30), "../../etc/passwd"] {
            search.tap()
            if let current = search.value as? String, !current.isEmpty, current != search.placeholderValue {
                search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
            }
            search.typeText(text)
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        }
        XCTAssertTrue(app.state == .runningForeground, "still running")
        // iOS 26 folds the tab bar away while searching; its Close button brings it back.
        for label in ["Close", "Cancel"] where app.buttons[label].exists {
            app.buttons[label].firstMatch.tap()
            break
        }
        // The folded bar shows only the tab used last; tapping it unfolds the rest.
        if !app.buttons["New Episodes"].exists { tabButton(app, "Shows").tap() }
        tabButton(app, "New Episodes").tap()
        playFirst(app)
    }

    /// Mid-episode: sent to the background and back, then killed and started again. The show is
    /// still followed and the position is kept.
    func testInterruptionsWhilePlaying() {
        var app = launch(["-debugFeedURL", feed])
        playFirst(app)
        RunLoop.current.run(until: Date().addingTimeInterval(4))
        XCUIDevice.shared.press(.home)
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        app.activate()
        XCTAssertTrue(app.buttons["miniPlayer"].waitForExistence(timeout: 10), "still loaded after the background")
        app.buttons["miniPlayer.playPause"].tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        tabButton(app, "Shows").tap()
        let show = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'show.'")).firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 15), "the show is still followed")
        tabButton(app, "New Episodes").tap()
        let episode = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'episode.'")).firstMatch
        XCTAssertTrue(episode.waitForExistence(timeout: 15))
        episode.tap()
        XCTAssertTrue(app.buttons["episode.play"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["episode.play"].label.contains("Resume"), "the position was kept")
    }

    // MARK: - Helpers

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extra
        app.launch()
        return app
    }

    private func playButton(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'play.'")).firstMatch
    }

    /// Plays the first episode in the list until the mini player's clock is running.
    private func playFirst(_ app: XCUIApplication) {
        let play = playButton(app)
        XCTAssertTrue(play.waitForExistence(timeout: 30))
        play.tap()
        let pause = app.buttons["miniPlayer.playPause"]
        let started = Date()
        while !(pause.exists && pause.label == "Pause"), Date().timeIntervalSince(started) < 30 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTAssertEqual(pause.label, "Pause", "the episode plays")
    }

    /// Empties the field first: the cursor lands where the tap was, so it is put at the end.
    private func replace(_ field: XCUIElement, with text: String) {
        field.tap()
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        if let current = field.value as? String, !current.isEmpty, current != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
        }
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text, "the field holds only what was typed")
    }

    func dismissSavePasswordPrompt(_ app: XCUIApplication) {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            for label in ["Not Now", "Teď ne"] where app.buttons[label].exists {
                app.buttons[label].tap()
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
    }

    /// The tab bar's button: iOS 26 lists more than one button with a tab's label, and only one
    /// can be hit.
    private func tabButton(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", label))
        _ = matches.firstMatch.waitForExistence(timeout: 10)
        return matches.allElementsBoundByIndex.first { $0.isHittable } ?? matches.firstMatch
    }

    /// The Search tab is a capsule that opens into the field on a tap, sometimes on a second.
    private func openSearch(_ app: XCUIApplication) -> XCUIElement {
        let field = app.searchFields.firstMatch
        for _ in 0..<3 where !field.exists {
            let tab = tabButton(app, "Search")
            if tab.exists { tab.tap() }
            if field.waitForExistence(timeout: 3) { break }
        }
        XCTAssertTrue(field.exists, "the Search tab shows a search field")
        return field
    }
}
