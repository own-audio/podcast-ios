import XCTest

/// Screenshots for the App Store and the website, taken on the public own.audio demo
/// ("Try the Demo Library": Creative Commons shows, nothing private). Not a test of behaviour:
/// run it on purpose, on the store's device sizes, with a clean status bar
/// (`scripts/app-store-screenshots.sh`). `SCREENSHOT_LANGUAGE` is `en` or `cs`,
/// `SCREENSHOT_DIR` is where the PNGs go. Modelled on the music app's.
final class AppStoreScreenshots: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var czech: Bool { env["SCREENSHOT_LANGUAGE"] == "cs" }

    override func setUpWithError() throws {
        continueAfterFailure = true
        guard env["SCREENSHOT_DIR"] != nil, env["SCREENSHOT_LANGUAGE"] != nil else {
            throw XCTSkip("Set SCREENSHOT_DIR and SCREENSHOT_LANGUAGE to take store screenshots")
        }
    }

    private func t(_ english: String, _ czech: String) -> String { self.czech ? czech : english }

    func testTakeScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-AppleLanguages", "(\(env["SCREENSHOT_LANGUAGE"]!))", "-AppleLocale", czech ? "cs_CZ" : "en_US"]
        app.launchChecked()
        sleep(2)
        save(app, "0-welcome")

        // The welcome screen's "I run a server" opens the add-server form, which has the demo.
        let server = app.buttons["welcome.server"]
        XCTAssertTrue(server.waitForExistence(timeout: 15))
        server.tap()
        let demo = app.buttons["addServer.demo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 15))
        demo.tap()
        XCTAssertTrue(app.buttons["home.settings"].waitForExistence(timeout: 90), "New Episodes should open on the demo")
        // Artwork in.
        sleep(8)
        save(app, "1-new-episodes")

        app.buttons["tab.shows"].tap()
        let show = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'show.'")).firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 30), "the demo should have shows")
        sleep(5)
        save(app, "2-shows")

        show.tap()
        let episode = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'episode.'")).firstMatch
        XCTAssertTrue(episode.waitForExistence(timeout: 30))
        sleep(4)
        save(app, "3-show")

        // Play the newest episode from New Episodes, then open the player a little way in.
        app.buttons["tab.inbox"].tap()
        let play = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'play.'")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 30))
        play.tap()
        let miniPlayer = app.buttons["miniPlayer"]
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 40))
        sleep(10)
        miniPlayer.tap()
        XCTAssertTrue(app.descendants(matching: .any)["player.scrubber"].firstMatch.waitForExistence(timeout: 15))
        sleep(4)
        save(app, "4-player")
        if app.buttons["player.close"].exists { app.buttons["player.close"].tap() }

        app.buttons["tab.search"].tap()
        sleep(6)
        save(app, "5-discover")

        app.buttons["tab.downloads"].tap()
        sleep(3)
        save(app, "6-downloads")
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
}
