import FeedKit
import Foundation
import OwnAudioKit

/// An own.audio server's podcasts (`/api/v2`): the shows the household follows, their episodes
/// as the server keeps them, positions that follow the listener, and streams the server signs.
/// Following and refreshing are not in v2 yet, so they are hidden; New Episodes is built from
/// each show's newest page, by the same first-sighting rules as the other sources.
public actor OwnAudioPodcastSource: PodcastSource {
    public nonisolated let client: OwnAudioClient
    private let store: ListeningStore
    private let now: @Sendable () -> Date
    private var podcasts: [String: Podcast] = [:]

    public nonisolated var capabilities: Capabilities { [.syncsProgress, .serverDownloads, .familySharing] }

    public init(client: OwnAudioClient, store: ListeningStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.store = store
        self.now = now
    }

    // MARK: - Shows and episodes

    public func shows() async throws -> [Show] {
        var all: [Podcast] = []
        var cursor: String?
        repeat {
            let page = try await translating { try await client.podcasts(cursor: cursor) }
            all += page.items
            cursor = page.next
        } while cursor != nil
        var out: [Show] = []
        for podcast in all {
            podcasts[podcast.id] = podcast
            out.append(await show(podcast))
        }
        return out.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    public func episodes(showId: String) async throws -> [Episode] {
        var all: [PodcastEpisode] = []
        var cursor: String?
        repeat {
            let page = try await translating { try await client.episodes(podcastId: showId, cursor: cursor) }
            all += page.items
            cursor = page.next
        } while cursor != nil
        let observed = await store.observe(all.map(episode), showId: showId)
        return FeedLibrary.ordered(observed, serial: false)
    }

    public func episode(_ key: EpisodeKey) async throws -> Episode {
        let found = try await translating { try await client.episode(id: key.episodeId) }
        return (await store.observe([episode(found)], showId: key.showId)).first!
    }

    public func follow(feedURL: URL) async throws -> Show { throw SourceError.unsupported }
    public func unfollow(showId: String) async throws { throw SourceError.unsupported }

    public func updateSettings(_ settings: ShowSettings, showId: String) async throws {
        try await store.setSettings(settings, showId: showId)
    }

    /// The server refreshes feeds by itself; this asks it for each show's newest episodes and
    /// returns those first seen now.
    public func refresh(showId: String?) async throws -> [Episode] {
        let started = now()
        let ids: [String]
        if let showId { ids = [showId] } else { ids = try await shows().map(\.id) }
        var fresh: [Episode] = []
        for id in ids {
            let page = try await translating { try await client.episodes(podcastId: id, limit: 20) }
            fresh += await store.observe(page.items.map(episode), showId: id).filter { $0.firstSeenAt >= started }
        }
        return fresh
    }

    // MARK: - New Episodes and the queue

    public func inbox(limit: Int) async throws -> [Episode] {
        if podcasts.isEmpty { _ = try await shows() }
        var inbox: [Episode] = []
        for id in podcasts.keys {
            let page = try await translating { try await client.episodes(podcastId: id, limit: 20) }
            for episode in await store.observe(page.items.map(episode), showId: id) where await store.isInInbox(episode) {
                inbox.append(episode)
            }
        }
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

    public func progress(_ key: EpisodeKey) async throws -> ListeningProgress? {
        let local = await store.progress(key)
        guard let server = try? await client.progress(.episode, id: key.episodeId) else { return local }
        let remote = ListeningProgress(positionMs: server.positionMs, played: server.finished, updatedAt: server.updatedAt)
        guard let local, local.updatedAt >= remote.updatedAt else { return remote }
        return local
    }

    public func allProgress() async throws -> [EpisodeKey: ListeningProgress] {
        var out = await store.allProgress()
        let byEpisode = Dictionary(out.map { ($0.key.episodeId, $0.key) }, uniquingKeysWith: { first, _ in first })
        var remote: [OwnAudioKit.Progress] = []
        var cursor: String?
        repeat {
            let page = try await translating { try await client.progressList(.episode, cursor: cursor) }
            remote += page.items
            cursor = page.next
        } while cursor != nil
        for entry in remote {
            // The server names episodes alone; the show comes from what the phone already knows.
            guard let key = byEpisode[entry.id] else { continue }
            let progress = ListeningProgress(positionMs: entry.positionMs, played: entry.finished, updatedAt: entry.updatedAt)
            if let local = out[key], local.updatedAt >= progress.updatedAt { continue }
            out[key] = progress
        }
        return out
    }

    /// On the phone first, then to the server with the time it happened, so the server keeps
    /// the newer of this and another device's position. Returns what the server holds.
    public func saveProgress(_ progress: ListeningProgress, for key: EpisodeKey) async throws -> ListeningProgress {
        let kept = try await store.save(progress, for: key)
        guard kept == progress else { return kept }
        let answer = try await translating {
            try await client.saveProgress(.episode, id: key.episodeId, positionMs: progress.positionMs, finished: progress.played, at: progress.updatedAt)
        }
        let held = ListeningProgress(positionMs: answer.progress.positionMs, played: answer.progress.finished, updatedAt: answer.progress.updatedAt)
        if !answer.applied { try await store.save(held, for: key) }
        return answer.applied ? kept : held
    }

    public func markPlayed(_ key: EpisodeKey, _ played: Bool) async throws {
        let position = played ? (await store.progress(key)?.positionMs ?? 0) : 0
        _ = try await saveProgress(ListeningProgress(positionMs: position, played: played, updatedAt: now()), for: key)
    }

    // MARK: - Playing

    /// The server's signed stream (its stored copy, or the publisher's file through it).
    public func playback(_ key: EpisodeKey) async throws -> Playback {
        let info = try await translating { try await client.playbackInfo(kind: "episode", id: key.episodeId, capabilities: PlaybackCapabilities()) }
        return Playback(url: info.url, isServerFile: true)
    }

    // MARK: - Mapping

    private func show(_ podcast: Podcast) async -> Show {
        Show(
            id: podcast.id, title: HTMLText.decodeEntities(podcast.title), author: nil,
            description: podcast.description.map(HTMLText.plain).flatMap { $0.isEmpty ? nil : $0 },
            imageURL: FeedValues.url(podcast.image), feedURL: FeedValues.url(podcast.feedUrl), link: FeedValues.url(podcast.link),
            categories: podcast.categories ?? [],
            followedAt: await store.firstSeen(showId: podcast.id) ?? now(),
            settings: await store.settings(showId: podcast.id)
        )
    }

    private func episode(_ episode: PodcastEpisode) -> Episode {
        Episode(
            id: episode.id, showId: episode.podcastId, title: HTMLText.decodeEntities(episode.title),
            description: episode.description.map(HTMLText.plain).flatMap { $0.isEmpty ? nil : $0 },
            publishedAt: episode.publishedAt, durationMs: episode.durationMs, audioURL: FeedValues.url(episode.audioUrl),
            audioType: episode.contentType, audioBytes: episode.sizeBytes, imageURL: FeedValues.url(episode.image),
            season: episode.seasonNumber, number: episode.episodeNumber,
            transcripts: episode.transcriptUrl.flatMap(FeedValues.url).map { [Transcript(url: $0, type: episode.transcriptType ?? "text/plain", language: nil)] } ?? [],
            firstSeenAt: now()
        )
    }

    func translating<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch let error as OwnAudioError {
            switch error {
            case .signedOut: throw SourceError.signInRejected
            case .problem(let p) where p.status == 401: throw SourceError.signInRejected
            case .problem(let p) where p.status == 404: throw SourceError.notFound
            case .network, .offline: throw SourceError.network
            default: throw SourceError.server(String(describing: error))
            }
        }
    }
}
