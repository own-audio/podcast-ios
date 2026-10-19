import XCTest

/// Discover: categories, a category's shows, search and suggestions — from Apple's directory
/// with no server, and from an own.audio server's catalogue (`CATALOGUE_*`). Needs the network.
final class DiscoveryTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func tab(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", label))
        _ = matches.firstMatch.waitForExistence(timeout: 10)
        return matches.allElementsBoundByIndex.first { $0.isHittable } ?? matches.firstMatch
    }

    private func openDiscover(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["home.settings"].waitForExistence(timeout: 40))
        for _ in 0..<3 where !app.buttons["discover.addByAddress"].exists {
            tab(app, "Discover").tap()
            _ = app.buttons["discover.addByAddress"].waitForExistence(timeout: 5)
        }
        XCTAssertTrue(app.buttons["discover.addByAddress"].exists, "Discover opens on its own screen")
    }

    /// No server: Apple's genres, a genre's chart, a show from it to follow; no suggestions.
    func testDiscoverFromApple() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-debugFeedURL", "https://feeds.podcastindex.org/pc20.xml"]
        app.launchChecked()
        openDiscover(app)
        let news = app.buttons["discover.category.news"]
        XCTAssertTrue(news.waitForExistence(timeout: 15), "Apple's genres to browse")
        XCTAssertFalse(app.descendants(matching: .any)["discover.suggestions"].exists, "Apple knows no similar shows")
        news.tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'search.result.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "the genre's chart")
        row.tap()
        XCTAssertTrue(app.buttons["search.follow"].waitForExistence(timeout: 10) || app.buttons["search.open"].exists, "a show to follow")
    }

    /// An own.audio server with the catalogue: counted categories, a category's shows, search
    /// from the server, and shows like the ones followed.
    func testDiscoverFromTheServerCatalogue() throws {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["CATALOGUE_HOST"], let user = env["CATALOGUE_EMAIL"], let password = env["CATALOGUE_PASSWORD"] else {
            throw XCTSkip("CATALOGUE_HOST is not set")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-debugFeedURL", "https://feeds.podcastindex.org/pc20.xml",
                               "-debugServerKind", "ownAudio", "-debugServerHost", host, "-debugServerUser", user, "-debugServerPassword", password]
        app.launchChecked()
        openDiscover(app)
        let society = app.buttons["discover.category.society"]
        XCTAssertTrue(society.waitForExistence(timeout: 30), "the catalogue's categories")
        XCTAssertTrue(society.label.contains("shows"), "with how many shows: \(society.label)")
        let suggestion = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'suggestion.'")).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 40), "shows like the ones followed")
        XCTAssertTrue(suggestion.label.contains("Because you follow"), suggestion.label)

        society.tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'search.result.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "the category's shows")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // On iOS 26 the search tab's field shows once the tab is tapped, sometimes twice.
        let field = app.searchFields.firstMatch
        for _ in 0..<3 where !field.exists { tab(app, "Discover").tap(); _ = field.waitForExistence(timeout: 3) }
        XCTAssertTrue(field.exists)
        field.tap()
        field.typeText("news")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'From ' AND NOT (label CONTAINS 'Apple')")).firstMatch.waitForExistence(timeout: 20)
                      || app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'FROM ' AND NOT (label CONTAINS 'APPLE')")).firstMatch.exists,
                      "search answered by the server's catalogue")
    }
}
