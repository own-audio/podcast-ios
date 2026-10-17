import Foundation

// Podcasts in `/api/v2`: the shows a household follows and their episodes, as the server keeps
// them. Following, adding by feed URL and refreshing are not in v2 yet.

public struct Podcast: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let credits: [Credit]?
    public let feedUrl: String?
    public let description: String?
    public let link: String?
    public let language: String?
    public let podcastGuid: String?
    public let categories: [String]?
    /// A link to the show's artwork.
    public let image: String?
    /// `private` or `family`.
    public let visibility: String?
    public let ownerId: String?
    public let lastRefreshedAt: Date?
}

public struct PodcastEpisode: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let podcastId: String
    public let guid: String?
    public let title: String
    public let description: String?
    public let publishedAt: Date?
    /// Often missing: the server has not read the file yet.
    public let durationMs: Int64?
    public let episodeNumber: Int?
    public let seasonNumber: Int?
    /// The publisher's enclosure.
    public let audioUrl: String?
    /// The server keeps a copy of the file.
    public let stored: Bool?
    public let sizeBytes: Int64?
    public let contentType: String?
    public let image: String?
    public let transcriptUrl: String?
    public let transcriptType: String?
    public let createdAt: Date?
}

extension OwnAudioClient {
    public func podcasts(cursor: String? = nil, limit: Int = 100) async throws -> Page<Podcast> {
        try await get("podcasts", query: ["cursor": cursor, "limit": String(limit)])
    }

    public func podcast(id: String) async throws -> Podcast {
        try await get("podcasts/\(id)")
    }

    /// Newest first.
    public func episodes(podcastId: String, cursor: String? = nil, limit: Int = 100) async throws -> Page<PodcastEpisode> {
        try await get("podcasts/\(podcastId)/episodes", query: ["cursor": cursor, "limit": String(limit)])
    }

    public func episode(id: String) async throws -> PodcastEpisode {
        try await get("episodes/\(id)")
    }

}
