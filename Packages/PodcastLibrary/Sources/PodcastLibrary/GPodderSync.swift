import Foundation
import GPodderKit

/// Keeps the phone's feeds and a gPodder account (podfetch, Nextcloud's gPodder Sync,
/// gpodder.net) in step: subscriptions both ways, and positions and played marks as episode
/// actions. The newer of two positions wins, so whichever device was listened to last decides.
public actor GPodderSync {
    struct State: Codable {
        var subscriptionsSince: Int64 = 0
        var actionsSince: Int64 = 0
        /// The feeds both sides agreed on after the last sync; a feed missing from it on one side
        /// was removed there.
        var syncedFeeds: Set<String> = []
        /// When each episode's position was last sent, so only what changed goes up.
        var sent: [String: Date] = [:]
    }

    public struct Report: Sendable, Equatable {
        public var followed = 0
        public var unfollowed = 0
        public var uploadedShows = 0
        public var positionsApplied = 0
        public var positionsSent = 0
    }

    private let client: GPodderClient
    private let library: FeedLibrary
    private let device: String
    private let file: URL
    private var state: State

    /// `device` is this phone's id on the account, stable for the life of the install.
    public init(client: GPodderClient, library: FeedLibrary, device: String, directory: URL) {
        self.client = client
        self.library = library
        self.device = device
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appendingPathComponent("gpodder-\(device).json")
        state = (try? JSONDecoder().decode(State.self, from: Data(contentsOf: file))) ?? State()
    }

    public func register(caption: String) async throws {
        try await client.registerDevice(id: device, caption: caption)
    }

    @discardableResult
    public func sync() async throws -> Report {
        var report = Report()
        try await syncSubscriptions(&report)
        try await pullActions(&report)
        try await pushActions(&report)
        try save()
        return report
    }

    // MARK: - Subscriptions

    private func syncSubscriptions(_ report: inout Report) async throws {
        let firstSync = state.subscriptionsSince == 0
        // What the listener did on the phone since the last sync, worked out before the
        // account's changes are applied: it is newer than anything the account can say, and
        // a server that repeats a recent "add" must not bring back a show just unfollowed.
        let before = Set(await library.shows().compactMap { $0.feedURL?.absoluteString })
        let removedHere = firstSync ? [] : state.syncedFeeds.subtracting(before)
        let addedHere = before.subtracting(state.syncedFeeds)
        let changes = try await client.subscriptionChanges(device: device, since: state.subscriptionsSince)

        for feed in changes.remove where !addedHere.contains(feed) {
            state.syncedFeeds.remove(feed)
            guard let show = await show(feed: feed) else { continue }
            try await library.unfollow(showId: show.id)
            report.unfollowed += 1
        }
        for feed in changes.add where !changes.remove.contains(feed) && !removedHere.contains(feed) {
            state.syncedFeeds.insert(feed)
            guard await show(feed: feed) == nil, let url = URL(string: feed) else { continue }
            // One feed that is gone must not stop the rest; it stays on the account.
            if (try? await library.follow(feedURL: url)) != nil { report.followed += 1 }
        }

        let local = Set(await library.shows().compactMap { $0.feedURL?.absoluteString })
        let add = local.subtracting(state.syncedFeeds).sorted()
        let remove = removedHere.subtracting(local).sorted()
        var since = changes.timestamp
        if !add.isEmpty || !remove.isEmpty {
            let answer = try await client.uploadSubscriptionChanges(device: device, add: add, remove: remove)
            since = answer.timestamp
            report.uploadedShows = add.count
            state.syncedFeeds.formUnion(add)
            state.syncedFeeds.subtract(remove)
            for pair in answer.updateUrls where pair.count == 2 && state.syncedFeeds.remove(pair[0]) != nil {
                if !pair[1].isEmpty { state.syncedFeeds.insert(pair[1]) }
            }
        }
        state.subscriptionsSince = since
    }

    // MARK: - Episode actions

    private func pullActions(_ report: inout Report) async throws {
        let answer = try await client.episodeActions(since: state.actionsSince)
        var index: [String: [String: (key: EpisodeKey, durationMs: Int64?)]] = [:]
        // The account hands back this phone's own actions too; they are already here.
        for action in answer.actions where (action.action == .play || action.action == .new) && action.device != device {
            if index[action.podcast] == nil {
                guard let show = await show(feed: action.podcast), let episodes = try? await library.episodes(showId: show.id) else { continue }
                var byEpisode: [String: (key: EpisodeKey, durationMs: Int64?)] = [:]
                for episode in episodes {
                    if let audio = episode.audioURL?.absoluteString { byEpisode[audio] = (episode.key, episode.durationMs) }
                    byEpisode["guid:" + episode.id] = (episode.key, episode.durationMs)
                }
                index[action.podcast] = byEpisode
            }
            guard let match = index[action.podcast]?[action.episode] ?? action.guid.flatMap({ index[action.podcast]?["guid:" + $0] }) else { continue }
            let when = action.timestamp ?? Date(timeIntervalSince1970: TimeInterval(answer.timestamp))
            let progress: ListeningProgress
            if action.action == .new {
                progress = ListeningProgress(positionMs: 0, played: false, updatedAt: when)
            } else {
                let positionMs = Int64(action.position ?? 0) * 1000
                let durationMs = action.total.flatMap { $0 > 0 ? Int64($0) * 1000 : nil } ?? match.durationMs
                progress = ListeningProgress(positionMs: positionMs, played: ListeningProgress.reachedEnd(positionMs: positionMs, durationMs: durationMs), updatedAt: when)
            }
            let kept = try await library.saveProgress(progress, for: match.key)
            if kept == progress {
                report.positionsApplied += 1
                // Came from the account; sending it back would only echo it.
                state.sent[match.key.description] = progress.updatedAt
            }
        }
        state.actionsSince = answer.timestamp
    }

    private func pushActions(_ report: inout Report) async throws {
        var actions: [EpisodeAction] = []
        var stamps: [String: Date] = [:]
        let shows = Dictionary(uniqueKeysWithValues: await library.shows().map { ($0.id, $0) })
        for (key, progress) in await library.allProgress() {
            if let sent = state.sent[key.description], sent >= progress.updatedAt { continue }
            guard let feed = shows[key.showId]?.feedURL?.absoluteString,
                  let episode = try? await library.episode(key), let audio = episode.audioURL?.absoluteString else { continue }
            let total = episode.durationMs.map { Int($0 / 1000) }
            let position: Int
            if progress.played {
                position = total ?? Int(progress.positionMs / 1000)
            } else {
                position = Int(progress.positionMs / 1000)
            }
            if !progress.played && position == 0 {
                actions.append(EpisodeAction(podcast: feed, episode: audio, action: .new, timestamp: progress.updatedAt, device: device, guid: episode.id))
            } else {
                // A position with no length is still worth sending; servers accept a total of the position.
                actions.append(EpisodeAction(podcast: feed, episode: audio, action: .play, timestamp: progress.updatedAt, started: 0, position: position, total: total ?? position, device: device, guid: episode.id))
            }
            stamps[key.description] = progress.updatedAt
        }
        guard !actions.isEmpty else { return }
        // gpodder.net takes at most a few hundred per call.
        for start in stride(from: 0, to: actions.count, by: 200) {
            _ = try await client.uploadEpisodeActions(Array(actions[start..<min(start + 200, actions.count)]))
        }
        state.sent.merge(stamps) { _, new in new }
        report.positionsSent = actions.count
    }

    // MARK: -

    private func show(feed: String) async -> Show? {
        await library.shows().first { $0.feedURL?.absoluteString == feed }
    }

    private func save() throws {
        try JSONEncoder().encode(state).write(to: file, options: .atomic)
    }
}
