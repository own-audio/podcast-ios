import Foundation
import OwnAudioKit
import Testing

@testable import PodcastLibrary

/// The own.audio adapter against a real server with podcasts (`OWNAUDIO_*`). Leaves the
/// account's positions as it found them.
@Suite("own.audio podcasts, live", .serialized, .enabled(if: ProcessInfo.processInfo.environment["OWNAUDIO_HOST"] != nil))
struct OwnAudioLiveTests {
    @Test("shows, a show's episodes, New Episodes, a signed stream, a position round trip")
    func live() async throws {
        let env = ProcessInfo.processInfo.environment
        let host = try #require(URL(string: env["OWNAUDIO_HOST"]!))
        let tokens = try await OwnAudioClient.signIn(host: host, email: env["OWNAUDIO_EMAIL"]!, password: env["OWNAUDIO_ACCOUNT_PASSWORD"]!, device: .init(name: "own.audio Podcasts live test"))
        let client = OwnAudioClient(host: host, tokens: TokenSession(tokens))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("oa-live-\(UUID().uuidString)", isDirectory: true)
        let source = OwnAudioPodcastSource(client: client, store: ListeningStore(directory: directory))
        #expect(!source.capabilities.contains(.addByURL), "v2 cannot follow yet")
        let shows = try await source.shows()
        try #require(!shows.isEmpty, "the server needs podcasts")
        let episodes = try await source.episodes(showId: shows[0].id)
        #expect(!episodes.isEmpty && episodes.allSatisfy { $0.showId == shows[0].id })
        let inbox = try await source.inbox(limit: 50)
        #expect(inbox.count >= 1 && inbox.count <= shows.count, "first sight: the newest episode of each show")
        let episode = try #require(inbox.first)
        let playback = try await source.playback(episode.key)
        var request = URLRequest(url: playback.url)
        request.setValue("bytes=0-100", forHTTPHeaderField: "Range")
        request.setValue("own.audio Podcasts tests", forHTTPHeaderField: "User-Agent")
        let (_, response) = try await URLSession.shared.data(for: request)
        #expect([200, 206].contains((response as? HTTPURLResponse)?.statusCode ?? 0), "the signed stream answers")
        let before = try await client.progress(.episode, id: episode.id)
        let saved = try await source.saveProgress(ListeningProgress(positionMs: 61_000, played: false, updatedAt: Date()), for: episode.key)
        #expect(saved.positionMs == 61_000)
        #expect(try await client.progress(.episode, id: episode.id)?.positionMs == 61_000)
        if let before {
            _ = try await client.saveProgress(.episode, id: episode.id, positionMs: before.positionMs, finished: before.finished)
        } else {
            try await client.deleteProgress(.episode, id: episode.id)
        }
        await client.signOut()
    }
}
