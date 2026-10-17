import Foundation
import Testing

@testable import FeedKit

@Suite("FeedFetcher")
struct FeedFetcherTests {
    private func fixtureData(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test("a fetch keeps the validators, the next one sends them and a 304 costs nothing")
    func conditional() async throws {
        let body = try fixtureData("itunes.xml")
        let mock = await MockURLProtocol.makeStubbedSession { request in
            if request.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"" {
                return .init(statusCode: 304, body: Data())
            }
            return .init(statusCode: 200, body: body, headers: ["ETag": "\"v1\"", "Last-Modified": "Fri, 16 Oct 2026 08:30:00 GMT", "Content-Type": "application/rss+xml"])
        }
        let fetcher = FeedFetcher(session: mock.urlSession)
        let url = URL(string: "https://example.com/workshop/feed.xml")!
        guard case .fetched(let document, let validators, let finalURL) = try await fetcher.fetch(url) else {
            Issue.record("the first fetch should bring the feed"); return
        }
        #expect(document.show.title == "The Workshop Hour" && document.episodes.count == 3)
        #expect(validators == .init(etag: "\"v1\"", lastModified: "Fri, 16 Oct 2026 08:30:00 GMT"))
        #expect(finalURL == url)
        #expect(try await fetcher.fetch(url, validators: validators) == .notModified)
        let sent = await mock.requestLog()
        #expect(sent.last?.value(forHTTPHeaderField: "If-Modified-Since") == "Fri, 16 Oct 2026 08:30:00 GMT")
        #expect(sent.allSatisfy { $0.value(forHTTPHeaderField: "User-Agent") == "own.audio Podcasts" })
    }

    @Test("errors say what went wrong: an HTTP status, an answer too large, an HTML page")
    func errors() async throws {
        let mock = await MockURLProtocol.makeStubbedSession { request in
            switch request.url?.lastPathComponent {
            case "gone": return .init(statusCode: 410, body: Data())
            case "huge": return .init(statusCode: 200, body: Data(count: 2048))
            default: return .init(statusCode: 200, body: Data("<!DOCTYPE html><html><body>Hi</body></html>".utf8))
            }
        }
        var fetcher = FeedFetcher(session: mock.urlSession)
        fetcher.maxBytes = 1024
        await #expect(throws: FeedError.http(410)) { try await fetcher.fetch(URL(string: "https://example.com/gone")!) }
        await #expect(throws: FeedError.tooLarge) { try await fetcher.fetch(URL(string: "https://example.com/huge")!) }
        await #expect(throws: FeedError.notAFeed) { try await fetcher.fetch(URL(string: "https://example.com/page")!) }
    }
}

/// Real feeds from the wild, named in `FEED_URLS` (space-separated): each parses, has a title
/// and episodes with enclosures. Not run by default; the fixtures cover the forms.
@Suite("Live feeds", .enabled(if: !(ProcessInfo.processInfo.environment["FEED_URLS"] ?? "").isEmpty))
struct LiveFeedTests {
    @Test("every listed feed parses into a show with playable episodes")
    func liveFeeds() async throws {
        let urls = (ProcessInfo.processInfo.environment["FEED_URLS"] ?? "").split(separator: " ").compactMap { URL(string: String($0)) }
        let fetcher = FeedFetcher()
        for url in urls {
            guard case .fetched(let document, _, _) = try await fetcher.fetch(url) else { Issue.record("\(url) answered 304 to a first fetch"); continue }
            #expect(!document.show.title.isEmpty, "\(url) has a title")
            let playable = document.episodes.filter { $0.enclosure != nil }
            #expect(!playable.isEmpty, "\(url) has episodes with audio")
            #expect(Set(document.episodes.map(\.id)).count == document.episodes.count, "\(url): episode ids are unique")
            if let chapters = playable.first(where: { $0.chaptersURL != nil })?.chaptersURL {
                let list = try await fetcher.chapters(chapters)
                #expect(!list.isEmpty, "\(chapters) holds chapters")
            }
            print("\(url.host() ?? ""): \(document.show.title) — \(playable.count) episodes, \(playable.compactMap(\.durationMs).count) with durations, \(playable.filter { $0.chaptersURL != nil || !$0.inlineChapters.isEmpty }.count) with chapters")
        }
    }
}
