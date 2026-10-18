import XCTest

/// The app launches to its first screen, in English and in Czech. Needs no server, so it runs
/// on every build.
final class LaunchTests: XCTestCase {
    func testLaunchesToTheFirstScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchChecked()
        let tagline = app.staticTexts["welcome.tagline"]
        XCTAssertTrue(tagline.waitForExistence(timeout: 15))
        XCTAssertEqual(tagline.label, "Your podcasts. No account, no server needed.")
    }

    func testFirstScreenInCzech() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-AppleLanguages", "(cs)", "-AppleLocale", "cs_CZ"]
        app.launchChecked()
        let tagline = app.staticTexts["welcome.tagline"]
        XCTAssertTrue(tagline.waitForExistence(timeout: 15))
        XCTAssertEqual(tagline.label, "Vaše podcasty. Bez účtu, bez serveru.")
    }
}

/// On iPad the tabs are a sidebar; the mini player still plays. Skipped on iPhone.
final class IPadTests: XCTestCase {
    func testSidebarOnIPad() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad only") }
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-debugFeedURL", "https://feeds.podcastindex.org/pc20.xml"]
        app.launchChecked()
        let toggle = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sidebar'")).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 15), "the sidebar's show/hide button")
        let play = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'play.'")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 30))
        play.tap()
        XCTAssertTrue(app.buttons["miniPlayer"].waitForExistence(timeout: 15), "the mini player with the sidebar")
    }
}
