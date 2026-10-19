import Foundation

/// A show in the server's catalogue (a self-hosted Podcast Index mirror), before anyone here
/// follows it.
public struct CatalogueShow: Decodable, Sendable, Equatable {
    public let title: String
    public let feedUrl: String
    public let link: String?
    public let description: String?
    public let author: String?
    public let imageUrl: String?
    public let language: String?
    public let episodeCount: Int?
    /// Podcast Index categories, lowercased; may be empty.
    public let categories: [String]?
}

/// A catalogue category and how many shows sit in it; `activeCount` counts the ones that still
/// publish, which is what a listener cares about.
public struct CatalogueCategoryCount: Decodable, Sendable, Equatable {
    public let category: String
    public let feedCount: Int
    public let activeCount: Int?
}

/// Podcast discovery: the catalogue's categories, the shows in one, search, and shows like a
/// given feed. Only `/api/v1` has these. They need the server's metadata service: a server
/// without one answers 500 (the open-source server out of the box), which the app reads as
/// "no catalogue here". Search, browse and similar leave out what the household already
/// follows, and nothing typed here leaves the server.
extension OwnAudioClient {
    private static let snake: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private func v1<T: Decodable>(_ method: String, _ path: String, query: [String: String?] = [:], body: (some Encodable)? = Optional<Empty>.none) async throws -> T {
        let data = try await raw(method, path, query: query, body: body, idempotencyKey: nil, api: "api/v1")
        return try Self.snake.decode(T.self, from: data)
    }

    public func catalogueCategories() async throws -> [CatalogueCategoryCount] {
        try await v1("GET", "/podcasts/discover/categories")
    }

    /// Up to 25 shows, from `offset`.
    public func catalogueBrowse(category: String, offset: Int = 0) async throws -> [CatalogueShow] {
        try await v1("GET", "/podcasts/discover/browse", query: ["category": category, "offset": String(offset)])
    }

    public func catalogueSearch(_ query: String) async throws -> [CatalogueShow] {
        struct Body: Encodable { let q: String }
        return try await v1("POST", "/podcasts/search", body: Body(q: query))
    }

    /// Shows like the one at `feedURL`; empty when the catalogue doesn't know it.
    public func catalogueSimilar(feedURL: URL) async throws -> [CatalogueShow] {
        try await v1("GET", "/podcasts/discover/similar", query: ["feed_url": feedURL.absoluteString])
    }
}
