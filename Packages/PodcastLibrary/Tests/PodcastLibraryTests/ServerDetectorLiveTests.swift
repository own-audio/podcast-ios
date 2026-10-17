import Foundation
import Testing

@testable import PodcastLibrary

/// Each test server is recognised by its address alone.
@Suite("Server detection, live", .enabled(if: ProcessInfo.processInfo.environment["OWNAUDIO_HOST"] != nil))
struct ServerDetectorLiveTests {
    @Test("own.audio, Audiobookshelf and gPodder servers by their address")
    func live() async throws {
        let env = ProcessInfo.processInfo.environment
        let detector = ServerDetector()
        if let host = env["OWNAUDIO_HOST"] {
            #expect(await detector.detect(host) == .ownAudio(URL(string: host)!))
        }
        if let host = env["AUDIOBOOKSHELF_HOST"] {
            #expect(await detector.detect(host) == .audiobookshelf(URL(string: host)!))
        }
        for key in ["PODFETCH_HOST", "GPODDER_HOST"] {
            guard let host = env[key] else { continue }
            let found = await detector.detect(host)
            // own.audio speaks gPodder too and is recognised as itself.
            switch found {
            case .gpodder?, .ownAudio?: break
            default: Issue.record("\(key) not recognised: \(String(describing: found))")
            }
        }
    }
}
