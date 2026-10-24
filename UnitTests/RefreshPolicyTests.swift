import Foundation
import Testing
@testable import OwnAudioPodcasts

@Suite("When a full refresh runs")
struct RefreshPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("the first automatic refresh runs; the next waits fifteen minutes")
    func interval() {
        #expect(RefreshPolicy.shouldRun(.automatic, lastRun: nil, now: now, inBackground: false, isPlaying: false))
        #expect(!RefreshPolicy.shouldRun(.automatic, lastRun: now.addingTimeInterval(-60), now: now, inBackground: false, isPlaying: false),
                "back from Control Center a minute later: nothing")
        #expect(!RefreshPolicy.shouldRun(.automatic, lastRun: now.addingTimeInterval(-14 * 60 - 59), now: now, inBackground: false, isPlaying: false))
        #expect(RefreshPolicy.shouldRun(.automatic, lastRun: now.addingTimeInterval(-15 * 60), now: now, inBackground: false, isPlaying: false))
    }

    @Test("a pull to refresh always runs, also right after another and in the background")
    func asked() {
        #expect(RefreshPolicy.shouldRun(.asked, lastRun: now, now: now, inBackground: false, isPlaying: false))
        #expect(RefreshPolicy.shouldRun(.asked, lastRun: now, now: now, inBackground: true, isPlaying: true))
    }

    @Test("in the background while an episode plays, the app doesn't refresh by itself")
    func backgroundWhilePlaying() {
        #expect(!RefreshPolicy.shouldRun(.automatic, lastRun: nil, now: now, inBackground: true, isPlaying: true))
        #expect(RefreshPolicy.shouldRun(.automatic, lastRun: nil, now: now, inBackground: true, isPlaying: false), "paused in the background: the background task may")
        #expect(RefreshPolicy.shouldRun(.automatic, lastRun: nil, now: now, inBackground: false, isPlaying: true), "on screen while playing: yes")
    }

    @Test("only a refresh the listener asked for skips the sources' own caches")
    func force() {
        #expect(RefreshPolicy.forcesFeeds(.asked))
        #expect(!RefreshPolicy.forcesFeeds(.automatic))
    }
}
