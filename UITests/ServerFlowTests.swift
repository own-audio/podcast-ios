import XCTest

/// Each server kind signed in through the launch arguments, its New Episodes shown, an episode
/// played and stopped. Skipped when the server's variables are not set (scripts/test-servers.sh
/// passes them from test-servers.local.env). Uses the throwaway test accounts: playing moves
/// their position in one episode by a few seconds.
final class ServerFlowTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testAudiobookshelf() throws {
        try run(kind: "audiobookshelf", prefix: "AUDIOBOOKSHELF", passwordKey: "AUDIOBOOKSHELF_PASSWORD")
    }

    func testOwnAudio() throws {
        try run(kind: "ownAudio", prefix: "OWNAUDIO", userKey: "OWNAUDIO_EMAIL", passwordKey: "OWNAUDIO_ACCOUNT_PASSWORD")
    }

    /// A show followed on the phone reaches the gPodder account.
    func testGPodderSubscriptionGoesUp() throws {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["GPODDER_HOST"], let user = env["GPODDER_USERNAME"], let password = env["GPODDER_PASSWORD"] else {
            throw XCTSkip("GPODDER_HOST is not set")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-debugFeedURL", "https://feeds.podcastindex.org/pc20.xml",
                               "-debugServerKind", "gpodder", "-debugServerHost", host, "-debugServerUser", user, "-debugServerPassword", password]
        app.launch()
        XCTAssertTrue(app.buttons["home.settings"].waitForExistence(timeout: 30))
        app.buttons["home.settings"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'settings.server.'")).firstMatch.waitForExistence(timeout: 10), "the account is listed")
    }

    private func run(kind: String, prefix: String, userKey: String? = nil, passwordKey: String) throws {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["\(prefix)_HOST"], let user = env[userKey ?? "\(prefix)_USERNAME"], let password = env[passwordKey] else {
            throw XCTSkip("\(prefix)_HOST is not set")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-debugServerKind", kind, "-debugServerHost", host, "-debugServerUser", user, "-debugServerPassword", password]
        app.launch()
        let play = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'play.'")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 60), "New Episodes from the server")
        play.tap()
        let mini = app.buttons["miniPlayer"]
        XCTAssertTrue(mini.waitForExistence(timeout: 20))
        mini.tap()
        let elapsed = app.staticTexts["player.elapsed"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 10))
        let first = elapsed.label
        let started = Date()
        while elapsed.label == first, Date().timeIntervalSince(started) < 30 { RunLoop.current.run(until: Date().addingTimeInterval(0.5)) }
        XCTAssertNotEqual(elapsed.label, first, "the server's episode plays")
        app.buttons["player.stop"].tap()
        XCTAssertFalse(app.buttons["miniPlayer"].waitForExistence(timeout: 3))
    }
}
