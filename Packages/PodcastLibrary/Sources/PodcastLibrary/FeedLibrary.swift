import FeedKit
import Foundation

/// The phone's own library: the shows the listener follows by feed, their episodes, positions,
/// the inbox and the queue, kept as JSON files in one folder. With no server this *is* the
/// library; with one, it is what the app falls back to offline.
///
/// Every change is written before the call returns, so a kill never loses a follow, a position
/// or the queue.
public actor FeedLibrary: PodcastSource {
    public nonisolated let capabilities: Capabilities = [.addByURL]

    struct ShowRecord: Codable {
        var show: Show
        var episodes: [Episode]
        var validators: FeedFetcher.Validators?
        /// The episode that was newest when the show was followed: the one old episode the inbox
        /// shows, so a new follow is not an empty row.
        var latestAtFollow: String?
    }

    struct State: Codable {
        var progress: [String: ListeningProgress] = [:]
        /// Episodes taken out of the inbox without being played.
        var dismissed: Set<String> = []
        var queue: [EpisodeKey] = []
    }

    private let directory: URL
    private let fetcher: FeedFetcher
    private let now: @Sendable () -> Date
    private var records: [String: ShowRecord] = [:]
    private var state = State()

    public init(directory: URL, fetcher: FeedFetcher = FeedFetcher(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.fetcher = fetcher
        self.now = now
        try? FileManager.default.createDirectory(at: directory.appendingPathComponent("shows"), withIntermediateDirectories: true)
        let decoder = JSONDecoder()
        if let files = try? FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("shows"), includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "json" {
                if let data = try? Data(contentsOf: file), let record = try? decoder.decode(ShowRecord.self, from: data) {
                    records[record.show.id] = record
                }
            }
        }
        if let data = try? Data(contentsOf: directory.appendingPathComponent("state.json")), let saved = try? decoder.decode(State.self, from: data) {
            state = saved
        }
    }

    // MARK: - Shows and episodes

    public func shows() -> [Show] {
        records.values.map(\.show).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Newest first, or oldest first for a serial show.
    public func episodes(showId: String) throws -> [Episode] {
        guard let record = records[showId] else { throw SourceError.notFound }
        return Self.ordered(record.episodes, serial: record.show.isSerial)
    }

    public func episode(_ key: EpisodeKey) throws -> Episode {
        guard let episode = records[key.showId]?.episodes.first(where: { $0.id == key.episodeId }) else { throw SourceError.notFound }
        return episode
    }

    public func follow(feedURL: URL) async throws -> Show {
        if let existing = records.values.first(where: { $0.show.feedURL == feedURL }) { return existing.show }
        let result: FeedFetcher.Result
        do {
            result = try await fetcher.fetch(feedURL)
        } catch FeedError.notAFeed {
            throw SourceError.notAFeed
        } catch {
            throw SourceError.network
        }
        guard case .fetched(let document, let validators, let finalURL) = result else { throw SourceError.network }
        let id = UUID().uuidString
        let followed = now()
        var show = Show(id: id, title: document.show.title, followedAt: followed)
        Self.apply(document.show, to: &show)
        show.feedURL = document.show.newFeedURL ?? finalURL
        show.refreshedAt = followed
        let episodes = document.episodes.filter { $0.enclosure != nil }.map { Episode($0, showId: id, firstSeenAt: followed) }
        let latest = episodes.max { ($0.publishedAt ?? .distantPast) < ($1.publishedAt ?? .distantPast) }
        records[id] = ShowRecord(show: show, episodes: episodes, validators: validators, latestAtFollow: show.isSerial ? nil : latest?.id)
        try save(showId: id)
        return show
    }

    public func unfollow(showId: String) throws {
        records[showId] = nil
        try? FileManager.default.removeItem(at: file(showId))
        state.queue.removeAll { $0.showId == showId }
        state.progress = state.progress.filter { !$0.key.hasPrefix(showId + "|") }
        state.dismissed = state.dismissed.filter { !$0.hasPrefix(showId + "|") }
        try saveState()
    }

    public func updateSettings(_ settings: ShowSettings, showId: String) throws {
        guard records[showId] != nil else { throw SourceError.notFound }
        records[showId]?.show.settings = settings
        try save(showId: showId)
    }

    // MARK: - Refreshing

    /// Conditional fetches, four at a time. New episodes are stamped with the time this phone
    /// first saw them, which is what puts them in the inbox; a show set to auto-queue gets them
    /// queued. A failing feed is left as it was and does not stop the others.
    public func refresh(showId: String? = nil) async -> [Episode] {
        let targets = records.values.filter { showId == nil || $0.show.id == showId }.compactMap { record -> (String, URL, FeedFetcher.Validators?)? in
            guard let url = record.show.feedURL else { return nil }
            return (record.show.id, url, record.validators)
        }
        var fresh: [Episode] = []
        let fetcher = self.fetcher
        await withTaskGroup(of: (String, FeedFetcher.Result?).self) { group in
            var pending = targets[...]
            for _ in 0..<min(4, pending.count) {
                let (id, url, validators) = pending.removeFirst()
                group.addTask { (id, try? await fetcher.fetch(url, validators: validators)) }
            }
            for await (id, result) in group {
                if let result { fresh += merge(result, into: id) }
                if let (next, url, validators) = pending.first {
                    pending.removeFirst()
                    group.addTask { (next, try? await fetcher.fetch(url, validators: validators)) }
                }
            }
        }
        let queued = fresh.filter { records[$0.showId]?.show.settings.autoQueue == true }.sorted { ($0.publishedAt ?? .distantPast) < ($1.publishedAt ?? .distantPast) }
        if !queued.isEmpty {
            state.queue += queued.map(\.key).filter { !state.queue.contains($0) }
            try? saveState()
        }
        return fresh
    }

    /// The feed's episodes over the stored ones: known ones keep their first-seen time, new
    /// ones get now, ones the feed dropped are dropped unless the listener is in the middle of
    /// them or has them queued.
    private func merge(_ result: FeedFetcher.Result, into showId: String) -> [Episode] {
        guard var record = records[showId] else { return [] }
        let stamp = now()
        record.show.refreshedAt = stamp
        guard case .fetched(let document, let validators, let finalURL) = result else {
            records[showId] = record
            try? save(showId: showId)
            return []
        }
        Self.apply(document.show, to: &record.show)
        if let moved = document.show.newFeedURL { record.show.feedURL = moved } else if finalURL != record.show.feedURL { record.show.feedURL = finalURL }
        record.validators = validators
        let known = Dictionary(record.episodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var fresh: [Episode] = []
        var merged: [Episode] = []
        var seen = Set<String>()
        for feedEpisode in document.episodes where feedEpisode.enclosure != nil && !seen.contains(feedEpisode.id) {
            seen.insert(feedEpisode.id)
            if let old = known[feedEpisode.id] {
                merged.append(Episode(feedEpisode, showId: showId, firstSeenAt: old.firstSeenAt))
            } else {
                let episode = Episode(feedEpisode, showId: showId, firstSeenAt: stamp)
                merged.append(episode)
                fresh.append(episode)
            }
        }
        let keep = Set(state.queue.filter { $0.showId == showId }.map(\.episodeId))
            .union(state.progress.filter { $0.key.hasPrefix(showId + "|") && !$0.value.played && $0.value.positionMs > 0 }.compactMap { EpisodeKey($0.key)?.episodeId })
        merged += record.episodes.filter { !seen.contains($0.id) && keep.contains($0.id) }
        record.episodes = merged
        records[showId] = record
        try? save(showId: showId)
        return fresh
    }

    private static func apply(_ feed: FeedShow, to show: inout Show) {
        show.title = feed.title.isEmpty ? show.title : feed.title
        show.author = feed.author ?? show.author
        show.description = feed.description ?? show.description
        show.imageURL = feed.imageURL ?? show.imageURL
        show.link = feed.link ?? show.link
        show.categories = feed.categories.isEmpty ? show.categories : feed.categories
        show.isSerial = feed.isSerial
        show.isExplicit = feed.isExplicit
    }

    // MARK: - The inbox

    /// New Episodes: unplayed, not dismissed, from shows that want it, and new to the listener —
    /// first seen after the follow, or the one that was newest at the follow. Newest first.
    public func inbox(limit: Int = 200) -> [Episode] {
        var out: [Episode] = []
        for record in records.values where record.show.settings.inInbox {
            for episode in record.episodes {
                let key = episode.key.description
                let isNew = episode.firstSeenAt > record.show.followedAt || episode.id == record.latestAtFollow
                guard isNew, state.progress[key]?.played != true, !state.dismissed.contains(key) else { continue }
                out.append(episode)
            }
        }
        out.sort { ($0.publishedAt ?? $0.firstSeenAt) > ($1.publishedAt ?? $1.firstSeenAt) }
        return Array(out.prefix(limit))
    }

    public func dismissFromInbox(_ keys: [EpisodeKey]) throws {
        state.dismissed.formUnion(keys.map(\.description))
        try saveState()
    }

    // MARK: - The queue

    public func queue() -> [EpisodeKey] { state.queue }

    /// Right after what is playing (the queue's head is what plays next).
    public func playNext(_ key: EpisodeKey) throws {
        state.queue.removeAll { $0 == key }
        state.queue.insert(key, at: 0)
        try saveState()
    }

    public func playLater(_ key: EpisodeKey) throws {
        guard !state.queue.contains(key) else { return }
        state.queue.append(key)
        try saveState()
    }

    public func removeFromQueue(_ key: EpisodeKey) throws {
        state.queue.removeAll { $0 == key }
        try saveState()
    }

    public func moveInQueue(from source: IndexSet, to destination: Int) throws {
        let moving = source.sorted().map { state.queue[$0] }
        var rest = state.queue.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let before = source.filter { $0 < destination }.count
        rest.insert(contentsOf: moving, at: max(0, min(rest.count, destination - before)))
        state.queue = rest
        try saveState()
    }

    /// What plays after `current` ends: the queue's next, else the newest inbox episode that
    /// isn't the one just heard. The episode returned leaves the queue.
    public func takeNext(after current: EpisodeKey?) throws -> Episode? {
        if let current { state.queue.removeAll { $0 == current } }
        while let head = state.queue.first {
            state.queue.removeFirst()
            if let episode = try? episode(head) {
                try saveState()
                return episode
            }
        }
        try saveState()
        return inbox().first { $0.key != current }
    }

    // MARK: - Progress

    public func progress(_ key: EpisodeKey) -> ListeningProgress? { state.progress[key.description] }

    public func allProgress() -> [EpisodeKey: ListeningProgress] {
        Dictionary(uniqueKeysWithValues: state.progress.compactMap { key, value in EpisodeKey(key).map { ($0, value) } })
    }

    /// The newer of what is kept and what comes in wins, so a late report from a stale player
    /// cannot move a position back.
    public func saveProgress(_ progress: ListeningProgress, for key: EpisodeKey) throws -> ListeningProgress {
        if let kept = state.progress[key.description], kept.updatedAt > progress.updatedAt { return kept }
        state.progress[key.description] = progress
        if progress.played { state.queue.removeAll { $0 == key } }
        try saveState()
        return progress
    }

    /// A position reached while playing; heard once it reaches the end.
    @discardableResult
    public func record(positionMs: Int64, for key: EpisodeKey, at date: Date? = nil) throws -> ListeningProgress {
        let duration = records[key.showId]?.episodes.first { $0.id == key.episodeId }?.durationMs
        let played = ListeningProgress.reachedEnd(positionMs: positionMs, durationMs: duration) || state.progress[key.description]?.played == true && positionMs == 0
        return try saveProgress(ListeningProgress(positionMs: positionMs, played: played, updatedAt: date ?? now()), for: key)
    }

    public func markPlayed(_ key: EpisodeKey, _ played: Bool) throws {
        state.progress[key.description] = ListeningProgress(positionMs: played ? (state.progress[key.description]?.positionMs ?? 0) : 0, played: played, updatedAt: now())
        if played { state.queue.removeAll { $0 == key } }
        try saveState()
    }

    // MARK: - Disk

    private func file(_ showId: String) -> URL {
        directory.appendingPathComponent("shows").appendingPathComponent("\(showId).json")
    }

    private func save(showId: String) throws {
        guard let record = records[showId] else { return }
        try JSONEncoder().encode(record).write(to: file(showId), options: .atomic)
    }

    private func saveState() throws {
        try JSONEncoder().encode(state).write(to: directory.appendingPathComponent("state.json"), options: .atomic)
    }

    static func ordered(_ episodes: [Episode], serial: Bool) -> [Episode] {
        episodes.sorted { a, b in
            let (x, y) = (a.publishedAt ?? a.firstSeenAt, b.publishedAt ?? b.firstSeenAt)
            return serial ? x < y : x > y
        }
    }
}
