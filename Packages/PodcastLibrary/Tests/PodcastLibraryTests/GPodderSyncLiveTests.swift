import FeedKit
import Foundation
import GPodderKit
import Testing

@testable import PodcastLibrary

/// The sync against a real gPodder server (`GPODDER_*`): a show followed on the phone reaches
/// the account, a position goes up as a play action, a newer one from another device comes
/// down, and unfollowing removes the show again. Leaves the account as it found it, apart from
/// the actions, which the API keeps.
@Suite("gPodder sync, live", .serialized, .enabled(if: ProcessInfo.processInfo.environment["GPODDER_HOST"] != nil))
struct GPodderSyncLiveTests {
    @Test("subscriptions and positions both ways")
    func live() async throws {
        let env = ProcessInfo.processInfo.environment
        let client = GPodderClient(host: try #require(URL(string: env["GPODDER_HOST"]!)), username: env["GPODDER_USERNAME"]!, password: env["GPODDER_PASSWORD"]!)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gp-live-\(UUID().uuidString)", isDirectory: true)
        let library = FeedLibrary(directory: directory)
        let device = "own-audio-live-\(UUID().uuidString.prefix(6).lowercased())"
        let sync = GPodderSync(client: client, library: library, device: device, directory: directory)
        try await sync.register(caption: "own.audio Podcasts live test")

        let show = try await library.follow(feedURL: URL(string: "https://feeds.podcastindex.org/pc20.xml")!)
        let feed = try #require(show.feedURL?.absoluteString)
        defer { Task { _ = try? await client.uploadSubscriptionChanges(device: device, add: [], remove: [feed]) } }
        let first = try await sync.sync()
        #expect(first.uploadedShows >= 1)
        #expect(try await client.subscriptionChanges(device: device, since: 0).add.contains(feed), "the account has the show")

        let episode = try #require(try await library.episodes(showId: show.id).first)
        let key = episode.key
        try await library.record(positionMs: 61_000, for: key, at: Date().addingTimeInterval(-120))
        let pushed = try await sync.sync()
        #expect(pushed.positionsSent >= 1)
        let actions = try await client.episodeActions(since: 0).actions
        #expect(actions.contains { $0.episode == episode.audioURL?.absoluteString && $0.position == 61 && $0.device == device }, "the position went up")

        _ = try await client.uploadEpisodeActions([EpisodeAction(
            podcast: feed, episode: try #require(episode.audioURL?.absoluteString), action: .play,
            timestamp: Date().addingTimeInterval(-10), started: 0, position: 300, total: 3600, device: "laptop-test")])
        let pulled = try await sync.sync()
        #expect(pulled.positionsApplied >= 1)
        #expect(await library.progress(key)?.positionMs == 300_000, "another device's newer position came down")

        try await library.unfollow(showId: show.id)
        _ = try await sync.sync()
        let after = try await client.subscriptionChanges(device: device, since: 0)
        #expect(!after.add.contains(feed), "unfollowing on the phone removed it from the account")
    }
}
