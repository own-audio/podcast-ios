import Foundation

/// Fetches a feed politely: with the validators from the last fetch, so an unchanged feed costs
/// a 304 and a few hundred bytes; following redirects and reporting where the feed ended up;
/// refusing anything over `maxBytes`, since a feed is text and a huge answer is a mistake.
public struct FeedFetcher: Sendable {
    public struct Validators: Sendable, Equatable, Codable {
        public var etag: String?
        public var lastModified: String?

        public init(etag: String? = nil, lastModified: String? = nil) {
            self.etag = etag
            self.lastModified = lastModified
        }
    }

    public enum Result: Sendable, Equatable {
        case notModified
        /// `finalURL` differs from the one asked for when the publisher redirected permanently.
        case fetched(FeedDocument, validators: Validators, finalURL: URL)
    }

    private let session: URLSession
    private let userAgent: String
    public var maxBytes: Int = 25 << 20

    public init(session: URLSession = .shared, userAgent: String = "own.audio Podcasts") {
        self.session = session
        self.userAgent = userAgent
    }

    public func fetch(_ url: URL, validators: Validators? = nil) async throws -> Result {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.9, */*;q=0.5", forHTTPHeaderField: "Accept")
        if let etag = validators?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let lastModified = validators?.lastModified { request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw FeedError.network
        }
        guard let http = response as? HTTPURLResponse else { throw FeedError.network }
        if http.statusCode == 304 { return .notModified }
        guard (200..<300).contains(http.statusCode) else { throw FeedError.http(http.statusCode) }
        guard data.count <= maxBytes else { throw FeedError.tooLarge }
        let document = try FeedParser.parse(data)
        let next = Validators(etag: http.value(forHTTPHeaderField: "ETag"), lastModified: http.value(forHTTPHeaderField: "Last-Modified"))
        return .fetched(document, validators: next, finalURL: http.url ?? url)
    }

    /// A chapters document named by `podcast:chapters`.
    public func chapters(_ url: URL) async throws -> [FeedChapter] {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw FeedError.network
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FeedError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try Chapters.parse(data)
    }
}
