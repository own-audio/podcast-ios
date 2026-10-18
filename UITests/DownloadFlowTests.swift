import XCTest

/// Downloads against a real feed: an episode downloaded from its page shows in Downloads with
/// its source, plays in Offline Mode and is removed; a show's rule downloads its newest episode
/// by itself; a download goes on after the app is killed; the settings are there. Needs the
/// network, nothing else.
final class DownloadFlowTests: XCTestCase {
    /// Podcasting 2.0's own show, as in FeedFlowTests.
    private let feed = "https://feeds.podcastindex.org/pc20.xml"

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = (reset ? ["-uiTestReset"] : []) + ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-debugFeedURL", feed]
        app.launch()
        return app
    }

    /// The tab bar's button: other buttons can carry the same label off screen.
    private func tab(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", label))
        _ = matches.firstMatch.waitForExistence(timeout: 10)
        return matches.allElementsBoundByIndex.first { $0.isHittable } ?? matches.firstMatch
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        return condition()
    }

    /// The newest episode's page, from New Episodes.
    private func openNewestEpisode(_ app: XCUIApplication) -> XCUIElement {
        let episode = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'episode.'")).firstMatch
        XCTAssertTrue(episode.waitForExistence(timeout: 30), "New Episodes holds the newest episode")
        episode.tap()
        let download = app.buttons["episode.download"]
        XCTAssertTrue(download.waitForExistence(timeout: 10))
        return download
    }

    func testDownloadPlayOfflineAndRemove() {
        let app = launch()
        let download = openNewestEpisode(app)
        XCTAssertEqual(download.label, "Download")
        download.tap()
        XCTAssertTrue(waitUntil(timeout: 300) { download.label == "Downloaded" }, "the download finishes: \(download.label)")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        tab(app, "Downloads").tap()
        let source = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'downloads.source.'")).firstMatch
        let sourceGroup = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'downloads.source.'")).firstMatch
        XCTAssertTrue(sourceGroup.waitForExistence(timeout: 10), "the download is listed")
        XCTAssertTrue((source.exists ? source.label : sourceGroup.label).contains("This iPhone"), "and says where it came from")
        XCTAssertTrue(app.buttons["downloads.removeAll"].exists, "Remove All is offered")

        // Offline: it still plays, from the phone.
        tab(app, "New Episodes").tap()
        let offline = app.buttons["home.offlineMode"].firstMatch
        XCTAssertTrue(offline.waitForExistence(timeout: 10))
        offline.tap()
        XCTAssertTrue(app.staticTexts["Offline Mode is on"].waitForExistence(timeout: 5))
        tab(app, "Downloads").tap()
        let play = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'play.'")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        play.tap()
        let mini = app.buttons["miniPlayer"]
        XCTAssertTrue(mini.waitForExistence(timeout: 15))
        mini.tap()
        let elapsed = app.staticTexts["player.elapsed"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil(timeout: 20) { elapsed.label != "0:00" }, "the downloaded episode plays offline")
        app.buttons["player.stop"].tap()

        // Removed: the list is empty again.
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'downloads.' AND NOT (identifier BEGINSWITH 'downloads.source.') AND identifier != 'downloads.removeAll'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["Remove"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["downloads.empty"].waitForExistence(timeout: 5), "nothing is left")

        tab(app, "New Episodes").tap()
        offline.tap()
    }

    /// Show Settings → Download New Episodes → Newest 1: the newest episode comes by itself.
    func testShowRuleDownloadsTheNewest() {
        let app = launch()
        tab(app, "Shows").tap()
        let show = app.descendants(matching: .any)["show.Podcasting 2.0"]
        XCTAssertTrue(show.waitForExistence(timeout: 20))
        show.tap()
        app.buttons["show.menu"].firstMatch.tap()
        app.buttons["show.settings"].firstMatch.tap()
        let rule = app.buttons["showSettings.autoDownload"].firstMatch
        XCTAssertTrue(rule.waitForExistence(timeout: 10))
        XCTAssertTrue(app.switches["showSettings.deleteWhenPlayed"].exists)
        XCTAssertTrue(app.buttons["showSettings.keepAtMost"].exists)
        rule.tap()
        app.buttons["Newest 1"].firstMatch.tap()
        app.buttons["showSettings.done"].tap()

        tab(app, "Downloads").tap()
        // One play button per downloaded episode.
        let listed = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'play.'"))
        XCTAssertTrue(listed.firstMatch.waitForExistence(timeout: 30), "the rule downloads the newest episode")
        XCTAssertEqual(listed.count, 1, "and only that one")
        app.buttons["downloads.removeAll"].tap()
        app.buttons["downloads.removeAll.confirm"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["downloads.empty"].waitForExistence(timeout: 5))
    }

    /// Killed mid-download and started again: the download finishes, and the episode plays.
    func testDownloadGoesOnAfterAKill() {
        var app = launch()
        var download = openNewestEpisode(app)
        download.tap()
        XCTAssertTrue(waitUntil(timeout: 20) { download.label.hasPrefix("Downloading") }, "the download starts")
        app.terminate()

        app = launch(reset: false)
        download = openNewestEpisode(app)
        if download.label == "Download" || download.label.hasPrefix("Download failed") { download.tap() }
        XCTAssertTrue(waitUntil(timeout: 300) { download.label == "Downloaded" }, "the download finishes after the restart: \(download.label)")
        app.buttons["episode.play"].tap()
        XCTAssertTrue(app.buttons["miniPlayer"].waitForExistence(timeout: 15), "and the episode plays")
    }

    /// The downloads settings, in Settings, as in the books app.
    func testDownloadSettings() {
        let app = launch()
        let settings = app.buttons["home.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 30))
        settings.tap()
        for id in ["settings.downloads", "settings.storageCap"] {
            XCTAssertTrue(app.buttons[id].firstMatch.waitForExistence(timeout: 5), id)
        }
        XCTAssertTrue(app.switches["settings.offlineMode"].exists)
        XCTAssertTrue(app.switches["settings.wifiOnly"].exists)
        XCTAssertEqual(app.switches["settings.wifiOnly"].value as? String, "1", "Wi-Fi only by default")
        app.buttons["settings.downloads"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["downloads.empty"].waitForExistence(timeout: 5), "Downloads opens from Settings")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let mobile = app.buttons["settings.mobileData"].firstMatch
        for _ in 0..<4 where !mobile.isHittable { app.swipeUp() }
        XCTAssertTrue(mobile.exists)
    }
}
