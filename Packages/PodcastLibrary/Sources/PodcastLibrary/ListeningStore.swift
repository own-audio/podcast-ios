import Foundation

/// What a server source keeps on the phone for itself: when each show and episode was first
/// seen (what makes an episode new to the listener), the inbox's dismissals, the queue, the
/// listener's own settings per show, and positions — written here first, then sent, and the
/// only record for episodes the server does not hold. The same rules as `FeedLibrary`.
public actor ListeningStore {
    struct State: Codable {
        var progress: [String: ListeningProgress] = [:]
        var dismissed: Set<String> = []
        var queue: [EpisodeKey] = []
        var episodeFirstSeen: [String: Date] = [:]
        var showFirstSeen: [String: Date] = [:]
        var latestAtFirstSight: [String: String] = [:]
        var settings: [String: ShowSettings] = [:]
    }

    private let file: URL
    private let now: @Sendable () -> Date
    private var state = State()

    public init(directory: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appendingPathComponent("listening.json")
        self.now = now
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(State.self, from: data) { state = saved }
    }

    // MARK: - First sightings

    /// Stamps what has not been seen before and returns the episodes with their first-seen time.
    /// The first time a show is seen, its newest episode is remembered as the one old episode
    /// New Episodes shows for it.
    public func observe(_ episodes: [Episode], showId: String) -> [Episode] {
        let stamp = now()
        var changed = false
        if state.showFirstSeen[showId] == nil {
            state.showFirstSeen[showId] = stamp
            if let newest = episodes.max(by: { ($0.publishedAt ?? .distantPast) < ($1.publishedAt ?? .distantPast) }) {
                state.latestAtFirstSight[showId] = newest.id
            }
            changed = true
        }
        let out = episodes.map { episode -> Episode in
            var episode = episode
            let key = episode.key.description
            if let seen = state.episodeFirstSeen[key] {
                episode.firstSeenAt = seen
            } else {
                state.episodeFirstSeen[key] = stamp
                episode.firstSeenAt = stamp
                changed = true
            }
            return episode
        }
        if changed { try? save() }
        return out
    }

    public func firstSeen(showId: String) -> Date? { state.showFirstSeen[showId] }

    /// New to the listener, unplayed, not dismissed, from a show that wants the inbox.
    public func isInInbox(_ episode: Episode) -> Bool {
        let key = episode.key.description
        guard state.settings[episode.showId]?.inInbox ?? true, state.progress[key]?.played != true, !state.dismissed.contains(key) else { return false }
        guard let showSeen = state.showFirstSeen[episode.showId] else { return false }
        return episode.firstSeenAt > showSeen || state.latestAtFirstSight[episode.showId] == episode.id
    }

    public func dismiss(_ keys: [EpisodeKey]) throws {
        state.dismissed.formUnion(keys.map(\.description))
        try save()
    }

    // MARK: - Settings

    public func settings(showId: String) -> ShowSettings { state.settings[showId] ?? ShowSettings() }

    public func setSettings(_ settings: ShowSettings, showId: String) throws {
        state.settings[showId] = settings
        try save()
    }

    // MARK: - Queue

    public func queue() -> [EpisodeKey] { state.queue }

    public func playNext(_ key: EpisodeKey) throws {
        state.queue.removeAll { $0 == key }
        state.queue.insert(key, at: 0)
        try save()
    }

    public func playLater(_ key: EpisodeKey) throws {
        guard !state.queue.contains(key) else { return }
        state.queue.append(key)
        try save()
    }

    public func removeFromQueue(_ key: EpisodeKey) throws {
        state.queue.removeAll { $0 == key }
        try save()
    }

    public func moveInQueue(from source: IndexSet, to destination: Int) throws {
        let moving = source.sorted().map { state.queue[$0] }
        var rest = state.queue.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let before = source.filter { $0 < destination }.count
        rest.insert(contentsOf: moving, at: max(0, min(rest.count, destination - before)))
        state.queue = rest
        try save()
    }

    /// The queue's head, taken off it; `current` leaves the queue first.
    public func popQueue(after current: EpisodeKey?) throws -> EpisodeKey? {
        if let current { state.queue.removeAll { $0 == current } }
        let head = state.queue.isEmpty ? nil : state.queue.removeFirst()
        try save()
        return head
    }

    // MARK: - Progress

    public func progress(_ key: EpisodeKey) -> ListeningProgress? { state.progress[key.description] }

    public func allProgress() -> [EpisodeKey: ListeningProgress] {
        Dictionary(uniqueKeysWithValues: state.progress.compactMap { key, value in EpisodeKey(key).map { ($0, value) } })
    }

    /// The newer wins; played leaves the queue.
    @discardableResult
    public func save(_ progress: ListeningProgress, for key: EpisodeKey) throws -> ListeningProgress {
        if let kept = state.progress[key.description], kept.updatedAt > progress.updatedAt { return kept }
        state.progress[key.description] = progress
        if progress.played { state.queue.removeAll { $0 == key } }
        try save()
        return progress
    }

    public func forget(showId: String) throws {
        let prefix = showId + "|"
        state.progress = state.progress.filter { !$0.key.hasPrefix(prefix) }
        state.dismissed = state.dismissed.filter { !$0.hasPrefix(prefix) }
        state.queue.removeAll { $0.showId == showId }
        state.episodeFirstSeen = state.episodeFirstSeen.filter { !$0.key.hasPrefix(prefix) }
        state.showFirstSeen[showId] = nil
        state.latestAtFirstSight[showId] = nil
        state.settings[showId] = nil
        try save()
    }

    private func save() throws {
        try JSONEncoder().encode(state).write(to: file, options: .atomic)
    }
}
