import Foundation

/// A show found by searching, before anyone follows it.
public struct ShowSearchResult: Sendable, Equatable, Identifiable, Hashable {
    public var id: String { feedURL.absoluteString }
    public var title: String
    public var author: String?
    public var feedURL: URL
    public var imageURL: URL?
    public var episodeCount: Int?
    public var genre: String?

    public init(title: String, author: String? = nil, feedURL: URL, imageURL: URL? = nil, episodeCount: Int? = nil, genre: String? = nil) {
        self.title = title
        self.author = author
        self.feedURL = feedURL
        self.imageURL = imageURL
        self.episodeCount = episodeCount
        self.genre = genre
    }
}

/// Apple's public iTunes Search: no key and no account, and it knows nearly every show, with
/// the feed URL in each answer. The listener's own Podcast Index key comes in P9.
public struct ITunesShowSearch: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// `country` is the store to search, by default the phone's region: a Czech show is found in
    /// the Czech store first.
    public func search(_ term: String, country: String? = Locale.current.region?.identifier, limit: Int = 30) async throws -> [ShowSearchResult] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "media", value: "podcast"),
            URLQueryItem(name: "entity", value: "podcast"),
            URLQueryItem(name: "term", value: trimmed),
            URLQueryItem(name: "limit", value: String(limit)),
        ] + (country.map { [URLQueryItem(name: "country", value: $0.lowercased())] } ?? [])
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(from: components.url!)
        } catch {
            throw SourceError.network
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw SourceError.network }
        struct Answer: Decodable {
            struct Item: Decodable {
                let collectionName: String?
                let artistName: String?
                let feedUrl: String?
                let artworkUrl600: String?
                let artworkUrl100: String?
                let trackCount: Int?
                let primaryGenreName: String?
            }
            let results: [Item]
        }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: data) else { throw SourceError.server("unreadable search answer") }
        var seen = Set<String>()
        // A show without a feed URL (Apple-exclusive, or withdrawn) can't be followed; it is left out.
        return answer.results.compactMap { item in
            guard let feed = item.feedUrl.flatMap(URL.init(string:)), let title = item.collectionName, seen.insert(feed.absoluteString).inserted else { return nil }
            return ShowSearchResult(title: title, author: item.artistName, feedURL: feed, imageURL: (item.artworkUrl600 ?? item.artworkUrl100).flatMap(URL.init(string:)), episodeCount: item.trackCount, genre: item.primaryGenreName)
        }
    }
}
