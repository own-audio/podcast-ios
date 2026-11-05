import XCTest

/// The App Store screenshots, taken from a real server. Not a test of behaviour: run it on
/// purpose, on the device sizes the store wants, with a clean status bar, in light mode (see
/// `scripts/app-store-screenshots.sh`). Use an own.audio server holding only the demo library
/// (Creative Commons shows), signed in as the account that runs its family, as own.audio Music's
/// screenshots do, so the three apps' pictures show the same family and server.
///
/// `TEST_RUNNER_SCREENSHOT_LANGUAGE` is `en` or `cs`; `TEST_RUNNER_SCREENSHOT_DIR` is where the
/// PNGs go; `TEST_RUNNER_SCREENSHOT_SHOW` is the show whose page is shown.
final class AppStoreScreenshots: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var czech: Bool { env["SCREENSHOT_LANGUAGE"] == "cs" }

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard env["SERVER_HOST"] != nil, env["SCREENSHOT_DIR"] != nil, env["SCREENSHOT_LANGUAGE"] != nil else {
            throw XCTSkip("Set SERVER_HOST, SCREENSHOT_DIR and SCREENSHOT_LANGUAGE to take store screenshots")
        }
    }

    private func t(_ english: String, _ czech: String) -> String { self.czech ? czech : english }

    private var language: [String] {
        ["-uiTestReset", "-AppleLanguages", "(\(env["SCREENSHOT_LANGUAGE"]!))", "-AppleLocale", czech ? "cs_CZ" : "en_US"]
    }

    func testTakeScreenshots() throws {
        // First, the app as it opens for someone with no server at all.
        let app = XCUIApplication()
        app.launchArguments = language + ["-screenshotWordmark", "podcast"]
        app.launchChecked()
        XCTAssertTrue(app.buttons["welcome.search"].waitForExistence(timeout: 15))
        sleep(2)
        save(app, "8-welcome")
        app.terminate()

        app.launchArguments = language + [
            "-debugServerKind", "ownAudio", "-debugServerHost", env["SERVER_HOST"]!,
            "-debugServerUser", env["SERVER_USER"] ?? "", "-debugServerPassword", env["SERVER_PASSWORD"] ?? "",
            "-debugServerName", t("Family Podcasts", "Rodinné podcasty"),
        ]
        app.launchChecked()
        let play = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'play.'")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 90), "New Episodes from the server")
        // Artwork in.
        sleep(8)
        save(app, "1-new-episodes")

        // Two episodes for later, so Up Next has something in it.
        let rows = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'episode.' AND NOT identifier IN %@", ["episode.title", "episode.play"]
        ))
        for index in [1, 2] {
            XCTAssertTrue(rows.element(boundBy: index).waitForExistence(timeout: 15))
            rows.element(boundBy: index).tap()
            let later = app.buttons["episode.playLater"]
            XCTAssertTrue(later.waitForExistence(timeout: 10), "an episode's page offers Play Later")
            later.tap()
            sleep(1)
            back(app)
        }

        // The newest episode onto the phone, for the Downloads tab.
        XCTAssertTrue(rows.element(boundBy: 0).waitForExistence(timeout: 10))
        rows.element(boundBy: 0).tap()
        let download = app.buttons["episode.download"]
        XCTAssertTrue(download.waitForExistence(timeout: 10))
        download.tap()
        XCTAssertTrue(waitUntil(timeout: 300) { download.label == t("Downloaded", "Staženo") }, "the episode should download: \(download.label)")
        back(app)

        // The newest episode, a little way in.
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        play.tap()
        let miniPlayer = app.buttons["miniPlayer"]
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 40))
        sleep(10)
        miniPlayer.tap()
        XCTAssertTrue(app.descendants(matching: .any)["player.scrubber"].firstMatch.waitForExistence(timeout: 15))
        sleep(3)
        save(app, "2-player")

        app.buttons["player.upNext"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'upNext.'")).firstMatch
            .waitForExistence(timeout: 10))
        sleep(2)
        save(app, "4-up-next")
        dismissSheet(app)
        let playPause = app.buttons["player.playPause"]
        if playPause.exists && playPause.label == t("Pause", "Pozastavit") { playPause.tap() }
        app.buttons["player.close"].tap()
        sleep(1)

        // A show's page.
        app.buttons["tab.shows"].firstMatch.tap()
        let name = env["SCREENSHOT_SHOW"] ?? "Hacker Public Radio"
        let show = app.descendants(matching: .any)["show.\(name)"].firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 30), "\(name) should be followed")
        show.tap()
        XCTAssertTrue(app.descendants(matching: .any)["show.filter"].firstMatch.waitForExistence(timeout: 20))
        sleep(4)
        save(app, "3-show")

        app.buttons["tab.search"].firstMatch.tap()
        sleep(6)
        save(app, "5-discover")
        // The search tab takes the tab bar's place until its field is closed.
        leaveSearch(app)

        app.buttons["tab.downloads"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'downloads.source.'")).firstMatch
            .waitForExistence(timeout: 15), "the download should be listed")
        sleep(2)
        save(app, "6-downloads")

        // The family, from the server's page in Settings.
        app.buttons["tab.inbox"].firstMatch.tap()
        app.buttons["home.settings"].tap()
        let server = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'settings.server.'")).firstMatch
        XCTAssertTrue(server.waitForExistence(timeout: 10), "Settings should list the server")
        server.tap()
        let family = app.buttons["serverDetail.family"]
        // The iPad's form sheet is shorter than the server's page: the family may be below the fold.
        for _ in 0..<4 where !family.waitForExistence(timeout: 4) {
            app.swipeUp()
        }
        XCTAssertTrue(family.exists, "an own.audio server signed in to has a family")
        family.tap()
        XCTAssertTrue(app.staticTexts[t("Members", "Členové")].waitForExistence(timeout: 15))
        sleep(3)
        save(app, "7-family")
    }

    private func leaveSearch(_ app: XCUIApplication) {
        let downloads = app.buttons["tab.downloads"].firstMatch
        for _ in 0..<3 where !downloads.exists {
            let close = app.buttons.matching(NSPredicate(format: "label IN %@", ["Close", "Zavřít", "Cancel", "Zrušit"])).firstMatch
            if close.exists { close.tap() } else { app.buttons["tab.inbox"].firstMatch.tap() }
            sleep(1)
        }
    }

    private func back(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        sleep(1)
    }

    private func dismissSheet(_ app: XCUIApplication) {
        let done = app.buttons.matching(NSPredicate(format: "label IN %@", ["Done", "Hotovo"])).firstMatch
        if done.waitForExistence(timeout: 2) { done.tap(); sleep(1); return }
        app.swipeDown(velocity: .fast)
        sleep(1)
    }

    private func save(_ app: XCUIApplication, _ name: String) {
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let directory = URL(fileURLWithPath: env["SCREENSHOT_DIR"]!)
        try? shot.pngRepresentation.write(to: directory.appendingPathComponent("\(name).png"))
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        return condition()
    }
}
