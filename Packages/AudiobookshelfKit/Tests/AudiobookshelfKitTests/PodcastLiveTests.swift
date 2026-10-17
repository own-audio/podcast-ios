import Foundation
import Testing

@testable import AudiobookshelfKit

/// Podcast libraries on a real Audiobookshelf, with the same throwaway user as `LiveServerTests`.
/// Leaves the account as it found it: the episode's position is removed again.
@Suite("Live podcasts", .serialized, .enabled(if: LiveConfig.current != nil))
struct PodcastLiveTests {
    private func signedIn() async throws -> AudiobookshelfClient {
        let config = try #require(LiveConfig.current)
        let signIn = try await AudiobookshelfClient.signIn(host: config.host, username: config.username, password: config.password)
        return AudiobookshelfClient(host: config.host, tokens: TokenSession(signIn.tokens))
    }

    @Test("podcast libraries list their shows; a show opens with its episodes")
    func showsAndEpisodes() async throws {
        let client = try await signedIn()
        let libraries = try await client.podcastLibraries()
        try #require(!libraries.isEmpty, "the server needs a podcast library")
        #expect(libraries.allSatisfy { $0.mediaType == "podcast" })
        var withEpisodes: PodcastItem?
        for library in libraries {
            let shows = try await client.allPodcasts(libraryId: library.id)
            #expect(shows.allSatisfy { !$0.media.metadata.title.isEmpty })
            if withEpisodes == nil, let show = shows.first(where: { ($0.media.numEpisodes ?? 0) > 0 }) { withEpisodes = show }
        }
        let show = try await client.podcast(id: try #require(withEpisodes).id)
        let episodes = try #require(show.media.episodes)
        #expect(!episodes.isEmpty)
        #expect(episodes.allSatisfy { $0.audioFile?.ino != nil && $0.duration > 0 }, "every episode on the server has a file")
        await client.signOut()
    }

    @Test("an episode plays through a session, its position is written and removed")
    func playAndProgress() async throws {
        let client = try await signedIn()
        var found: (PodcastItem, PodcastEpisode)?
        for library in try await client.podcastLibraries() where found == nil {
            for item in try await client.allPodcasts(libraryId: library.id) where (item.media.numEpisodes ?? 0) > 0 {
                let show = try await client.podcast(id: item.id)
                if let episode = show.media.episodes?.first { found = (show, episode); break }
            }
        }
        let (show, episode) = try #require(found)
        let session = try await client.playEpisode(itemId: show.id, episodeId: episode.id, device: DeviceInfo(deviceId: "podcast-live-tests", clientName: "own.audio Podcasts tests", clientVersion: "0.1.0"))
        #expect(session.episodeId == episode.id && !session.audioTracks.isEmpty)
        try await client.syncSession(id: session.id, currentTime: 30, timeListened: 5, duration: episode.duration)
        try await client.closeSession(id: session.id, currentTime: 31, timeListened: 1, duration: episode.duration)
        try await client.updateEpisodeProgress(itemId: show.id, episodeId: episode.id, .init(currentTime: 120, duration: episode.duration, isFinished: false))
        let progress = try #require(try await client.episodeProgress(itemId: show.id, episodeId: episode.id))
        #expect(progress.currentTime == 120 && progress.episodeId == episode.id && !progress.isFinished)
        try await client.deleteProgress(progressId: progress.id)
        #expect(try await client.episodeProgress(itemId: show.id, episodeId: episode.id) == nil)
        await client.signOut()
    }

    @Test("the server searches the podcast directory")
    func search() async throws {
        let client = try await signedIn()
        let hits = try await client.searchPodcasts("darknet diaries")
        #expect(hits.contains { $0.title.localizedCaseInsensitiveContains("Darknet") && $0.feedUrl != nil })
        await client.signOut()
    }
}
