import Foundation
import OwnAudioKit
import Testing

@testable import PodcastLibrary

/// The household and the devices of a real own.audio account (`OWNAUDIO_*`). Reads only, and
/// signs out the session it signed in with.
@Suite("own.audio household and devices, live", .serialized, .enabled(if: ProcessInfo.processInfo.environment["OWNAUDIO_HOST"] != nil))
struct HouseholdLiveTests {
    @Test("the household lists you first; the devices include this one; its session can be signed out")
    func live() async throws {
        let env = ProcessInfo.processInfo.environment
        let host = try #require(URL(string: env["OWNAUDIO_HOST"]!))
        let tokens = try await OwnAudioClient.signIn(host: host, email: env["OWNAUDIO_EMAIL"]!, password: env["OWNAUDIO_ACCOUNT_PASSWORD"]!, device: .init(name: "own.audio Podcasts household test"))
        let client = OwnAudioClient(host: host, tokens: TokenSession(tokens))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("oa-household-\(UUID().uuidString)", isDirectory: true)
        let source = OwnAudioPodcastSource(client: client, store: ListeningStore(directory: directory))

        let household = try await source.household()
        #expect(!household.name.isEmpty)
        #expect(household.members.first?.isMe == true, "you first")
        let storage = try await source.storage()
        #expect(storage.total >= storage.podcasts)
        _ = try await source.credit()

        let sessions = try await source.sessions()
        let mine = try #require(sessions.first { $0.isThisDevice }, "this session is marked")
        #expect(mine.name == "own.audio Podcasts household test")
        try await source.revokeSession(id: mine.id)
        await #expect(throws: (any Error).self) { try await source.sessions() }
    }

    @Test("a change on the server comes through the live stream")
    func liveChanges() async throws {
        let env = ProcessInfo.processInfo.environment
        let host = try #require(URL(string: env["OWNAUDIO_HOST"]!))
        let tokens = try await OwnAudioClient.signIn(host: host, email: env["OWNAUDIO_EMAIL"]!, password: env["OWNAUDIO_ACCOUNT_PASSWORD"]!, device: .init(name: "own.audio Podcasts events test"))
        let client = OwnAudioClient(host: host, tokens: TokenSession(tokens))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("oa-events-\(UUID().uuidString)", isDirectory: true)
        let source = OwnAudioPodcastSource(client: client, store: ListeningStore(directory: directory))
        let episode = try #require(try await source.inbox(limit: 5).first, "the server needs podcasts")
        let before = try await client.progress(.episode, id: episode.id)

        let heard = Task {
            for try await _ in source.libraryChanges() { return true }
            return false
        }
        try await Task.sleep(for: .seconds(2))
        _ = try await client.saveProgress(.episode, id: episode.id, positionMs: 4_000, finished: false)
        let timeout = Task { try await Task.sleep(for: .seconds(20)); heard.cancel() }
        let got = (try? await heard.value) ?? false
        timeout.cancel()
        #expect(got, "a library event within 20 seconds")

        if let before {
            _ = try await client.saveProgress(.episode, id: episode.id, positionMs: before.positionMs, finished: before.finished)
        } else {
            try await client.deleteProgress(.episode, id: episode.id)
        }
        let mine = try await source.sessions().first { $0.isThisDevice }
        if let mine { try await source.revokeSession(id: mine.id) }
    }
}
