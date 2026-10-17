import Foundation

/// A podcast feed as the app needs it: the show and its episodes, every field optional except
/// what a feed cannot be without. Times are milliseconds.
public struct FeedDocument: Sendable, Equatable {
    public var show: FeedShow
    public var episodes: [FeedEpisode]

    public init(show: FeedShow, episodes: [FeedEpisode]) {
        self.show = show
        self.episodes = episodes
    }
}

public struct FeedShow: Sendable, Equatable {
    public var title: String
    public var author: String?
    /// Plain text with paragraphs kept; `descriptionHTML` holds what the feed sent.
    public var description: String?
    public var descriptionHTML: String?
    public var link: URL?
    public var imageURL: URL?
    public var language: String?
    public var categories: [String] = []
    public var isExplicit = false
    /// `serial` shows are heard oldest first; `episodic` (the default) newest first.
    public var isSerial = false
    /// `itunes:new-feed-url`: the publisher moved the feed; follow it.
    public var newFeedURL: URL?
    /// `itunes:complete`: no more episodes will come.
    public var isComplete = false
    /// `podcast:guid`, the show's identity across feed moves.
    public var podcastGUID: String?
    public var funding: [FeedLink] = []
    public var lastBuildDate: Date?

    public init(title: String) {
        self.title = title
    }
}

public struct FeedEpisode: Sendable, Equatable, Identifiable {
    /// The `guid`, or the enclosure URL where the feed gives none — what identifies the
    /// episode from one fetch to the next.
    public var id: String
    public var title: String
    public var description: String?
    public var descriptionHTML: String?
    public var publishedAt: Date?
    public var durationMs: Int64?
    public var enclosure: FeedEnclosure?
    public var link: URL?
    public var imageURL: URL?
    public var season: Int?
    public var episode: Int?
    /// `full`, `trailer` or `bonus`.
    public var episodeType: String?
    public var isExplicit = false
    /// A Podcasting 2.0 chapters document to fetch (`podcast:chapters`).
    public var chaptersURL: URL?
    /// Podlove Simple Chapters, given inline in the feed.
    public var inlineChapters: [FeedChapter] = []
    public var transcripts: [FeedTranscript] = []
    public var persons: [FeedPerson] = []

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public struct FeedEnclosure: Sendable, Equatable {
    public var url: URL
    public var type: String?
    /// Bytes, where the feed says (often 0 or wrong).
    public var length: Int64?

    public init(url: URL, type: String? = nil, length: Int64? = nil) {
        self.url = url
        self.type = type
        self.length = length
    }
}

public struct FeedChapter: Sendable, Equatable {
    public var startMs: Int64
    public var endMs: Int64?
    public var title: String
    public var url: URL?
    public var imageURL: URL?
    /// Podcasting 2.0's `toc: false` marks a chapter that is only an image or link change.
    public var isInTableOfContents = true

    public init(startMs: Int64, endMs: Int64? = nil, title: String, url: URL? = nil, imageURL: URL? = nil, isInTableOfContents: Bool = true) {
        self.startMs = startMs
        self.endMs = endMs
        self.title = title
        self.url = url
        self.imageURL = imageURL
        self.isInTableOfContents = isInTableOfContents
    }
}

public struct FeedTranscript: Sendable, Equatable {
    public var url: URL
    /// `text/vtt`, `application/x-subrip`, `application/json`, `text/html`, `text/plain`.
    public var type: String
    public var language: String?
}

public struct FeedPerson: Sendable, Equatable {
    public var name: String
    /// `host`, `guest`, … (Podcasting 2.0's taxonomy); `host` when the feed says nothing.
    public var role: String
    public var imageURL: URL?
    public var link: URL?
}

public struct FeedLink: Sendable, Equatable {
    public var url: URL
    public var title: String?
}
