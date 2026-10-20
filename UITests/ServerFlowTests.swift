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
            app.launchChecked()
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

    /// The add-server form with the kind left on Automatic: a podfetch address, a user name and
    /// a password are enough, and it is added as a gPodder account.
    /// The Apple and Google buttons show for an own.audio server that takes them (the public
    /// canary takes both) and for nothing else. Needs only the network.
    func testSignInButtonsFollowTheServer() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchChecked()
        XCTAssertTrue(app.buttons["welcome.server"].waitForExistence(timeout: 15))
        app.buttons["welcome.server"].tap()
        let field = app.textFields["addServer.address"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        // The console's address, as people type it: the app knows the server is at api-canary.
        // A development build offers the canary as one tap, as the books and music apps do.
        XCTAssertTrue(app.buttons["addServer.canary"].waitForExistence(timeout: 10))
        field.typeText("app-canary.own.audio")
        XCTAssertTrue(app.buttons["addServer.apple"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["addServer.google"].exists)
        field.clearAndType("https://feeds.npr.org")
        XCTAssertTrue(app.buttons["addServer.google"].waitForNonExistence(timeout: 20))
        XCTAssertFalse(app.buttons["addServer.apple"].exists)
    }

    func testAddServerFindsTheKindByItself() throws {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["PODFETCH_HOST"], let user = env["PODFETCH_TEST_USERNAME"], let password = env["PODFETCH_TEST_PASSWORD"] else {
            throw XCTSkip("PODFETCH_HOST is not set")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchChecked()
        XCTAssertTrue(app.buttons["welcome.server"].waitForExistence(timeout: 15))
        app.buttons["welcome.server"].tap()
        for (id, text) in [("addServer.address", host), ("addServer.username", user)] {
            let field = app.textFields[id]
            XCTAssertTrue(field.waitForExistence(timeout: 10))
            field.tap()
            field.typeText(text)
        }
        let secret = app.secureTextFields["addServer.password"]
        secret.tap()
        secret.typeText(password)
        app.buttons["addServer.add"].tap()
        // Added: the first screen gives way to the tabs.
        let settings = app.buttons["home.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 40), "the server was recognised and added")
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline, !settings.isHittable {
            for label in ["Not Now", "Teď ne"] where app.buttons[label].exists { app.buttons[label].tap() }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        let name = URL(string: host)?.host() ?? host
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "settings.server.\(name)")).firstMatch
        // iOS's "Save Password?" sheet can arrive late and take the first tap.
        for _ in 0..<3 where !row.exists {
            for label in ["Not Now", "Teď ne"] where app.buttons[label].exists { app.buttons[label].tap() }
            if settings.isHittable { settings.tap() }
            _ = row.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(row.exists, "listed in Settings")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'gPodder sync'")).firstMatch.exists, "as a gPodder account")
    }

    /// The switch on New Episodes: one source at a time, or all together, in Shows too.
    func testSourceSwitch() throws {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["OWNAUDIO_HOST"], let user = env["OWNAUDIO_EMAIL"], let password = env["OWNAUDIO_ACCOUNT_PASSWORD"] else {
            throw XCTSkip("OWNAUDIO_HOST is not set")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-debugFeedURL", "https://feeds.podcastindex.org/pc20.xml",
                               "-debugServerKind", "ownAudio", "-debugServerHost", host, "-debugServerUser", user, "-debugServerPassword", password]
        app.launchChecked()
        let menu = app.buttons["home.serverMenu"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 40), "the switch shows with more than one source")
        XCTAssertTrue(menu.label.contains("All Sources"))

        let shows = app.buttons.matching(NSPredicate(format: "label == 'Shows'")).allElementsBoundByIndex.first { $0.isHittable } ?? app.buttons["Shows"].firstMatch
        shows.tap()
        let phoneShow = app.descendants(matching: .any)["show.Podcasting 2.0"]
        XCTAssertTrue(phoneShow.waitForExistence(timeout: 20))
        let serverShows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'show.' AND identifier != 'show.Podcasting 2.0'"))
        XCTAssertTrue(serverShows.firstMatch.waitForExistence(timeout: 30), "all sources: the server's shows too")

        let inbox = app.buttons.matching(NSPredicate(format: "label == 'New Episodes'")).allElementsBoundByIndex.first { $0.isHittable } ?? app.buttons["New Episodes"].firstMatch
        inbox.tap()
        for _ in 0..<3 where !app.buttons["This iPhone"].exists {
            for label in ["Not Now", "Teď ne"] where app.buttons[label].exists { app.buttons[label].tap() }
            menu.tap()
            _ = app.buttons["This iPhone"].waitForExistence(timeout: 3)
        }
        app.buttons["This iPhone"].tap()
        XCTAssertTrue(menu.label.contains("This iPhone"))
        shows.tap()
        XCTAssertTrue(phoneShow.waitForExistence(timeout: 10))
        XCTAssertEqual(serverShows.count, 0, "only this iPhone's shows")
    }

    /// Unfollow is offered for this iPhone's shows only: own.audio can't unfollow for a player yet,
    /// and on Audiobookshelf it would delete the show for everyone.
    func testUnfollowOnlyForThisIPhonesShows() throws {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["OWNAUDIO_HOST"], let user = env["OWNAUDIO_EMAIL"], let password = env["OWNAUDIO_ACCOUNT_PASSWORD"] else {
            throw XCTSkip("OWNAUDIO_HOST is not set")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-debugFeedURL", "https://feeds.podcastindex.org/pc20.xml",
                               "-debugServerKind", "ownAudio", "-debugServerHost", host, "-debugServerUser", user, "-debugServerPassword", password]
        app.launchChecked()
        XCTAssertTrue(app.buttons["home.serverMenu"].firstMatch.waitForExistence(timeout: 40))
        let shows = app.buttons.matching(NSPredicate(format: "label == 'Shows'")).allElementsBoundByIndex.first { $0.isHittable } ?? app.buttons["Shows"].firstMatch
        shows.tap()

        let phoneShow = app.descendants(matching: .any)["show.Podcasting 2.0"]
        XCTAssertTrue(phoneShow.waitForExistence(timeout: 20))
        phoneShow.tap()
        app.buttons["show.menu"].firstMatch.tap()
        XCTAssertTrue(app.buttons["show.unfollow"].waitForExistence(timeout: 5), "this iPhone's show can be unfollowed")
        // Close the menu, then back to Shows.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
        XCTAssertTrue(app.buttons["show.unfollow"].waitForNonExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let serverShow = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'show.' AND identifier != 'show.Podcasting 2.0'")).firstMatch
        XCTAssertTrue(serverShow.waitForExistence(timeout: 30))
        serverShow.tap()
        app.buttons["show.menu"].firstMatch.tap()
        XCTAssertTrue(app.buttons["show.settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["show.unfollow"].exists, "a server's show offers no Unfollow")
    }

    /// Never lose a position: an own.audio episode downloaded, then played with Offline Mode on.
    /// Once Offline Mode is off the position reaches the server — a fresh install, with nothing
    /// on the phone, offers to resume it.
    func testPositionFromOfflineReachesTheServer() throws {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["OWNAUDIO_HOST"], let user = env["OWNAUDIO_EMAIL"], let password = env["OWNAUDIO_ACCOUNT_PASSWORD"] else {
            throw XCTSkip("OWNAUDIO_HOST is not set")
        }
        func launch() -> XCUIApplication {
            let app = XCUIApplication()
            app.launchArguments = ["-uiTestReset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                                   "-debugServerKind", "ownAudio", "-debugServerHost", host, "-debugServerUser", user, "-debugServerPassword", password]
            app.launchChecked()
            return app
        }
        func tab(_ app: XCUIApplication, _ label: String) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex.first { $0.isHittable } ?? app.buttons[label].firstMatch
        }
        func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
            let end = Date().addingTimeInterval(timeout)
            while Date() < end, !condition() { RunLoop.current.run(until: Date().addingTimeInterval(0.5)) }
            return condition()
        }

        var app = launch()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'episode.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 60), "New Episodes from the server")
        let rowId = row.identifier
        row.tap()
        // From the start, whatever an earlier run left: played, then unplayed.
        let mark = app.buttons["episode.markPlayed"]
        XCTAssertTrue(mark.waitForExistence(timeout: 10))
        mark.tap()
        XCTAssertTrue(waitUntil(5) { mark.label == "Unplayed" })
        mark.tap()
        XCTAssertTrue(waitUntil(5) { mark.label == "Played" })
        XCTAssertEqual(app.buttons["episode.play"].label, "Play")
        let download = app.buttons["episode.download"]
        download.tap()
        XCTAssertTrue(waitUntil(300) { download.label == "Downloaded" }, "the download finishes: \(download.label)")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let offline = app.buttons["home.offlineMode"].firstMatch
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
        XCTAssertTrue(waitUntil(20) { elapsed.label != "0:00" }, "it plays offline")
        app.buttons["player.skipForward"].tap()
        app.buttons["player.skipForward"].tap()
        app.buttons["player.stop"].tap()

        tab(app, "New Episodes").tap()
        offline.tap()
        XCTAssertFalse(app.staticTexts["Offline Mode is on"].waitForExistence(timeout: 3))
        // Turning Offline Mode off refreshes, which sends what waited.
        sleep(8)
        app.terminate()

        app = launch()
        let again = app.buttons[rowId]
        XCTAssertTrue(again.waitForExistence(timeout: 60), "the episode is still unplayed")
        again.tap()
        // Playing asks the server, which has the position from offline: it starts past the
        // two skips (a fresh install's lists only know positions of episodes stored before).
        let start = app.buttons["episode.play"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        for label in ["Continue from", "Keep this iPhone"] where app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch.waitForExistence(timeout: 2) {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch.tap()
        }
        XCTAssertTrue(app.buttons["miniPlayer"].waitForExistence(timeout: 20))
        app.buttons["miniPlayer"].tap()
        let at = app.staticTexts["player.elapsed"]
        XCTAssertTrue(at.waitForExistence(timeout: 10))
        let seconds = { at.label.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) } }
        XCTAssertTrue(waitUntil(15) { seconds() >= 50 }, "the server has the position from offline: \(at.label)")
        app.buttons["player.stop"].tap()
    }

    /// An own.audio server's page leads to its Family (members, storage) and Devices (this iPhone
    /// marked first), as the books app's Settings do.
    func testFamilyAndDevices() throws {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["OWNAUDIO_HOST"], let user = env["OWNAUDIO_EMAIL"], let password = env["OWNAUDIO_ACCOUNT_PASSWORD"] else {
            throw XCTSkip("OWNAUDIO_HOST is not set")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-debugServerKind", "ownAudio", "-debugServerHost", host, "-debugServerUser", user, "-debugServerPassword", password]
        app.launchChecked()
        let settings = app.buttons["home.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 40))
        let name = URL(string: host)?.host() ?? host
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "settings.server.\(name)")).firstMatch
        for _ in 0..<3 where !row.exists {
            for label in ["Not Now", "Teď ne"] where app.buttons[label].exists { app.buttons[label].tap() }
            if settings.isHittable { settings.tap() }
            _ = row.waitForExistence(timeout: 5)
        }
        row.tap()

        let family = app.buttons["serverDetail.family"]
        XCTAssertTrue(family.waitForExistence(timeout: 10))
        family.tap()
        XCTAssertTrue(app.staticTexts["Members"].waitForExistence(timeout: 20) || app.staticTexts["MEMBERS"].exists, "the household's members")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH '(you)'")).firstMatch.exists, "you among them")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let devices = app.buttons["serverDetail.devices"]
        XCTAssertTrue(devices.waitForExistence(timeout: 10))
        devices.tap()
        XCTAssertTrue(app.staticTexts["This device"].waitForExistence(timeout: 20), "this iPhone is marked")
        // Below every device; a test account signed in by many runs has a long list.
        let everywhere = app.buttons["devices.signOutEverywhere"]
        for _ in 0..<15 where !everywhere.exists { app.swipeUp() }
        XCTAssertTrue(everywhere.exists)
    }

    /// A server's page in Settings: it answers and accepts the sign-in, its addresses are listed,
    /// one can be added, and the server can be renamed.
    func testServerPage() throws {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["OWNAUDIO_HOST"], let user = env["OWNAUDIO_EMAIL"], let password = env["OWNAUDIO_ACCOUNT_PASSWORD"] else {
            throw XCTSkip("OWNAUDIO_HOST is not set")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-debugServerKind", "ownAudio", "-debugServerHost", host, "-debugServerUser", user, "-debugServerPassword", password]
        app.launchChecked()
        let settings = app.buttons["home.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 40))
        let name = URL(string: host)?.host() ?? host
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "settings.server.\(name)")).firstMatch
        for _ in 0..<3 where !row.exists {
            for label in ["Not Now", "Teď ne"] where app.buttons[label].exists { app.buttons[label].tap() }
            if settings.isHittable { settings.tap() }
            _ = row.waitForExistence(timeout: 5)
        }
        row.tap()

        let result = app.descendants(matching: .any)["serverDetail.checkResult"]
        XCTAssertTrue(result.waitForExistence(timeout: 30))
        XCTAssertTrue(result.label.contains("accepts the sign-in"), result.label)
        XCTAssertTrue(app.descendants(matching: .any)["serverDetail.status"].label.contains("Connected"))
        let original = app.descendants(matching: .any).matching(identifier: "serverDetail.address.\(host)").firstMatch
        for _ in 0..<4 where !original.exists { app.swipeUp() }
        XCTAssertTrue(original.exists, "the address it was added with")

        app.buttons["serverDetail.addAddress"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("192.168.1.250:8080")
        app.alerts.buttons["Add"].tap()
        let added = app.descendants(matching: .any).matching(identifier: "serverDetail.address.http://192.168.1.250:8080").firstMatch
        for _ in 0..<4 where !added.waitForExistence(timeout: 2) { app.swipeUp() }
        XCTAssertTrue(added.exists, "an address added by hand")
        XCTAssertTrue(app.staticTexts["Home network · added by you"].exists, "on the home network, added by hand")

        for _ in 0..<4 where !app.buttons["serverDetail.rename"].isHittable { app.swipeDown() }
        app.buttons["serverDetail.rename"].tap()
        let nameField = app.alerts.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        let current = (nameField.value as? String) ?? ""
        nameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2) + "Demo")
        // On iOS 27 a tap right after typing can miss the alert's button: wait for it, and tap
        // it by position if the alert is still up.
        let save = app.alerts.firstMatch.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        if app.alerts.firstMatch.exists { app.alerts.firstMatch.buttons.element(boundBy: 1).tap() }
        XCTAssertTrue(app.navigationBars["Demo"].waitForExistence(timeout: 5), "renamed")
    }

    /// An Audiobookshelf server with several podcast libraries: each is in the switch on its own,
    /// and a library turned off on the server page leaves it.
    func testAudiobookshelfLibraries() throws {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["AUDIOBOOKSHELF_HOST"], let user = env["AUDIOBOOKSHELF_USERNAME"], let password = env["AUDIOBOOKSHELF_PASSWORD"] else {
            throw XCTSkip("AUDIOBOOKSHELF_HOST is not set")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-debugServerKind", "audiobookshelf", "-debugServerHost", host, "-debugServerUser", user, "-debugServerPassword", password]
        app.launchChecked()
        let menu = app.buttons["home.serverMenu"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 60), "the switch shows: this iPhone and the server's libraries")
        let name = URL(string: host)?.host() ?? host
        let libraryEntry = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(name) · ")).firstMatch
        for _ in 0..<5 where !libraryEntry.exists {
            for label in ["Not Now", "Teď ne"] where app.buttons[label].exists { app.buttons[label].tap() }
            menu.tap()
            if !libraryEntry.waitForExistence(timeout: 3) { app.tap() }
        }
        XCTAssertTrue(libraryEntry.exists, "a library on its own in the switch")
        let label = libraryEntry.label
        let library = String(label.dropFirst("\(name) · ".count))
        libraryEntry.tap()
        XCTAssertTrue(menu.label.contains(library), menu.label)

        app.buttons["home.settings"].firstMatch.tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "settings.server.\(name)")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let toggle = app.switches["serverDetail.library.\(library)"].firstMatch
        for _ in 0..<4 where !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "the library on the server page")
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0", "turned off")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertFalse(menu.label.contains(library), "the switch fell back from the hidden library: \(menu.label)")
        menu.tap()
        XCTAssertFalse(app.buttons[label].waitForExistence(timeout: 3), "the hidden library left the switch")
    }

    private func run(kind: String, prefix: String, userKey: String? = nil, passwordKey: String) throws {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["\(prefix)_HOST"], let user = env[userKey ?? "\(prefix)_USERNAME"], let password = env[passwordKey] else {
            throw XCTSkip("\(prefix)_HOST is not set")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-debugServerKind", kind, "-debugServerHost", host, "-debugServerUser", user, "-debugServerPassword", password]
        app.launchChecked()
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

private extension XCUIElement {
    func clearAndType(_ text: String) {
        tap()
        let current = value as? String ?? ""
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        typeText(text)
    }
}
