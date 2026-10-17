import AudiobookshelfKit
import Foundation
import Testing

@testable import PodcastLibrary

/// The adapter against a real Audiobookshelf with podcast libraries, as the throwaway user of
/// the kit's live tests. Leaves the account's positions as it found them.
@Suite("Audiobookshelf podcasts, live", .serialized, .enabled(if: ProcessInfo.processInfo.environment["AUDIOBOOKSHELF_HOST"] != nil))
struct AudiobookshelfLiveTests {
    @Test("shows, New Episodes, a show's episodes, a playable server file, a position round trip")
    func live() async throws {
        let env = ProcessInfo.processInfo.environment
        let hostURL = try #require(URL(string: env["AUDIOBOOKSHELF_HOST"]!))
        let signIn = try await AudiobookshelfClient.signIn(host: hostURL, username: env["AUDIOBOOKSHELF_USERNAME"]!, password: env["AUDIOBOOKSHELF_PASSWORD"]!)
        let client = AudiobookshelfClient(host: hostURL, tokens: TokenSession(signIn.tokens))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("abs-live-\(UUID().uuidString)", isDirectory: true)
        let abs = AudiobookshelfPodcastSource(client: client, store: ListeningStore(directory: directory), canAddShows: signIn.user.permissions.upload)
        let shows = try await abs.shows()
        try #require(!shows.isEmpty)
        let inbox = try await abs.inbox(limit: 50)
        #expect(!inbox.isEmpty, "the recent episodes make New Episodes")
        let episode = try #require(inbox.first)
        let playback = try await abs.playback(episode.key)
        #expect(playback.isServerFile)
        var request = URLRequest(url: playback.url)
        request.setValue("bytes=0-100", forHTTPHeaderField: "Range")
        let (_, response) = try await URLSession.shared.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 206, "the server file answers a range")
        let before = try await client.episodeProgress(itemId: episode.showId, episodeId: episode.id)
        let saved = try await abs.saveProgress(ListeningProgress(positionMs: 61_000, played: false, updatedAt: Date()), for: episode.key)
        let server = try #require(try await client.episodeProgress(itemId: episode.showId, episodeId: episode.id))
        #expect(saved.positionMs == 61_000 && server.currentTime == 61)
        if let before {
            try await client.updateEpisodeProgress(itemId: episode.showId, episodeId: episode.id, .init(currentTime: before.currentTime, duration: before.duration, isFinished: before.isFinished))
        } else {
            try await client.deleteProgress(progressId: server.id)
        }
        await client.signOut()
    }
}
