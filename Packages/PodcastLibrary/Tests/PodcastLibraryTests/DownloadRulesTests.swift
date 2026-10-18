import Foundation
import Testing

@testable import PodcastLibrary

@Suite("DownloadRules")
struct DownloadRulesTests {
    private func item(_ id: String, day: Int, played: Bool = false, downloaded: Bool = false) -> DownloadRules.Item {
        .init(id: id, publishedAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(day) * 86_400), isPlayed: played, isDownloaded: downloaded)
    }

    @Test("no rules, nothing changes")
    func noRules() {
        let items = [item("a", day: 3, played: true, downloaded: true), item("b", day: 2)]
        #expect(DownloadRules.plan(for: items, settings: ShowSettings(), protected: nil) == .init())
    }

    @Test("the newest N unplayed are downloaded, never the back catalogue")
    func autoDownload() {
        let items = [item("old", day: 1), item("new", day: 5), item("mid", day: 3, played: true), item("got", day: 4, downloaded: true)]
        let plan = DownloadRules.plan(for: items, settings: ShowSettings(autoDownload: 3), protected: nil)
        #expect(plan.download == ["new"])
        #expect(plan.remove.isEmpty)
    }

    @Test("played downloads go when Delete When Played is on, except the one playing")
    func deleteWhenPlayed() {
        let items = [item("a", day: 3, played: true, downloaded: true), item("b", day: 2, played: true, downloaded: true), item("c", day: 1, downloaded: true)]
        let plan = DownloadRules.plan(for: items, settings: ShowSettings(deleteWhenPlayed: true), protected: "b")
        #expect(plan.remove == ["a"])
    }

    @Test("Keep at Most keeps the newest and lets the oldest go, the playing one never")
    func keepAtMost() {
        let items = (1...5).map { item("e\($0)", day: $0, downloaded: true) }
        #expect(DownloadRules.plan(for: items, settings: ShowSettings(keepAtMost: 3), protected: nil).remove == ["e1", "e2"])
        #expect(DownloadRules.plan(for: items, settings: ShowSettings(keepAtMost: 3), protected: "e1").remove == ["e2"])
    }

    @Test("new downloads count against Keep at Most, so the rules don't fight")
    func togetherWithTheLimit() {
        let items = [item("new", day: 5), item("d4", day: 4, downloaded: true), item("d3", day: 3, downloaded: true)]
        let plan = DownloadRules.plan(for: items, settings: ShowSettings(autoDownload: 1, keepAtMost: 2), protected: nil)
        #expect(plan.download == ["new"])
        #expect(plan.remove == ["d3"])
        // A limit smaller than the downloads it would ask for: only the newest come.
        let tight = DownloadRules.plan(for: [item("x", day: 3), item("y", day: 2)], settings: ShowSettings(autoDownload: 2, keepAtMost: 1), protected: nil)
        #expect(tight.download == ["x"])
    }

    @Test("settings saved before the download rules existed still load")
    func oldSettingsDecode() throws {
        let old = #"{"inInbox":false,"autoQueue":false,"skipIntroSecs":30}"#
        let settings = try JSONDecoder().decode(ShowSettings.self, from: Data(old.utf8))
        #expect(settings.inInbox == false && settings.skipIntroSecs == 30)
        #expect(settings.autoDownload == 0 && settings.deleteWhenPlayed == false && settings.keepAtMost == nil)
        #expect(!settings.hasDownloadRules)
    }
}
