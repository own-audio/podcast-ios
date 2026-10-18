import FeedKit
import Foundation

/// A show the listener follows. `id` is the app's own and never changes, though the feed may
/// move (`itunes:new-feed-url`) or the server rename it.
public struct Show: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var author: String?
    public var description: String?
    public var imageURL: URL?
    /// Where its episodes come from; nil for a show only a server knows.
    public var feedURL: URL?
    public var link: URL?
    public var categories: [String]
    /// Heard oldest first.
    public var isSerial: Bool
    public var isExplicit: Bool
    public var followedAt: Date
    public var refreshedAt: Date?
    public var settings: ShowSettings
    /// The part of the source it lives in, where a source has parts: an Audiobookshelf library.
    public var collection: String?

    public init(id: String, title: String, author: String? = nil, description: String? = nil, imageURL: URL? = nil, feedURL: URL? = nil, link: URL? = nil, categories: [String] = [], isSerial: Bool = false, isExplicit: Bool = false, followedAt: Date = Date(), refreshedAt: Date? = nil, settings: ShowSettings = ShowSettings(), collection: String? = nil) {
        self.id = id
        self.title = title
        self.author = author
        self.description = description
        self.imageURL = imageURL
        self.feedURL = feedURL
        self.link = link
        self.categories = categories
        self.isSerial = isSerial
        self.isExplicit = isExplicit
        self.followedAt = followedAt
        self.refreshedAt = refreshedAt
        self.settings = settings
        self.collection = collection
    }
}

/// What the listener chose for one show.
public struct ShowSettings: Codable, Sendable, Equatable {
    /// New episodes appear in New Episodes.
    public var inInbox = true
    /// New episodes go to the end of the queue as they arrive.
    public var autoQueue = false
    /// Seconds skipped at the start of every episode (an intro heard a hundred times).
    public var skipIntroSecs: Double = 0
    /// nil: the app's speed.
    public var speed: Float?

    public init(inInbox: Bool = true, autoQueue: Bool = false, skipIntroSecs: Double = 0, speed: Float? = nil) {
        self.inInbox = inInbox
        self.autoQueue = autoQueue
        self.skipIntroSecs = skipIntroSecs
        self.speed = speed
    }
}

public struct Episode: Codable, Sendable, Equatable, Identifiable {
    /// The feed's GUID (or what stands in for it), unique within its show.
    public var id: String
    public var showId: String
    public var title: String
    public var description: String?
    public var publishedAt: Date?
    public var durationMs: Int64?
    public var audioURL: URL?
    public var audioType: String?
    public var audioBytes: Int64?
    public var imageURL: URL?
    public var link: URL?
    public var season: Int?
    public var number: Int?
    /// `full`, `trailer`, `bonus`.
    public var kind: String?
    public var chaptersURL: URL?
    public var chapters: [Chapter]
    public var transcripts: [Transcript]
    /// When this phone first saw it: what decides whether it is new to the listener.
    public var firstSeenAt: Date

    /// The id the player and the downloads know it by: unique across shows.
    public var key: EpisodeKey { EpisodeKey(showId: showId, episodeId: id) }

    public init(id: String, showId: String, title: String, description: String? = nil, publishedAt: Date? = nil, durationMs: Int64? = nil, audioURL: URL? = nil, audioType: String? = nil, audioBytes: Int64? = nil, imageURL: URL? = nil, link: URL? = nil, season: Int? = nil, number: Int? = nil, kind: String? = nil, chaptersURL: URL? = nil, chapters: [Chapter] = [], transcripts: [Transcript] = [], firstSeenAt: Date = Date()) {
        self.id = id
        self.showId = showId
        self.title = title
        self.description = description
        self.publishedAt = publishedAt
        self.durationMs = durationMs
        self.audioURL = audioURL
        self.audioType = audioType
        self.audioBytes = audioBytes
        self.imageURL = imageURL
        self.link = link
        self.season = season
        self.number = number
        self.kind = kind
        self.chaptersURL = chaptersURL
        self.chapters = chapters
        self.transcripts = transcripts
        self.firstSeenAt = firstSeenAt
    }
}

/// An episode named across shows: `showId` and the feed's id together.
public struct EpisodeKey: Codable, Sendable, Hashable, CustomStringConvertible {
    public let showId: String
    public let episodeId: String

    public init(showId: String, episodeId: String) {
        self.showId = showId
        self.episodeId = episodeId
    }

    /// `<showId>|<episodeId>`; show ids are the app's own and never hold a `|`.
    public var description: String { "\(showId)|\(episodeId)" }

    public init?(_ text: String) {
        guard let bar = text.firstIndex(of: "|") else { return nil }
        showId = String(text[..<bar])
        episodeId = String(text[text.index(after: bar)...])
    }
}

public struct Chapter: Codable, Sendable, Equatable {
    public var startMs: Int64
    public var endMs: Int64?
    public var title: String
    public var url: URL?
    public var imageURL: URL?
    public var isInTableOfContents: Bool

    public init(startMs: Int64, endMs: Int64? = nil, title: String, url: URL? = nil, imageURL: URL? = nil, isInTableOfContents: Bool = true) {
        self.startMs = startMs
        self.endMs = endMs
        self.title = title
        self.url = url
        self.imageURL = imageURL
        self.isInTableOfContents = isInTableOfContents
    }
}

public struct Transcript: Codable, Sendable, Equatable {
    public var url: URL
    public var type: String
    public var language: String?
}

/// Where the listener is in an episode, and whether it is heard.
public struct ListeningProgress: Codable, Sendable, Equatable {
    public var positionMs: Int64
    public var played: Bool
    public var updatedAt: Date

    public init(positionMs: Int64, played: Bool, updatedAt: Date = Date()) {
        self.positionMs = positionMs
        self.played = played
        self.updatedAt = updatedAt
    }

    /// The end of an episode is often an outro or an ad: within the last 30 seconds, or past 98%,
    /// it counts as heard.
    public static func reachedEnd(positionMs: Int64, durationMs: Int64?) -> Bool {
        guard let duration = durationMs, duration > 0 else { return false }
        return duration - positionMs <= 30_000 || Double(positionMs) / Double(duration) >= 0.98
    }
}

extension Episode {
    /// The feed's episode as this library keeps it.
    init(_ feed: FeedEpisode, showId: String, firstSeenAt: Date) {
        self.init(
            id: feed.id, showId: showId, title: feed.title, description: feed.description, publishedAt: feed.publishedAt,
            durationMs: feed.durationMs, audioURL: feed.enclosure?.url, audioType: feed.enclosure?.type,
            audioBytes: feed.enclosure?.length.flatMap { $0 > 0 ? $0 : nil }, imageURL: feed.imageURL, link: feed.link,
            season: feed.season, number: feed.episode, kind: feed.episodeType, chaptersURL: feed.chaptersURL,
            chapters: feed.inlineChapters.map { Chapter(startMs: $0.startMs, endMs: $0.endMs, title: $0.title, url: $0.url, imageURL: $0.imageURL, isInTableOfContents: $0.isInTableOfContents) },
            transcripts: feed.transcripts.map { Transcript(url: $0.url, type: $0.type, language: $0.language) },
            firstSeenAt: firstSeenAt
        )
    }
}
