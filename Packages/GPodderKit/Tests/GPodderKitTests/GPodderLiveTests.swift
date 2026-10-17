import Foundation
import Testing

@testable import GPodderKit

/// Against a real gPodder server (podfetch, Nextcloud's gPodder Sync). Works on a device of its
/// own and removes the feed it adds; the episode action it sends stays in the account's history,
/// as the API has no way to delete one.
@Suite("gPodder, live", .serialized, .enabled(if: ProcessInfo.processInfo.environment["GPODDER_HOST"] != nil))
struct GPodderLiveTests {
    @Test("login, a device, a subscription added and removed, an episode action round trip")
    func live() async throws {
        let env = ProcessInfo.processInfo.environment
        let client = GPodderClient(host: try #require(URL(string: env["GPODDER_HOST"]!)), username: env["GPODDER_USERNAME"]!, password: env["GPODDER_PASSWORD"]!)
        try await client.login()
        let device = "own-audio-podcasts-test"
        try await client.registerDevice(id: device, caption: "own.audio Podcasts tests")
        let feed = "https://feeds.example.org/own-audio-test-\(UUID().uuidString.prefix(8)).xml"

        let start = try await client.subscriptionChanges(device: device, since: 0)
        let added = try await client.uploadSubscriptionChanges(device: device, add: [feed], remove: [])
        let afterAdd = try await client.subscriptionChanges(device: device, since: start.timestamp)
        #expect(afterAdd.add.contains(feed), "the feed added shows up as added")
        let removed = try await client.uploadSubscriptionChanges(device: device, add: [], remove: [feed])
        #expect(removed.timestamp >= added.timestamp)
        let all = try await client.subscriptionChanges(device: device, since: 0)
        #expect(!all.add.contains(feed), "and is gone once removed")

        let before = try await client.episodeActions(since: 0)
        let when = Date(timeIntervalSince1970: (Date().timeIntervalSince1970).rounded(.down))
        _ = try await client.uploadEpisodeActions([EpisodeAction(podcast: feed, episode: feed + "/1.mp3", action: .play, timestamp: when, started: 0, position: 42, total: 600, device: device)])
        let after = try await client.episodeActions(since: before.timestamp)
        let back = after.actions.first { $0.episode == feed + "/1.mp3" }
        #expect(back?.position == 42 && back?.action == .play)
    }

    @Test("a wrong password is refused")
    func wrongPassword() async throws {
        let env = ProcessInfo.processInfo.environment
        let client = GPodderClient(host: URL(string: env["GPODDER_HOST"]!)!, username: env["GPODDER_USERNAME"]!, password: "not-the-password")
        await #expect(throws: GPodderError.unauthorized) { try await client.login() }
    }
}
