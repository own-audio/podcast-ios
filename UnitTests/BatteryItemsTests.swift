import Foundation
import Testing
@testable import OwnAudioPodcasts

@Suite("Download progress to the screen")
struct DownloadProgressGateTests {
    final class Clock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 1_800_000_000) }

    @Test("at most twice a second per episode, and always the end")
    func throttle() {
        let clock = Clock()
        let gate = DownloadProgressGate(interval: 0.5, now: { clock.now })
        #expect(gate.shouldReport(id: "a", done: false))
        clock.now += 0.1
        #expect(!gate.shouldReport(id: "a", done: false))
        #expect(gate.shouldReport(id: "b", done: false), "each episode on its own")
        clock.now += 0.2
        #expect(!gate.shouldReport(id: "a", done: false))
        #expect(gate.shouldReport(id: "a", done: true), "the last bytes always")
        clock.now += 0.5
        #expect(gate.shouldReport(id: "a", done: false))
    }
}
