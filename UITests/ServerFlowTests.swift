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

    /// A show followed on the phone reaches the gPodder account: signed in with the account,
    /// the app syncs, and the account (asked as another device) lists the show.
    func testGPodderSubscriptionGoesUp() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["GPODDER_HOST"], let user = env["GPODDER_USERNAME"], let password = env["GPODDER_PASSWORD"] else {
            throw XCTSkip("GPODDER_HOST is not set")
        }
        let feed = "https://feeds.podcastindex.org/pc20.xml"
        let app = await XCUIApplication()
        await MainActor.run {
            app.launchArguments = ["-uiTestReset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                                   "-debugFeedURL", feed,
                                   "-debugServerKind", "gpodder", "-debugServerHost", host, "-debugServerUser", user, "-debugServerPassword", password]
            app.launch()
        }
        let settings = await app.buttons["home.settings"]
        let appeared = await MainActor.run { settings.waitForExistence(timeout: 30) }
        XCTAssertTrue(appeared)

        var request = URLRequest(url: URL(string: host)!.appending(path: "api/2/subscriptions/\(user)/ui-test-check.json"))
        request.setValue("Basic " + Data("\(user):\(password)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        var listed = false
        for _ in 0..<20 where !listed {
            if let (data, _) = try? await URLSession.shared.data(for: request),
               let answer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let add = answer["add"] as? [String] {
                listed = add.contains(feed)
            }
            if !listed { try await Task.sleep(for: .seconds(1)) }
        }
        XCTAssertTrue(listed, "the show followed on the phone is on the account")

        await MainActor.run { settings.tap() }
        let row = await app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'settings.server.'")).firstMatch
        let rowShown = await MainActor.run { row.waitForExistence(timeout: 10) }
        XCTAssertTrue(rowShown, "the account is listed in Settings")
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
