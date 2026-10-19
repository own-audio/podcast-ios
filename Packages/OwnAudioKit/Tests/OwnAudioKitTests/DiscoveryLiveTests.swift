import Foundation
import Testing

@testable import OwnAudioKit

/// Discovery against a server with the podcast catalogue (`CATALOGUE_*`, scripts/test-servers.sh
/// passes them). Reads only, and signs out the session it made.
@Suite("Podcast catalogue, live", .serialized, .enabled(if: ProcessInfo.processInfo.environment["CATALOGUE_HOST"] != nil))
struct DiscoveryLiveTests {
    @Test("categories with counts, a category's shows, search, and shows like one of them")
    func live() async throws {
        let env = ProcessInfo.processInfo.environment
        let host = try #require(URL(string: env["CATALOGUE_HOST"]!))
        let tokens = try await OwnAudioClient.signIn(host: host, email: env["CATALOGUE_EMAIL"]!, password: env["CATALOGUE_PASSWORD"]!, device: .init(name: "own.audio Podcasts discovery test"))
        let client = OwnAudioClient(host: host, tokens: TokenSession(tokens))

        let categories = try await client.catalogueCategories()
        #expect(categories.count > 5)
        let first = try #require(categories.first)
        #expect(first.feedCount > 0)

        let shows = try await client.catalogueBrowse(category: first.category)
        #expect(!shows.isEmpty, "the biggest category has shows")
        #expect(shows.allSatisfy { URL(string: $0.feedUrl) != nil })

        let found = try await client.catalogueSearch("news")
        #expect(!found.isEmpty)

        let seed = try #require(URL(string: shows[0].feedUrl))
        let similar = try await client.catalogueSimilar(feedURL: seed)
        #expect(!similar.contains { $0.feedUrl == seed.absoluteString }, "not the show itself")

        try await client.revokeSession(id: try #require(try await client.sessions().first { $0.current }).id)
    }
}
