import Foundation

/// What a source can do beyond listing shows and playing episodes; the screens hide the rest.
public struct Capabilities: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Follow a show by its feed URL.
    public static let addByURL = Capabilities(rawValue: 1 << 0)
    /// Search for shows through the source itself.
    public static let search = Capabilities(rawValue: 1 << 1)
    /// The source keeps episode files itself (Audiobookshelf, own.audio).
    public static let serverDownloads = Capabilities(rawValue: 1 << 2)
    /// A household that shares shows.
    public static let familySharing = Capabilities(rawValue: 1 << 3)
    /// Positions follow the listener between devices.
    public static let syncsProgress = Capabilities(rawValue: 1 << 4)
    /// Episodes translated on the server.
    public static let translation = Capabilities(rawValue: 1 << 5)
}

public enum SourceError: Error, Sendable, Equatable {
    case network
    case notFound
    case notAFeed
    case unsupported
    case signInRejected
    case server(String)
}

/// One place shows come from: the phone's own feeds, or a server. Every screen speaks to this.
public protocol PodcastSource: Sendable {
    var capabilities: Capabilities { get }

    func shows() async throws -> [Show]
    func episodes(showId: String) async throws -> [Episode]
    func episode(_ key: EpisodeKey) async throws -> Episode

    /// Follows the show at `feedURL`; returns it with its episodes fetched.
    func follow(feedURL: URL) async throws -> Show
    func unfollow(showId: String) async throws
    func updateSettings(_ settings: ShowSettings, showId: String) async throws

    /// Asks every show (or one) for new episodes; returns those that are new to the listener.
    func refresh(showId: String?) async throws -> [Episode]

    func progress(_ key: EpisodeKey) async throws -> ListeningProgress?
    func allProgress() async throws -> [EpisodeKey: ListeningProgress]
    /// What the source holds afterwards: a newer position from another device wins.
    func saveProgress(_ progress: ListeningProgress, for key: EpisodeKey) async throws -> ListeningProgress
    func markPlayed(_ key: EpisodeKey, _ played: Bool) async throws

    /// New Episodes, newest first.
    func inbox(limit: Int) async throws -> [Episode]
    func dismissFromInbox(_ keys: [EpisodeKey]) async throws
    func queue() async -> [EpisodeKey]
    func playNext(_ key: EpisodeKey) async throws
    func playLater(_ key: EpisodeKey) async throws
    func removeFromQueue(_ key: EpisodeKey) async throws
    func moveInQueue(from source: IndexSet, to destination: Int) async throws
    /// What plays after `current`: the queue's next, else the newest in New Episodes.
    func takeNext(after current: EpisodeKey?) async throws -> Episode?

    /// Where to play an episode from right now.
    func playback(_ key: EpisodeKey) async throws -> Playback
}

/// How to play one episode: a URL the player can open (a file on the source, or the
/// publisher's enclosure), and whether the source wants play sessions reported.
public struct Playback: Sendable, Equatable {
    public var url: URL
    /// The server's own copy rather than the publisher's.
    public var isServerFile: Bool
    /// An HLS playlist the server transcodes as it goes (a file the phone can't play as it is).
    public var isHLS: Bool

    public init(url: URL, isServerFile: Bool, isHLS: Bool = false) {
        self.url = url
        self.isServerFile = isServerFile
        self.isHLS = isHLS
    }
}

/// What AVPlayer plays as a file. Anything else (WebM, Ogg, Opus) needs a server to transcode it.
public enum PlayableAudio {
    public static let mimeTypes: Set<String> = [
        "audio/mpeg", "audio/mp3", "audio/mpeg3", "audio/x-mpeg", "audio/mp4", "audio/x-m4a", "audio/m4a", "audio/m4b", "audio/x-m4b",
        "audio/aac", "audio/x-aac", "audio/aacp", "audio/flac", "audio/x-flac", "audio/wav", "audio/x-wav", "audio/wave", "audio/aiff", "audio/x-aiff",
        "audio/x-caf", "video/mp4", "video/quicktime",
    ]

    /// nil (unknown) counts as playable: most feeds that say nothing send MP3.
    public static func isPlayable(_ mimeType: String?) -> Bool {
        guard let type = mimeType?.lowercased().split(separator: ";").first.map({ $0.trimmingCharacters(in: .whitespaces) }), !type.isEmpty else { return true }
        return mimeTypes.contains(type)
    }
}
