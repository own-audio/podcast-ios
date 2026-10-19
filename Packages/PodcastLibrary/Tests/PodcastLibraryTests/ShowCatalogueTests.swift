import Foundation
import Testing

@testable import PodcastLibrary

@Suite("Apple's charts as a catalogue")
struct AppleShowCatalogueTests {
    @Test("a genre's chart in the country's store, in its order, with feed addresses from one lookup")
    func chart() async throws {
        let mock = await MockURLProtocol.makeStubbedSession { request in
            let url = request.url!.absoluteString
            if url.contains("/rss/toppodcasts/") {
                #expect(url.contains("itunes.apple.com/cz/rss/toppodcasts/limit=50/genre=1489/json"))
                let body = #"{"feed":{"entry":[{"id":{"attributes":{"im:id":"2"}}},{"id":{"attributes":{"im:id":"1"}}},{"id":{"attributes":{"im:id":"3"}}}]}}"#
                return .init(statusCode: 200, body: Data(body.utf8))
            }
            #expect(url.contains("lookup") && url.contains("id=2,1,3"))
            let body = """
            {"results":[
            {"collectionId":1,"collectionName":"One","feedUrl":"https://example.com/1.rss"},
            {"collectionId":2,"collectionName":"Two","artistName":"Host","feedUrl":"https://example.com/2.rss","artworkUrl600":"https://img.example/2.jpg"},
            {"collectionId":3,"collectionName":"Apple only"}]}
            """
            return .init(statusCode: 200, body: Data(body.utf8))
        }
        let catalogue = AppleShowCatalogue(session: mock.urlSession, country: "CZ")
        let shows = try await catalogue.browse(CatalogueCategory(key: "news"), offset: 0)
        #expect(shows.map(\.title) == ["Two", "One"], "the chart's order; no feed, no row")
        #expect(shows.first?.author == "Host")
        #expect(try await catalogue.browse(CatalogueCategory(key: "news"), offset: 50).isEmpty, "one page")
    }

    @Test("every genre is a category, and Apple knows no similar shows")
    func categories() async throws {
        let catalogue = AppleShowCatalogue(country: "us")
        #expect(try await catalogue.categories().count == AppleShowCatalogue.genres.count)
        #expect(try await catalogue.similar(to: URL(string: "https://example.com/feed")!) == nil)
    }
}
