import Foundation
import Testing

@testable import PodcastLibrary

@Suite("UpNext")
struct UpNextTests {
    private func entry(_ id: String) -> UpNext.Entry {
        .init(id: id, source: "phone", episode: Episode(id: id, showId: "s", title: "Episode \(id)"), show: nil)
    }

    private func queue() -> UpNext {
        UpNext(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    @Test("Play Next goes first, Play Later last; nothing is queued twice")
    func order() {
        let up = queue()
        up.playLater(entry("a"))
        up.playLater(entry("b"))
        up.playNext(entry("c"))
        up.playLater(entry("a"))
        #expect(up.all.map(\.id) == ["c", "a", "b"])
        up.playNext(entry("b"))
        #expect(up.all.map(\.id) == ["b", "c", "a"])
    }

    @Test("taking the next drops the one that just played, wherever it was")
    func takeNext() {
        let up = queue()
        for id in ["a", "b", "c"] { up.playLater(entry(id)) }
        #expect(up.takeNext(after: "b")?.id == "a")
        #expect(up.all.map(\.id) == ["c"])
        #expect(up.takeNext(after: nil)?.id == "c")
        #expect(up.takeNext(after: nil) == nil)
    }

    @Test("reorder and remove, as a list's edit mode does")
    func edit() {
        let up = queue()
        for id in ["a", "b", "c", "d"] { up.playLater(entry(id)) }
        up.move(from: IndexSet(integer: 3), to: 0)
        #expect(up.all.map(\.id) == ["d", "a", "b", "c"])
        up.move(from: IndexSet(integer: 0), to: 4)
        #expect(up.all.map(\.id) == ["a", "b", "c", "d"])
        up.remove("b")
        up.removeAll { $0.id == "d" }
        #expect(up.all.map(\.id) == ["a", "c"])
    }

    @Test("it survives a restart")
    func persists() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        UpNext(directory: directory).playLater(entry("x"))
        #expect(UpNext(directory: directory).all.map(\.id) == ["x"])
    }
}
