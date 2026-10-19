import Foundation
import OwnAudioKit

/// A category to browse: its key (what the catalogue calls it) and how many shows sit in it,
/// where the catalogue counts them.
public struct CatalogueCategory: Sendable, Hashable, Identifiable {
    public var id: String { key }
    /// `news`, `society`… — a Podcast Index category (own.audio) or one of Apple's podcast
    /// genres under the same names (`AppleShowCatalogue.genres`). The app names it.
    public let key: String
    /// Shows that still publish, where the catalogue knows; nil for Apple's charts.
    public let showCount: Int?

    public init(key: String, showCount: Int? = nil) {
        self.key = key
        self.showCount = showCount
    }
}

/// Where Discover finds new shows. An own.audio server with the podcast catalogue knows millions
/// of shows by category and which are like which; without one, Apple's public directory gives
/// its charts per genre and its search, and nothing about similarity.
public protocol ShowCatalogue: Sendable {
    func categories() async throws -> [CatalogueCategory]
    /// A page of the category's shows from `offset`; an empty page is the end.
    func browse(_ category: CatalogueCategory, offset: Int) async throws -> [ShowSearchResult]
    func search(_ term: String) async throws -> [ShowSearchResult]
    /// Shows like the one at `feedURL`; nil when this catalogue can't tell.
    func similar(to feedURL: URL) async throws -> [ShowSearchResult]?
}

/// The podcast catalogue on an own.audio server (`/api/v1/podcasts/discover/*`). Nothing typed
/// or followed leaves the server; the server leaves out what the household already follows.
public struct OwnAudioShowCatalogue: ShowCatalogue {
    let client: OwnAudioClient

    public init(client: OwnAudioClient) {
        self.client = client
    }

    /// Whether this server has a catalogue at all: one without the metadata service answers an
    /// error, which hides Discover's own.audio part rather than showing it broken.
    public func isAvailable() async -> Bool {
        guard let categories = try? await client.catalogueCategories() else { return false }
        return !categories.isEmpty
    }

    public func categories() async throws -> [CatalogueCategory] {
        try await translating {
            try await client.catalogueCategories()
                .filter { ($0.activeCount ?? $0.feedCount) > 0 }
                .map { CatalogueCategory(key: $0.category, showCount: $0.activeCount ?? $0.feedCount) }
        }
    }

    public func browse(_ category: CatalogueCategory, offset: Int) async throws -> [ShowSearchResult] {
        try await translating { try await client.catalogueBrowse(category: category.key, offset: offset).compactMap(Self.result) }
    }

    public func search(_ term: String) async throws -> [ShowSearchResult] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        return try await translating { try await client.catalogueSearch(trimmed).compactMap(Self.result) }
    }

    public func similar(to feedURL: URL) async throws -> [ShowSearchResult]? {
        try await translating { try await client.catalogueSimilar(feedURL: feedURL).compactMap(Self.result) }
    }

    static func result(_ show: CatalogueShow) -> ShowSearchResult? {
        guard let feed = URL(string: show.feedUrl) else { return nil }
        return ShowSearchResult(
            title: show.title, author: show.author, feedURL: feed, imageURL: show.imageUrl.flatMap(URL.init(string:)),
            episodeCount: show.episodeCount, genre: show.categories?.first
        )
    }

    private func translating<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch let error as OwnAudioError {
            switch error {
            case .signedOut: throw SourceError.signInRejected
            case .network, .offline: throw SourceError.network
            default: throw SourceError.server(String(describing: error))
            }
        }
    }
}

/// Apple's public podcast directory: its top shows per genre in the listener's country, and its
/// search. No key and no account; the charts are Apple's own ranking. A chart names shows by
/// Apple id, so their feed addresses come from one lookup per page.
public struct AppleShowCatalogue: ShowCatalogue {
    private let session: URLSession
    private let country: String

    /// Apple's podcast genres, under the catalogue's category names where they match.
    public static let genres: [(key: String, appleId: Int)] = [
        ("news", 1489), ("society", 1324), ("comedy", 1303), ("education", 1304), ("business", 1321),
        ("history", 1487), ("science", 1533), ("technology", 1318), ("health", 1512), ("truecrime", 1488),
        ("culture", 1301), ("sports", 1545), ("kids", 1305), ("fiction", 1483), ("religion", 1314),
        ("leisure", 1502), ("music", 1310), ("tv", 1309), ("government", 1511),
    ]

    public init(session: URLSession = .shared, country: String? = Locale.current.region?.identifier) {
        self.session = session
        self.country = (country ?? "us").lowercased()
    }

    public func categories() async throws -> [CatalogueCategory] {
        Self.genres.map { CatalogueCategory(key: $0.key) }
    }

    /// Apple's chart is one page of 50.
    public func browse(_ category: CatalogueCategory, offset: Int) async throws -> [ShowSearchResult] {
        guard offset == 0, let genre = Self.genres.first(where: { $0.key == category.key })?.appleId else { return [] }
        let chart = URL(string: "https://itunes.apple.com/\(country)/rss/toppodcasts/limit=50/genre=\(genre)/json")!
        struct Chart: Decodable {
            struct Feed: Decodable {
                struct Entry: Decodable {
                    struct Identifier: Decodable {
                        struct Attributes: Decodable {
                            let id: String
                            enum CodingKeys: String, CodingKey { case id = "im:id" }
                        }
                        let attributes: Attributes
                    }
                    let id: Identifier
                }
                let entry: [Entry]?
            }
            let feed: Feed
        }
        let ids = try decode(Chart.self, from: await fetch(chart)).feed.entry?.map(\.id.attributes.id) ?? []
        guard !ids.isEmpty else { return [] }
        let lookup = URL(string: "https://itunes.apple.com/lookup?entity=podcast&country=\(country)&id=\(ids.joined(separator: ","))")!
        let found = try decode(LookupAnswer.self, from: await fetch(lookup)).results
        let byId = Dictionary(found.compactMap { item in item.collectionId.map { (String($0), item) } }, uniquingKeysWith: { first, _ in first })
        // In the chart's order; a show without a feed address can't be followed and is left out.
        return ids.compactMap { byId[$0]?.result }
    }

    public func search(_ term: String) async throws -> [ShowSearchResult] {
        try await ITunesShowSearch(session: session).search(term, country: country)
    }

    public func similar(to feedURL: URL) async throws -> [ShowSearchResult]? { nil }

    private struct LookupAnswer: Decodable {
        struct Item: Decodable {
            let collectionId: Int?
            let collectionName: String?
            let artistName: String?
            let feedUrl: String?
            let artworkUrl600: String?
            let artworkUrl100: String?
            let trackCount: Int?
            let primaryGenreName: String?

            var result: ShowSearchResult? {
                guard let title = collectionName, let feed = feedUrl.flatMap(URL.init(string:)) else { return nil }
                return ShowSearchResult(title: title, author: artistName, feedURL: feed, imageURL: (artworkUrl600 ?? artworkUrl100).flatMap(URL.init(string:)), episodeCount: trackCount, genre: primaryGenreName)
            }
        }
        let results: [Item]
    }

    private func fetch(_ url: URL) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw SourceError.network
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw SourceError.network }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw SourceError.server("unreadable directory answer")
        }
    }
}
