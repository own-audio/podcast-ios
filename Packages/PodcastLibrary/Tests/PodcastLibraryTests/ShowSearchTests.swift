import Foundation
import Testing

@testable import PodcastLibrary

@Suite("iTunes show search")
struct ShowSearchTests {
    @Test("shows with a feed, once each, in the asked store")
    func search() async throws {
        let mock = await MockURLProtocol.makeStubbedSession { request in
            let query = request.url?.query ?? ""
            #expect(query.contains("media=podcast") && query.contains("term=radio%20wave") && query.contains("country=cz"))
            let body = """
            {"resultCount":3,"results":[
            {"collectionName":"Radio Wave","artistName":"Český rozhlas","feedUrl":"https://example.cz/wave.rss","artworkUrl600":"https://img.example/600.jpg","trackCount":120,"primaryGenreName":"Music"},
            {"collectionName":"Radio Wave","feedUrl":"https://example.cz/wave.rss"},
            {"collectionName":"Apple only"}]}
            """
            return .init(statusCode: 200, body: Data(body.utf8))
        }
        let results = try await ITunesShowSearch(session: mock.urlSession).search("radio wave", country: "CZ")
        #expect(results == [ShowSearchResult(title: "Radio Wave", author: "Český rozhlas", feedURL: URL(string: "https://example.cz/wave.rss")!, imageURL: URL(string: "https://img.example/600.jpg"), episodeCount: 120, genre: "Music")])
    }

    @Test("nothing typed asks nothing")
    func empty() async throws {
        #expect(try await ITunesShowSearch().search("  ").isEmpty)
    }
}
