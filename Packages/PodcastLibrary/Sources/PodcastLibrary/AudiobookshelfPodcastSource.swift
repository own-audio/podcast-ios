import AudiobookshelfKit
import FeedKit
import Foundation

/// An Audiobookshelf server's podcast libraries. A show's episodes are the ones the server
/// holds; for a show with a feed, the feed's other episodes are listed too, played from the
/// publisher, their positions kept on the phone (the server has nowhere to put them). New
/// Episodes comes from each library's recent episodes, one request per library.
///
/// Subscribing needs an account that may upload; without that the app can browse, play and
/// sync positions, and adding shows is hidden.
public actor AudiobookshelfPodcastSource: PodcastSource {
    public let client: AudiobookshelfClient
    private let store: ListeningStore
    private let fetcher: FeedFetcher
    private let canAddShows: Bool
    private let now: @Sendable () -> Date

    /// Feeds fetched this session, by show: validators for the next conditional fetch, the
    /// episodes only the feed has, and when it was asked.
    private struct FeedCache {
        var validators: FeedFetcher.Validators?
        var feedOnly: [Episode]
        var fetchedAt: Date
    }
    private var feeds: [String: FeedCache] = [:]
    private var items: [String: PodcastItem] = [:]

    public nonisolated var capabilities: Capabilities {
        canAddShows ? [.search, .syncsProgress, .serverDownloads, .addByURL] : [.search, .syncsProgress, .serverDownloads]
    }

    /// Feed-only episodes carry this before the feed's own id, so a key says which kind it is.
    static let feedPrefix = "feed:"

    /// This phone, as play sessions name it.
    private let device: DeviceInfo

    public init(client: AudiobookshelfClient, store: ListeningStore, fetcher: FeedFetcher = FeedFetcher(), canAddShows: Bool,
                device: DeviceInfo = DeviceInfo(deviceId: "own-audio-podcasts", clientName: "own.audio Podcasts", clientVersion: "1"),
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.device = device
        self.client = client
        self.store = store
        self.fetcher = fetcher
        self.canAddShows = canAddShows
        self.now = now
    }

    // MARK: - Shows and episodes

    public func shows() async throws -> [Show] {
        var out: [Show] = []
        for library in try await translating({ try await client.podcastLibraries() }) {
            for item in try await translating({ try await client.allPodcasts(libraryId: library.id) }) where !item.isMissing {
                items[item.id] = items[item.id] ?? item
                out.append(await show(item))
            }
        }
        return out.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    public func episodes(showId: String) async throws -> [Episode] {
        let item = try await translating { try await client.podcast(id: showId) }
        items[showId] = item
        var episodes = (item.media.episodes ?? []).map { episode($0, showId: showId) }
        episodes += await feedOnlyEpisodes(item, serverEpisodes: item.media.episodes ?? [])
        let observed = await store.observe(episodes, showId: showId)
        return FeedLibrary.ordered(observed, serial: item.media.metadata.type == "serial")
    }

    public func episode(_ key: EpisodeKey) async throws -> Episode {
        if let known = feeds[key.showId]?.feedOnly.first(where: { $0.id == key.episodeId }) { return known }
        guard let found = try await episodes(showId: key.showId).first(where: { $0.id == key.episodeId }) else { throw SourceError.notFound }
        return found
    }

    /// The feed's episodes the server doesn't hold, matched by GUID, then enclosure URL, then
    /// title. Fetched at most every ten minutes per show, conditionally; a feed that fails
    /// leaves the server's episodes alone.
    private func feedOnlyEpisodes(_ item: PodcastItem, serverEpisodes: [PodcastEpisode], force: Bool = false) async -> [Episode] {
        guard let feedURL = FeedValues.url(item.media.metadata.feedUrl) else { return [] }
        let cached = feeds[item.id]
        if !force, let cached, now().timeIntervalSince(cached.fetchedAt) < 600 { return cached.feedOnly }
        guard let result = try? await fetcher.fetch(feedURL, validators: cached?.validators) else { return cached?.feedOnly ?? [] }
        guard case .fetched(let document, let validators, _) = result else {
            feeds[item.id]?.fetchedAt = now()
            return cached?.feedOnly ?? []
        }
        let guids = Set(serverEpisodes.compactMap(\.guid))
        let enclosures = Set(serverEpisodes.compactMap { $0.enclosure?.url })
        let titles = Set(serverEpisodes.map { $0.title.lowercased() })
        let feedOnly = document.episodes.filter { feed in
            guard let enclosure = feed.enclosure else { return false }
            return !guids.contains(feed.id) && !enclosures.contains(enclosure.url.absoluteString) && !titles.contains(feed.title.lowercased())
        }.map { feed -> Episode in
            var episode = Episode(feed, showId: item.id, firstSeenAt: now())
            episode.id = Self.feedPrefix + feed.id
            return episode
        }
        feeds[item.id] = FeedCache(validators: validators, feedOnly: feedOnly, fetchedAt: now())
        return feedOnly
    }

    // MARK: - Following

    public func follow(feedURL: URL) async throws -> Show {
        guard canAddShows else { throw SourceError.unsupported }
        if let existing = try await shows().first(where: { $0.feedURL == feedURL }) { return existing }
        guard let library = try await translating({ try await client.podcastLibraries() }).first(where: { !($0.folders ?? []).isEmpty }),
              let folder = library.folders?.first else { throw SourceError.unsupported }
        let title: String
        switch try? await fetcher.fetch(feedURL) {
        case .fetched(let document, _, _): title = document.show.title
        default: throw SourceError.notAFeed
        }
        let item = try await translating { try await client.subscribe(feedURL: feedURL, title: title, libraryId: library.id, folder: folder) }
        items[item.id] = item
        return await show(item)
    }

    /// Removing a show deletes it, and its files, on the server for everyone: not done from a
    /// player.
    public func unfollow(showId: String) async throws {
        throw SourceError.unsupported
    }

    public func updateSettings(_ settings: ShowSettings, showId: String) async throws {
        try await store.setSettings(settings, showId: showId)
    }

    /// The feeds of one show, or of every show with a feed, asked again; returns the episodes
    /// first seen now.
    public func refresh(showId: String?) async throws -> [Episode] {
        let started = now()
        var shows: [PodcastItem]
        if let showId {
            shows = [try await translating { try await client.podcast(id: showId) }]
        } else {
            _ = try await self.shows()
            shows = items.values.filter { $0.media.metadata.feedUrl != nil }
        }
        var fresh: [Episode] = []
        for item in shows {
            let serverEpisodes = showId == nil ? [] : (item.media.episodes ?? [])
            let feedOnly = await feedOnlyEpisodes(item, serverEpisodes: serverEpisodes, force: true)
            let server = serverEpisodes.map { episode($0, showId: item.id) }
            fresh += await store.observe(server + feedOnly, showId: item.id).filter { $0.firstSeenAt >= started }
        }
        _ = try await inbox(limit: 200)
        return fresh
    }

    // MARK: - New Episodes and the queue

    public func inbox(limit: Int) async throws -> [Episode] {
        var candidates: [Episode] = []
        for library in try await translating({ try await client.podcastLibraries() }) {
            let recent = try await translating { try await client.recentEpisodes(libraryId: library.id, limit: 100) }
            let byShow = Dictionary(grouping: recent, by: { $0.libraryItemId ?? "" })
            for (showId, episodes) in byShow where !showId.isEmpty {
                candidates += await store.observe(episodes.map { episode($0, showId: showId) }, showId: showId)
            }
        }
        for (showId, cache) in feeds {
            candidates += await store.observe(cache.feedOnly, showId: showId)
        }
        var inbox: [Episode] = []
        for episode in candidates where await store.isInInbox(episode) { inbox.append(episode) }
        inbox.sort { ($0.publishedAt ?? $0.firstSeenAt) > ($1.publishedAt ?? $1.firstSeenAt) }
        return Array(inbox.prefix(limit))
    }

    public func dismissFromInbox(_ keys: [EpisodeKey]) async throws { try await store.dismiss(keys) }
    public func queue() async -> [EpisodeKey] { await store.queue() }
    public func playNext(_ key: EpisodeKey) async throws { try await store.playNext(key) }
    public func playLater(_ key: EpisodeKey) async throws { try await store.playLater(key) }
    public func removeFromQueue(_ key: EpisodeKey) async throws { try await store.removeFromQueue(key) }
    public func moveInQueue(from source: IndexSet, to destination: Int) async throws { try await store.moveInQueue(from: source, to: destination) }

    public func takeNext(after current: EpisodeKey?) async throws -> Episode? {
        while let head = try await store.popQueue(after: current) {
            if let episode = try? await episode(head) { return episode }
        }
        return try await inbox(limit: 20).first { $0.key != current }
    }

    // MARK: - Positions

    /// The newer of the phone's and the server's.
    public func progress(_ key: EpisodeKey) async throws -> ListeningProgress? {
        let local = await store.progress(key)
        guard !Self.isFeedOnly(key), let server = try? await client.episodeProgress(itemId: key.showId, episodeId: key.episodeId) else { return local }
        let remote = ListeningProgress(positionMs: Int64(server.currentTime * 1000), played: server.isFinished, updatedAt: server.updatedAt)
        guard let local, local.updatedAt >= remote.updatedAt else { return remote }
        return local
    }

    public func allProgress() async throws -> [EpisodeKey: ListeningProgress] {
        var out = await store.allProgress()
        let me = try await translating { try await client.me() }
        for entry in me.mediaProgress {
            guard let episodeId = entry.episodeId else { continue }
            let key = EpisodeKey(showId: entry.libraryItemId, episodeId: episodeId)
            let remote = ListeningProgress(positionMs: Int64(entry.currentTime * 1000), played: entry.isFinished, updatedAt: entry.updatedAt)
            if let local = out[key], local.updatedAt >= remote.updatedAt { continue }
            out[key] = remote
        }
        return out
    }

    /// On the phone first, then to the server for episodes it holds. A send that fails keeps
    /// the phone's record, and the app sends it again later.
    public func saveProgress(_ progress: ListeningProgress, for key: EpisodeKey) async throws -> ListeningProgress {
        let kept = try await store.save(progress, for: key)
        guard kept == progress, !Self.isFeedOnly(key) else { return kept }
        let duration = (try? await episode(key).durationMs).flatMap { $0 }.map { Double($0) / 1000 } ?? 0
        try await translating {
            try await client.updateEpisodeProgress(itemId: key.showId, episodeId: key.episodeId, .init(currentTime: Double(progress.positionMs) / 1000, duration: duration, isFinished: progress.played))
        }
        return kept
    }

    public func markPlayed(_ key: EpisodeKey, _ played: Bool) async throws {
        let position = played ? (await store.progress(key)?.positionMs ?? 0) : 0
        _ = try await saveProgress(ListeningProgress(positionMs: position, played: played, updatedAt: now()), for: key)
    }

    // MARK: - Playing

    public func playback(_ key: EpisodeKey) async throws -> Playback {
        let episode = try await episode(key)
        if Self.isFeedOnly(key) {
            guard let url = episode.audioURL else { throw SourceError.notFound }
            return Playback(url: url, isServerFile: false)
        }
        let item: PodcastItem
        if let known = items[key.showId], known.media.episodes != nil { item = known } else { item = try await translating { try await client.podcast(id: key.showId) } }
        guard let file = item.media.episodes?.first(where: { $0.id == key.episodeId })?.audioFile else { throw SourceError.notFound }
        let token = try await translating { try await client.freshToken() }
        guard PlayableAudio.isPlayable(file.mimeType) else {
            // WebM, Ogg, Opus: the server transcodes them into HLS for a play session that says
            // what this phone plays.
            let session = try await translating { try await client.playEpisode(itemId: key.showId, episodeId: key.episodeId, device: device) }
            guard let track = session.audioTracks.first else { throw SourceError.notFound }
            return Playback(url: client.mediaURL(contentUrl: track.contentUrl, token: token), isServerFile: true, isHLS: session.isHLS)
        }
        guard let ino = file.ino else { throw SourceError.notFound }
        return Playback(url: client.fileURL(itemId: key.showId, ino: ino, token: token), isServerFile: true)
    }

    // MARK: - Mapping

    static func isFeedOnly(_ key: EpisodeKey) -> Bool { key.episodeId.hasPrefix(feedPrefix) }

    private func show(_ item: PodcastItem) async -> Show {
        let metadata = item.media.metadata
        return Show(
            // Audiobookshelf passes on titles as the feed or YouTube wrote them, entities and all.
            id: item.id, title: HTMLText.decodeEntities(metadata.title), author: metadata.author.map(HTMLText.decodeEntities),
            description: metadata.description.map(HTMLText.plain).flatMap { $0.isEmpty ? nil : $0 },
            imageURL: item.media.coverPath != nil ? client.coverURL(itemId: item.id, width: 600) : FeedValues.url(metadata.imageUrl),
            feedURL: FeedValues.url(metadata.feedUrl), link: FeedValues.url(metadata.itunesPageUrl), categories: metadata.genres,
            isSerial: metadata.type == "serial", isExplicit: metadata.explicit,
            followedAt: await store.firstSeen(showId: item.id) ?? Date(timeIntervalSince1970: Double(item.addedAt) / 1000),
            settings: await store.settings(showId: item.id)
        )
    }

    private func episode(_ episode: PodcastEpisode, showId: String) -> Episode {
        Episode(
            id: episode.id, showId: showId, title: HTMLText.decodeEntities(episode.title),
            description: episode.description.map(HTMLText.plain).flatMap { $0.isEmpty ? nil : $0 },
            publishedAt: episode.publishedAt.map { Date(timeIntervalSince1970: Double($0) / 1000) },
            durationMs: episode.duration > 0 ? Int64(episode.duration * 1000) : nil,
            audioURL: nil, audioType: episode.audioFile?.mimeType, audioBytes: episode.size,
            season: episode.season.flatMap { Int($0) }, number: episode.episode.flatMap { Int($0) }, kind: episode.episodeType,
            chapters: episode.chapters.map { Chapter(startMs: Int64($0.start * 1000), endMs: Int64($0.end * 1000), title: $0.title) },
            firstSeenAt: now()
        )
    }

    private func translating<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch let error as AudiobookshelfError {
            switch error {
            case .signedOut, .http(401, _): throw SourceError.signInRejected
            case .http(404, _): throw SourceError.notFound
            case .http(403, _): throw SourceError.unsupported
            case .network: throw SourceError.network
            default: throw SourceError.server(String(describing: error))
            }
        }
    }
}
