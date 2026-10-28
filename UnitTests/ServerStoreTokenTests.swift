import AudiobookshelfKit
import Foundation
import OwnAudioKit
import Testing
@testable import OwnAudioPodcasts

@Suite("Saved tokens", .serialized)
struct ServerStoreTokenTests {
    @Test("saving a record loaded before a refresh keeps the rotated tokens; signing in again replaces them")
    func keepsRotatedTokens() async throws {
        let store = ServerStore(service: "audio.own.podcastplayer.tests.\(UUID().uuidString)")
        defer { Task { await store.clear() } }
        let first = OwnAudioKit.Tokens(accessToken: "a1", refreshToken: "first", expiresAt: Date(), scope: "")
        let second = OwnAudioKit.Tokens(accessToken: "a2", refreshToken: "second", expiresAt: Date(), scope: "")
        let fresh = OwnAudioKit.Tokens(accessToken: "a3", refreshToken: "fresh", expiresAt: Date(), scope: "")
        let loaded = ServerRecord(displayName: "own.audio", kind: .ownAudio, host: URL(string: "https://pods.example.com")!,
                                  username: "a@example.com", ownAudioTokens: first)
        try await store.add(loaded)
        await store.updateTokens(serverId: loaded.id, ownAudio: second)

        var renamed = loaded
        renamed.displayName = "Home"
        let saved = try await store.update(renamed)
        #expect(saved.ownAudioTokens?.refreshToken == "second")
        #expect(await store.loadAll().first?.displayName == "Home")
        #expect(await store.loadAll().first?.ownAudioTokens?.refreshToken == "second")

        var signedIn = loaded
        signedIn.ownAudioTokens = fresh
        try await store.update(signedIn, signIn: true)
        #expect(await store.loadAll().first?.ownAudioTokens?.refreshToken == "fresh")
    }
}
