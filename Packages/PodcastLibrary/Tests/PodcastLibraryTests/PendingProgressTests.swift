import Foundation
import Testing

@testable import PodcastLibrary

@Suite("PendingProgress")
struct PendingProgressTests {
    private func store() -> PendingProgress {
        PendingProgress(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + seconds) }

    @Test("one entry per episode; the newer position wins, an older one never replaces it")
    func merges() {
        let pending = store()
        pending.record(.init(id: "s/a", progress: .init(positionMs: 10_000, played: false, updatedAt: at(10))))
        pending.record(.init(id: "s/a", progress: .init(positionMs: 20_000, played: false, updatedAt: at(20))))
        pending.record(.init(id: "s/a", progress: .init(positionMs: 5_000, played: false, updatedAt: at(5))))
        #expect(pending.all().map(\.progress.positionMs) == [20_000])
    }

    @Test("oldest first; sent removes only what was sent, not a newer position recorded since")
    func sendOrder() {
        let pending = store()
        let first = PendingProgress.Entry(id: "s/b", progress: .init(positionMs: 1, played: false, updatedAt: at(30)))
        pending.record(first)
        pending.record(.init(id: "s/a", progress: .init(positionMs: 2, played: true, updatedAt: at(10))))
        #expect(pending.all().map(\.id) == ["s/a", "s/b"])
        pending.record(.init(id: "s/b", progress: .init(positionMs: 9, played: false, updatedAt: at(40))))
        pending.sent(first)
        #expect(pending.all().map(\.progress.positionMs) == [2, 9])
    }

    @Test("it survives a restart, and a removed server's entries go")
    func persists() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        PendingProgress(directory: directory).record(.init(id: "server1/x", progress: .init(positionMs: 7, played: false, updatedAt: at(1))))
        PendingProgress(directory: directory).record(.init(id: "server2/y", progress: .init(positionMs: 8, played: false, updatedAt: at(2))))
        let again = PendingProgress(directory: directory)
        #expect(again.all().count == 2)
        again.removeAll(prefix: "server1")
        #expect(again.all().map(\.id) == ["server2/y"])
    }
}
