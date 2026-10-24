import Foundation
import PodcastLibrary
import SpokenEngine
import Testing
@testable import OwnAudioPodcasts

@MainActor
@Suite("Storing and sending positions")
struct PositionReporterTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func value(_ seconds: Int, played: Bool = false) -> ListeningProgress {
        ListeningProgress(positionMs: Int64(seconds) * 1000, played: played, updatedAt: start.addingTimeInterval(TimeInterval(seconds)))
    }

    /// A reporter whose stores are listed, as (episode, seconds).
    private func reporter() -> (PositionReporter, () -> [(String, Int64)]) {
        final class Box { var stored: [(String, Int64)] = [] }
        let box = Box()
        let reporter = PositionReporter { id, value in box.stored.append((id, value.positionMs / 1000)) }
        return (reporter, { box.stored })
    }

    @Test("while playing: the first tick, then once a minute, not every ten seconds")
    func cadence() {
        let (reporter, stored) = reporter()
        for second in stride(from: 10, through: 130, by: 10) {
            reporter.report(value(second), for: "a", reason: .periodic)
        }
        #expect(stored().map(\.1) == [10, 70, 130])
        #expect(reporter.unflushed == nil)
        reporter.report(value(140), for: "a", reason: .periodic)
        #expect(reporter.unflushed?.value.positionMs == 140_000, "held back, in memory")
    }

    @Test("a chapter change is listening on, not a reason to send")
    func chapter() {
        let (reporter, stored) = reporter()
        reporter.report(value(10), for: "a", reason: .periodic)
        reporter.report(value(20), for: "a", reason: .chapter)
        #expect(stored().map(\.1) == [10])
    }

    @Test("pause, seek, stop and the end store at once", arguments: [SpokenEngine.TickReason.pause, .seek, .stop, .finished, .teardown])
    func immediate(reason: SpokenEngine.TickReason) {
        let (reporter, stored) = reporter()
        reporter.report(value(10), for: "a", reason: .periodic)
        reporter.report(value(20), for: "a", reason: .periodic)
        reporter.report(value(25), for: "a", reason: reason)
        #expect(stored().map(\.1) == [10, 25])
        #expect(reporter.unflushed == nil)
    }

    @Test("reaching the end stores at once, whatever the reason")
    func played() {
        let (reporter, stored) = reporter()
        reporter.report(value(10), for: "a", reason: .periodic)
        reporter.report(value(20, played: true), for: "a", reason: .periodic)
        #expect(stored().map(\.1) == [10, 20])
    }

    @Test("another episode: the old one's held-back position first, then the new one's")
    func episodeChange() {
        let (reporter, stored) = reporter()
        reporter.report(value(10), for: "a", reason: .periodic)
        reporter.report(value(30), for: "a", reason: .periodic)
        reporter.report(value(40), for: "b", reason: .periodic)
        #expect(stored().map { "\($0.0)\($0.1)" } == ["a10", "a30", "b40"])
    }

    @Test("going to the background stores what was held back; nothing twice")
    func flush() {
        let (reporter, stored) = reporter()
        reporter.report(value(10), for: "a", reason: .periodic)
        reporter.report(value(20), for: "a", reason: .periodic)
        reporter.flush()
        reporter.flush()
        #expect(stored().map(\.1) == [10, 20])
    }

    // MARK: - Offline and a dead server

    private func pendingStore() -> PendingProgress {
        PendingProgress(directory: FileManager.default.temporaryDirectory.appendingPathComponent("pending-\(UUID().uuidString)", isDirectory: true))
    }

    @Test("offline, the position waits on disk and nothing is sent")
    func offline() async {
        let pending = pendingStore()
        let task = AppModel.send(value(30), for: "server/s|e", pending: pending, offline: true) { _ in Issue.record("sent while offline") }
        #expect(task == nil)
        #expect(pending.all().map(\.progress.positionMs) == [30_000])
    }

    @Test("a dead server keeps the position on disk; a live one takes it off")
    func deadServer() async {
        struct Down: Error {}
        let pending = pendingStore()
        await AppModel.send(value(30), for: "server/s|e", pending: pending, offline: false) { _ in throw Down() }?.value
        #expect(pending.all().map(\.progress.positionMs) == [30_000], "kept for the next refresh")
        await AppModel.send(value(90), for: "server/s|e", pending: pending, offline: false) { _ in }?.value
        #expect(pending.all().isEmpty)
    }

    @Test("throttled positions for a dead server: the minute's report and the pause wait on disk")
    func throttledDeadServer() async {
        struct Down: Error {}
        let pending = pendingStore()
        var tasks: [Task<Void, Never>] = []
        let reporter = PositionReporter { id, value in
            if let task = AppModel.send(value, for: id, pending: pending, offline: false, save: { _ in throw Down() }) { tasks.append(task) }
        }
        for second in stride(from: 10, through: 50, by: 10) { reporter.report(value(second), for: "server/s|e", reason: .periodic) }
        reporter.report(value(55), for: "server/s|e", reason: .pause)
        for task in tasks { await task.value }
        #expect(tasks.count == 2, "one request for the first tick, one for the pause")
        #expect(pending.all().map(\.progress.positionMs) == [55_000], "the newest is on disk")
    }
}
