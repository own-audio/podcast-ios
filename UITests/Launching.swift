import XCTest

extension XCUIApplication {
    /// Launches with the arguments set, and makes sure they arrived. iOS prewarms apps it
    /// expects to be opened: it starts the process early, without arguments, and a test's launch
    /// can then be handed that process — in the device's language, without `-uiTestReset`. The
    /// first screen tells: its words must be in the language asked for. If not, the launch is
    /// tried again.
    func launchChecked(file: StaticString = #filePath, line: UInt = #line) {
        let czech = launchArguments.contains("(cs)")
        let settings = czech ? "Nastavení" : "Settings"
        let tagline = czech ? "Vaše podcasty. Bez účtu, bez serveru." : "Your podcasts. No account, no server needed."
        for attempt in 1...3 {
            if state != .notRunning { terminate() }
            launch()
            let home = buttons["home.settings"], welcome = staticTexts["welcome.tagline"]
            let end = Date().addingTimeInterval(30)
            while Date() < end, !home.exists, !welcome.exists { RunLoop.current.run(until: Date().addingTimeInterval(0.3)) }
            if (home.exists && home.label == settings) || (welcome.exists && welcome.label == tagline) { return }
            if attempt == 3 { XCTFail("the app didn't start with its arguments", file: file, line: line) }
        }
    }
}
