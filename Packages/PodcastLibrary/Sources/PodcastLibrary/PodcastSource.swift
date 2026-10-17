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
}
