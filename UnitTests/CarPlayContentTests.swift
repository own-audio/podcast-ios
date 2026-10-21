import CarPlay
import Foundation
import PodcastLibrary
import Testing
@testable import OwnAudioPodcasts

/// What the car's screen shows, checked without a car (see `CarPlayContent`).
@MainActor
@Suite("CarPlay content")
struct CarPlayContentTests {
    private let server = SourceRef.server(UUID())

    private func episode(_ id: String, show: String = "s", day: Int = 0, durationMs: Int64? = 3_600_000) -> SourcedEpisode {
        let published = Date(timeIntervalSince1970: 1_700_000_000 + Double(day) * 86_400)
        return SourcedEpisode(source: server, episode: Episode(id: id, showId: show, title: "Episode \(id)", publishedAt: published, durationMs: durationMs))
    }

    @Test("the start screen lists New Episodes, Downloads and Shows, in that order")
    func root() {
        #expect(CarPlayContent.rootEntries(hasShows: true) == [.newEpisodes, .downloads, .shows])
        #expect(CarPlayContent.rootEntries(hasShows: true).map(\.title) == ["New Episodes", "Downloads", "Shows"])
        #expect(CarPlayContent.rootEntries(hasShows: false).isEmpty, "nothing followed: no lists")
    }

    @Test("New Episodes keeps the inbox order, only what can play, at most 100")
    func newEpisodes() {
        let inbox = (0..<150).map { episode("e\($0)") }
        let playable = CarPlayContent.newEpisodes(inbox) { $0.episode.id != "e1" }
        #expect(playable.count == CarPlayContent.maxItems)
        #expect(playable.first?.episode.id == "e0")
        #expect(!playable.contains { $0.episode.id == "e1" }, "offline, what isn't on the phone is left out")
    }

    @Test("Downloads lists finished downloads only, the newest first")
    func downloads() {
        func entry(_ id: String, finished: Double?) -> DownloadManager.DownloadedEpisode {
            let item = episode(id)
            return DownloadManager.DownloadedEpisode(
                id: item.id, source: server.id, episode: item.episode, show: nil,
                fileName: finished == nil ? nil : "\(id).mp3", bytes: 1,
                startedAt: Date(timeIntervalSince1970: 0), finishedAt: finished.map(Date.init(timeIntervalSince1970:)), lastPlayedAt: nil
            )
        }
        let list = CarPlayContent.downloads([entry("old", finished: 100), entry("busy", finished: nil), entry("new", finished: 200)])
        #expect(list.map(\.episode.id) == ["new", "old"])
    }

    @Test("a show's episodes: newest first, playable only")
    func showEpisodes() {
        let list = CarPlayContent.showEpisodes([episode("a", day: 1), episode("b", day: 3), episode("c", day: 2)]) { $0.episode.id != "c" }
        #expect(list.map(\.episode.id) == ["b", "a"])
    }

    @Test("a row's bar: how far in; none when played, not started or of unknown length")
    func progress() {
        #expect(CarPlayContent.progress(ListeningProgress(positionMs: 900_000, played: false), durationMs: 3_600_000) == 0.25)
        #expect(CarPlayContent.progress(ListeningProgress(positionMs: 900_000, played: true), durationMs: 3_600_000) == nil)
        #expect(CarPlayContent.progress(ListeningProgress(positionMs: 0, played: false), durationMs: 3_600_000) == nil)
        #expect(CarPlayContent.progress(ListeningProgress(positionMs: 900_000, played: false), durationMs: nil) == nil)
        #expect(CarPlayContent.progress(nil, durationMs: 3_600_000) == nil)
        #expect(CarPlayContent.progress(ListeningProgress(positionMs: 9_000_000, played: false), durationMs: 3_600_000) == 1)
    }

    @Test("the rate button goes 1× → 1.25× … 2× → 0.75× → 1×")
    func rates() {
        var rate: Float = 1
        var seen: [Float] = []
        for _ in 0..<6 {
            rate = CarPlayContent.nextRate(after: rate)
            seen.append(rate)
        }
        #expect(seen == [1.25, 1.5, 1.75, 2, 0.75, 1])
        #expect(CarPlayContent.nextRate(after: 2.5) == 0.75, "a speed set on the phone above 2× starts over")
    }

    @Test("a list: one section, its rows, at most 100, and the empty text")
    func listTemplate() {
        let items = (0..<120).map { CPListItem(text: "Row \($0)", detailText: nil) }
        let template = CarPlayContent.listTemplate(title: "New Episodes", items: items, emptyText: "No new episodes")
        #expect(template.title == "New Episodes")
        #expect(template.sections.count == 1)
        #expect(template.sections[0].items.count == CarPlayContent.maxItems)
        #expect(template.emptyViewTitleVariants == ["No new episodes"])
    }
}
