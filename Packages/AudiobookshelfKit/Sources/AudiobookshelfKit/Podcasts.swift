import Foundation

// Podcast libraries. A show is a library item whose media is a podcast; its episodes are the
// ones the server holds (downloaded from the feed, or found in the folder). A show with a
// `feedUrl` has more episodes in its feed than on the server.

public struct PodcastItem: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let libraryId: String
    public let addedAt: Int64
    public let updatedAt: Int64
    public let isMissing: Bool
    public let media: PodcastMedia

    enum CodingKeys: String, CodingKey { case id, libraryId, addedAt, updatedAt, isMissing, media }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        libraryId = try c.decode(String.self, forKey: .libraryId)
        addedAt = try c.decodeIfPresent(Int64.self, forKey: .addedAt) ?? 0
        updatedAt = try c.decodeIfPresent(Int64.self, forKey: .updatedAt) ?? 0
        isMissing = try c.decodeIfPresent(Bool.self, forKey: .isMissing) ?? false
        media = try c.decode(PodcastMedia.self, forKey: .media)
    }
}

public struct PodcastMedia: Decodable, Sendable, Equatable {
    public let metadata: PodcastMetadata
    public let coverPath: String?
    public let tags: [String]
    /// On lists; the detail carries `episodes`.
    public let numEpisodes: Int?
    public let episodes: [PodcastEpisode]?
    /// The server downloads new episodes by itself.
    public let autoDownloadEpisodes: Bool
    public let maxEpisodesToKeep: Int?

    enum CodingKeys: String, CodingKey { case metadata, coverPath, tags, numEpisodes, episodes, autoDownloadEpisodes, maxEpisodesToKeep }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        metadata = try c.decode(PodcastMetadata.self, forKey: .metadata)
        coverPath = try c.decodeIfPresent(String.self, forKey: .coverPath)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        numEpisodes = try c.decodeIfPresent(Int.self, forKey: .numEpisodes)
        episodes = try c.decodeIfPresent([PodcastEpisode].self, forKey: .episodes)
        autoDownloadEpisodes = try c.decodeIfPresent(Bool.self, forKey: .autoDownloadEpisodes) ?? false
        maxEpisodesToKeep = try c.decodeIfPresent(Int.self, forKey: .maxEpisodesToKeep)
    }
}

public struct PodcastMetadata: Decodable, Sendable, Equatable {
    public let title: String
    public let author: String?
    public let description: String?
    public let feedUrl: String?
    public let imageUrl: String?
    public let itunesPageUrl: String?
    public let language: String?
    public let explicit: Bool
    /// `episodic` or `serial`.
    public let type: String?
    public let genres: [String]

    enum CodingKeys: String, CodingKey { case title, author, description, feedUrl, imageUrl, itunesPageUrl, language, explicit, type, genres }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = Mojibake.repair(try c.decodeIfPresent(String.self, forKey: .title) ?? "")
        author = Mojibake.repair(try c.decodeIfPresent(String.self, forKey: .author))
        description = try c.decodeIfPresent(String.self, forKey: .description)
        feedUrl = try c.decodeIfPresent(String.self, forKey: .feedUrl)
        imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        itunesPageUrl = try c.decodeIfPresent(String.self, forKey: .itunesPageUrl)
        language = try c.decodeIfPresent(String.self, forKey: .language)
        explicit = try c.decodeIfPresent(Bool.self, forKey: .explicit) ?? false
        type = try c.decodeIfPresent(String.self, forKey: .type)
        genres = try c.decodeIfPresent([String].self, forKey: .genres) ?? []
    }
}

public struct PodcastEpisode: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let libraryItemId: String?
    public let title: String
    public let description: String?
    /// Milliseconds since 1970; servers that scanned a folder often have only a year.
    public let publishedAt: Int64?
    /// Seconds.
    public let duration: Double
    public let size: Int64?
    /// The feed's GUID, when the episode came from the feed.
    public let guid: String?
    public let season: String?
    public let episode: String?
    public let episodeType: String?
    public let enclosure: Enclosure?
    public let audioFile: AudioFile?
    public let chapters: [Chapter]
    public let addedAt: Int64?

    public struct Enclosure: Decodable, Sendable, Equatable {
        public let url: String
        public let type: String?
        public let length: String?
    }

    enum CodingKeys: String, CodingKey { case id, libraryItemId, title, description, publishedAt, duration, size, guid, season, episode, episodeType, enclosure, audioFile, chapters, addedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        libraryItemId = try c.decodeIfPresent(String.self, forKey: .libraryItemId)
        title = Mojibake.repair(try c.decodeIfPresent(String.self, forKey: .title) ?? "")
        description = try c.decodeIfPresent(String.self, forKey: .description)
        publishedAt = try c.decodeIfPresent(Int64.self, forKey: .publishedAt)
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        size = try c.decodeIfPresent(Int64.self, forKey: .size)
        guid = try c.decodeIfPresent(String.self, forKey: .guid)
        season = try c.decodeIfPresent(FlexibleID.self, forKey: .season)?.value
        episode = try c.decodeIfPresent(FlexibleID.self, forKey: .episode)?.value
        episodeType = try c.decodeIfPresent(String.self, forKey: .episodeType)
        enclosure = try c.decodeIfPresent(Enclosure.self, forKey: .enclosure)
        audioFile = try c.decodeIfPresent(AudioFile.self, forKey: .audioFile)
        chapters = try c.decodeIfPresent([Chapter].self, forKey: .chapters) ?? []
        addedAt = try c.decodeIfPresent(Int64.self, forKey: .addedAt)
    }
}

/// `GET /api/search/podcast`: the iTunes directory, asked through the server.
public struct PodcastSearchResult: Decodable, Sendable, Equatable {
    public let id: Int?
    public let title: String
    public let artistName: String?
    public let feedUrl: String?
    public let cover: String?
    public let genres: [String]?
}

extension AudiobookshelfClient {
    public func podcastLibraries() async throws -> [Library] {
        let answer: LibrariesAnswer = try await get("api/libraries")
        return answer.libraries.filter { $0.mediaType == "podcast" }
    }

    /// A page of shows, newest additions first by default.
    public func podcasts(libraryId: String, page: Int = 0, limit: Int = 200, sort: String = "media.metadata.title", descending: Bool = false) async throws -> Page<PodcastItem> {
        try await get("api/libraries/\(libraryId)/items", query: ["page": String(page), "limit": String(limit), "sort": sort, "desc": descending ? "1" : "0", "minified": "1"])
    }

    public func allPodcasts(libraryId: String) async throws -> [PodcastItem] {
        var out: [PodcastItem] = []
        var page = 0
        while true {
            let answer = try await podcasts(libraryId: libraryId, page: page)
            out += answer.results
            guard answer.hasMore, !answer.results.isEmpty else { return out }
            page += 1
        }
    }

    /// A show with its episodes.
    public func podcast(id: String) async throws -> PodcastItem {
        try await get("api/items/\(id)", query: ["expanded": "1"])
    }

    public func episodeProgress(itemId: String, episodeId: String) async throws -> MediaProgress? {
        do {
            return try await get("api/me/progress/\(itemId)/\(episodeId)")
        } catch AudiobookshelfError.http(404, _) {
            return nil
        }
    }

    public func updateEpisodeProgress(itemId: String, episodeId: String, _ update: ProgressUpdate) async throws {
        try await send("PATCH", "api/me/progress/\(itemId)/\(episodeId)", body: update)
    }

    /// A play session for one episode, so the server counts the listening.
    public func playEpisode(itemId: String, episodeId: String, device: DeviceInfo, supportedMimeTypes: [String] = ["audio/mpeg", "audio/mp4", "audio/x-m4a", "audio/aac", "audio/flac", "audio/wav", "audio/x-wav", "audio/aiff"]) async throws -> PlaybackSession {
        struct Body: Encodable {
            let deviceInfo: DeviceInfo
            let forceDirectPlay: Bool
            let forceTranscode: Bool
            let supportedMimeTypes: [String]
            let mediaPlayer: String
        }
        return try await call("POST", "api/items/\(itemId)/play/\(episodeId)", body: Body(deviceInfo: device, forceDirectPlay: false, forceTranscode: false, supportedMimeTypes: supportedMimeTypes, mediaPlayer: "AVPlayer"))
    }

    public func searchPodcasts(_ term: String) async throws -> [PodcastSearchResult] {
        try await get("api/search/podcast", query: ["term": term])
    }

    /// Subscribes the server to a feed, into `folder` of `library`. Needs an account that may
    /// upload; the server makes the show's folder and, with `autoDownload`, fetches new episodes.
    public func subscribe(feedURL: URL, title: String, libraryId: String, folder: Library.Folder, autoDownload: Bool = false) async throws -> PodcastItem {
        struct Body: Encodable {
            struct Media: Encodable {
                struct Metadata: Encodable { let title: String; let feedUrl: String }
                let metadata: Metadata
                let autoDownloadEpisodes: Bool
            }
            let path: String
            let folderId: String
            let libraryId: String
            let media: Media
        }
        let safe = title.replacingOccurrences(of: "[/\\\\:*?\"<>|]", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        let path = folder.fullPath.hasSuffix("/") ? folder.fullPath + safe : folder.fullPath + "/" + safe
        return try await call("POST", "api/podcasts", body: Body(path: path, folderId: folder.id, libraryId: libraryId, media: .init(metadata: .init(title: title, feedUrl: feedURL.absoluteString), autoDownloadEpisodes: autoDownload)))
    }
}

extension AudiobookshelfClient {
    struct RecentEpisodes: Decodable { let episodes: [PodcastEpisode] }

    /// The library's newest episodes across its shows, newest first — what New Episodes is
    /// built from without opening every show.
    public func recentEpisodes(libraryId: String, limit: Int = 50) async throws -> [PodcastEpisode] {
        let answer: RecentEpisodes = try await get("api/libraries/\(libraryId)/recent-episodes", query: ["limit": String(limit), "page": "0"])
        return answer.episodes
    }
}
