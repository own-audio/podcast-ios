import XCTest

/// The app launches to its first screen, in English and in Czech. Needs no server, so it runs
/// on every build.
final class LaunchTests: XCTestCase {
    func testLaunchesToTheFirstScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let tagline = app.staticTexts["welcome.tagline"]
        XCTAssertTrue(tagline.waitForExistence(timeout: 15))
        XCTAssertEqual(tagline.label, "Your podcasts. No account, no server needed.")
    }

    func testFirstScreenInCzech() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-AppleLanguages", "(cs)", "-AppleLocale", "cs_CZ"]
        app.launch()
        let tagline = app.staticTexts["welcome.tagline"]
        XCTAssertTrue(tagline.waitForExistence(timeout: 15))
        XCTAssertEqual(tagline.label, "Vaše podcasty. Bez účtu, bez serveru.")
    }
}
