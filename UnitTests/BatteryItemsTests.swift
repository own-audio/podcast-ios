import Foundation
import Testing
@testable import OwnAudioPodcasts

@Suite("Where an episode plays from")
struct EpisodeFileTests {
    private let downloaded = URL(fileURLWithPath: "/tmp/downloads/e.mp3")
    private let cached = URL(fileURLWithPath: "/tmp/listening-cache/e.mp3")

    @Test("the download first, then the listening cache, then the stream")
    func order() {
        #expect(AppModel.locate(downloaded: downloaded, cached: cached) == .downloaded(downloaded))
        #expect(AppModel.locate(downloaded: nil, cached: cached) == .cached(cached), "a cached episode no longer streams")
        #expect(AppModel.locate(downloaded: nil, cached: nil) == .stream)
    }
}

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
