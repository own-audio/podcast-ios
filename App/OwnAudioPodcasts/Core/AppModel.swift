import AudiobookshelfKit
import FeedKit
import Foundation
import GPodderKit
import Observation
import OwnAudioKit
import PlayerCore
import PodcastLibrary
import SpokenEngine
import UIKit

/// Where a show or an episode comes from: the phone's own feeds, or one of the servers.
enum SourceRef: Hashable, Sendable {
    case phone
    case server(UUID)
    /// One library of a server (Audiobookshelf), for the switch and for adding shows; items
    /// themselves always belong to `.server`.
    case library(UUID, String)

    var id: String {
        switch self {
        case .phone: "phone"
        case .server(let id): id.uuidString
        case .library(let id, let library): id.uuidString + "#" + library
        }
    }

    var serverId: UUID? {
        switch self {
        case .phone: nil
        case .server(let id), .library(let id, _): id
        }
    }

    init?(id: String) {
        if id == "phone" {
            self = .phone
        } else if let hash = id.firstIndex(of: "#"), let uuid = UUID(uuidString: String(id[..<hash])) {
            self = .library(uuid, String(id[id.index(after: hash)...]))
        } else if let uuid = UUID(uuidString: id) {
            self = .server(uuid)
        } else {
            return nil
        }
    }
}

struct SourcedShow: Identifiable, Hashable, Sendable {
    let source: SourceRef
    let show: Show
    var id: String { source.id + "/" + show.id }

    static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.show == b.show }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct SourcedEpisode: Identifiable, Hashable, Sendable {
    let source: SourceRef
    let episode: Episode
    /// `<source>/<show>|<episode>`: unique across every source, and the player's id for it.
    var id: String { source.id + "/" + episode.key.description }

    static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.episode == b.episode }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static func parse(_ id: String) -> (SourceRef, EpisodeKey)? {
        guard let slash = id.firstIndex(of: "/"), let source = SourceRef(id: String(id[..<slash])),
              let key = EpisodeKey(String(id[id.index(after: slash)...])) else { return nil }
        return (source, key)
    }
}

/// The whole app's state: the sources and their shows, New Episodes, positions, the player.
/// Screens read it and call it; nothing else talks to a source.
@Observable
@MainActor
final class AppModel {
    static let shared = AppModel()

    private(set) var hasLoaded = false
    private(set) var servers: [ServerRecord] = []
    private(set) var shows: [SourcedShow] = []
    private(set) var inbox: [SourcedEpisode] = []
    /// By `SourcedEpisode.id`.
    private(set) var progress: [String: ListeningProgress] = [:]
    private(set) var isRefreshing = false
    /// Sources that could not be read the last time; their shows are left out until they answer.
    private(set) var unreachable: Set<SourceRef> = []
    var actionError: String?

    private(set) var nowPlaying: SourcedEpisode?
    private(set) var nowPlayingShow: Show?

    let nowPlayingController = NowPlayingController()
    let engine: SpokenEngine
    let settings = PlaybackSettings()
    let network = NetworkMonitor()
    let phone: FeedLibrary

    @ObservationIgnored private var sources: [UUID: any PodcastSource] = [:]
    @ObservationIgnored private var syncs: [UUID: GPodderSync] = [:]
    @ObservationIgnored private let store = ServerStore()
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var syncTask: Task<Void, Never>?

    /// The hosted service's edge refuses requests with no User-Agent.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = ["User-Agent": "own.audio Podcasts/\(appVersion) iOS"]
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }()

    static var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    /// Made once per installation: the phone's device id on a gPodder account.
    static let installationId: String = {
        let key = "installationId"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let made = UUID().uuidString.lowercased()
        UserDefaults.standard.set(made, forKey: key)
        return made
    }()

    /// The public demo: a shared own.audio server with sample shows.
    static let demoHost = URL(string: "https://demopi.own.audio")!

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("podcasts", isDirectory: true)
        if UITestFlags.isUITesting {
            try? FileManager.default.removeItem(at: directory)
        }
        phone = FeedLibrary(directory: directory.appendingPathComponent("phone", isDirectory: true), fetcher: FeedFetcher(session: Self.session))
        engine = SpokenEngine(nowPlaying: nowPlayingController, resumeStore: nil)
        engine.skipForwardSecs = settings.skipForwardSecs
        engine.skipBackwardSecs = settings.skipBackwardSecs
        engine.smartRewind = SmartRewind(isEnabled: settings.smartRewind)
        engine.onPosition = { [weak self] position in self?.positionReported(position) }
        engine.artworkProvider = { [weak self] id in await self?.artwork(for: id) }
        network.onChange = { [weak self] connected in
            guard connected else { return }
            Task {
                await self?.chooseAddresses()
                await self?.refresh()
            }
        }
    }

    // MARK: - State

    var isOffline: Bool { settings.offlineMode || !network.isConnected }
    var isOfflineByChoice: Bool { settings.offlineMode }

    func setOfflineMode(_ on: Bool) {
        settings.offlineMode = on
        Task {
            await reloadLists()
            if !on { await refresh() }
        }
    }

    /// Nothing followed and no server: the first-run screen.
    var isEmpty: Bool { shows.isEmpty && servers.isEmpty }

    func server(_ id: UUID) -> ServerRecord? { servers.first { $0.id == id } }

    // MARK: - The source switch

    /// The source New Episodes and Shows show; nil for all of them together.
    var activeSource: SourceRef? = SourceRef(id: UserDefaults.standard.string(forKey: "activeSource") ?? "") {
        didSet { UserDefaults.standard.set(activeSource?.id, forKey: "activeSource") }
    }

    /// The sources that have a library of their own, for the switch: this iPhone and every
    /// own.audio and Audiobookshelf server. A gPodder account syncs this iPhone's shows and is
    /// not one.
    var switchableSources: [SourceRef] {
        // own.audio first, always; then this iPhone, then the other servers and gPodder accounts.
        // A server with several libraries offers each one after itself.
        func entries(_ record: ServerRecord) -> [SourceRef] {
            let libraries = record.visibleLibraries
            return [.server(record.id)] + (libraries.count > 1 ? libraries.map { .library(record.id, $0.id) } : [])
        }
        return serversInOrder.filter { $0.kind == .ownAudio }.flatMap(entries) + [.phone]
            + serversInOrder.filter { $0.kind != .ownAudio }.flatMap(entries)
    }

    /// Each gPodder account's shows, as of its last sync: the phone's shows it holds.
    private(set) var gpodderFeeds: [UUID: Set<String>] = [:]

    private func noteAccountFeeds() async {
        for (id, sync) in syncs { gpodderFeeds[id] = await sync.accountFeeds() }
    }

    /// Whether an item of `source` belongs on the switch's `active` choice. A gPodder account
    /// holds no library of its own: its choice shows the phone's shows that are on the account.
    private func matches(_ source: SourceRef, showFeed: URL?, active: SourceRef) -> Bool {
        if case .server(let id) = active, server(id)?.kind == .gpodder {
            return source == .phone && showFeed.map { gpodderFeeds[id]?.contains($0.absoluteString) == true } == true
        }
        return source == active
    }

    private func matches(_ source: SourceRef, show: Show?, active: SourceRef) -> Bool {
        if case .library(let id, let library) = active {
            return source == .server(id) && show?.collection == library
        }
        return matches(source, showFeed: show?.feedURL, active: active)
    }

    /// Servers as every list shows them: own.audio first, then Audiobookshelf, then gPodder
    /// accounts, each by name.
    var serversInOrder: [ServerRecord] {
        func rank(_ kind: ServerKind) -> Int {
            switch kind {
            case .ownAudio: 0
            case .audiobookshelf: 1
            case .gpodder: 2
            }
        }
        return servers.sorted {
            rank($0.kind) != rank($1.kind) ? rank($0.kind) < rank($1.kind)
                : $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    var visibleInbox: [SourcedEpisode] {
        guard let activeSource else { return inbox }
        return inbox.filter { matches($0.source, show: show(for: $0), active: activeSource) }
    }

    var visibleShows: [SourcedShow] {
        guard let activeSource else { return shows }
        return shows.filter { matches($0.source, show: $0.show, active: activeSource) }
    }

    func brand(_ ref: SourceRef) -> ServerBrand {
        guard let id = ref.serverId else { return .phone }
        return server(id).map(ServerBrand.init) ?? .gpodder
    }

    func sourceName(_ ref: SourceRef) -> String {
        switch ref {
        case .phone: String(localized: "This iPhone")
        case .server(let id): server(id)?.displayName ?? String(localized: "Removed server")
        case .library(let id, let library):
            "\(server(id)?.displayName ?? String(localized: "Removed server")) · \(server(id)?.libraries.first { $0.id == library }?.name ?? library)"
        }
    }

    func capabilities(_ ref: SourceRef) -> Capabilities {
        source(ref)?.capabilities ?? []
    }

    /// Where shows can be followed: the phone always, and every server that takes a feed URL.
    var followTargets: [SourceRef] {
        [.phone] + serversInOrder.filter { $0.kind != .gpodder && sources[$0.id]?.capabilities.contains(.addByURL) == true }.flatMap { record -> [SourceRef] in
            // On a server with several libraries, the show goes into the one chosen.
            let libraries = record.visibleLibraries
            return libraries.count > 1 ? libraries.map { .library(record.id, $0.id) } : [.server(record.id)]
        }
    }

    func source(_ ref: SourceRef) -> (any PodcastSource)? {
        switch ref {
        case .phone: phone
        case .server(let id), .library(let id, _): sources[id]
        }
    }

    // MARK: - Loading

    func load() async {
        guard !hasLoaded else { return }
        if UITestFlags.isUITesting {
            await store.clear()
            activeSource = nil
        }
        servers = await store.loadAll()
        // A source remembered from before that is gone now would filter everything away.
        if let active = activeSource, !switchableSources.contains(active) { activeSource = nil }
        rebuildSources()
        await noteAccountFeeds()
        await addFromLaunchArguments()
        await reloadLists()
        hasLoaded = true
        await chooseAddresses()
        await loadServerIcons()
        await loadLibraries()
        await refresh()
    }

    /// For UI tests and screenshots: `-debugFeedURL`, and `-debugServerKind` (ownAudio,
    /// audiobookshelf, gpodder) with `-debugServerHost`, `-debugServerUser`, `-debugServerPassword`.
    private func addFromLaunchArguments() async {
        let defaults = UserDefaults.standard
        for text in (defaults.string(forKey: "debugFeedURL") ?? "").split(separator: " ") {
            if let url = URL(string: String(text)) { _ = try? await phone.follow(feedURL: url) }
        }
        guard let kindName = defaults.string(forKey: "debugServerKind"),
              let host = defaults.string(forKey: "debugServerHost"),
              let user = defaults.string(forKey: "debugServerUser"),
              let password = defaults.string(forKey: "debugServerPassword") else { return }
        do {
            // "automatic" (or anything unknown) finds the kind the way the form does.
            try await addServer(kind: ServerKind(rawValue: kindName), address: host, username: user, password: password)
        } catch {
            actionError = Self.message(for: error)
        }
    }

    private func rebuildSources() {
        sources = [:]
        syncs = [:]
        for record in servers {
            switch record.kind {
            case .ownAudio:
                let tokens = OwnAudioKit.TokenSession(record.ownAudioTokens, keeper: OwnAudioTokenKeeper(store: store, serverId: record.id))
                let client = OwnAudioClient(host: address(for: record), tokens: tokens, session: Self.session)
                sources[record.id] = OwnAudioPodcastSource(client: client, store: ListeningStore(directory: serverDirectory(record.id)))
            case .audiobookshelf:
                let tokens = AudiobookshelfKit.TokenSession(record.audiobookshelfTokens, keeper: AudiobookshelfTokenKeeper(store: store, serverId: record.id))
                let client = AudiobookshelfClient(host: address(for: record), tokens: tokens, session: Self.session)
                sources[record.id] = AudiobookshelfPodcastSource(client: client, store: ListeningStore(directory: serverDirectory(record.id)), fetcher: FeedFetcher(session: Self.session), canAddShows: record.canAddShows)
            case .gpodder:
                guard let password = record.password else { continue }
                let client = GPodderClient(host: address(for: record), username: record.username, password: password, session: Self.session)
                syncs[record.id] = GPodderSync(client: client, library: phone, device: Self.gpodderDevice, directory: serverDirectory(record.id))
            }
        }
    }

    private static var gpodderDevice: String { "own-audio-podcasts-" + installationId.prefix(8) }

    private func serverDirectory(_ id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// Every source's shows, New Episodes and positions, read again. Offline, only the phone's
    /// own feeds are read: they are on disk, and a server would only time out.
    func reloadLists() async {
        var allShows: [SourcedShow] = []
        var allInbox: [SourcedEpisode] = []
        var allProgress: [String: ListeningProgress] = [:]
        var failing = Set<SourceRef>()
        var refs: [SourceRef] = [.phone]
        if !isOffline { refs += servers.filter { $0.kind != .gpodder }.map { .server($0.id) } }
        for ref in refs {
            guard let source = source(ref) else { continue }
            do {
                let hidden = Set(ref.serverId.flatMap { server($0)?.hiddenLibraries } ?? [])
                let sourceShows = try await source.shows().filter { $0.collection.map { !hidden.contains($0) } ?? true }
                let kept = Set(sourceShows.map(\.id))
                allShows += sourceShows.map { SourcedShow(source: ref, show: $0) }
                allInbox += try await source.inbox(limit: 200).filter { hidden.isEmpty || kept.contains($0.showId) }.map { SourcedEpisode(source: ref, episode: $0) }
                for (key, value) in try await source.allProgress() {
                    allProgress[ref.id + "/" + key.description] = value
                }
            } catch {
                failing.insert(ref)
            }
        }
        shows = allShows.sorted { $0.show.title.localizedStandardCompare($1.show.title) == .orderedAscending }
        inbox = allInbox.sorted { ($0.episode.publishedAt ?? $0.episode.firstSeenAt) > ($1.episode.publishedAt ?? $1.episode.firstSeenAt) }
        progress = allProgress
        unreachable = failing
    }

    /// Syncs gPodder accounts, asks every feed and server for new episodes, and reads the lists
    /// again. Offline it does nothing.
    func refresh() async {
        guard !isOffline, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        for (id, sync) in syncs where (try? await sync.sync()) != nil { lastSyncs[id] = Date() }
        await noteAccountFeeds()
        _ = await phone.refresh(showId: nil)
        for source in sources.values { _ = try? await source.refresh(showId: nil) }
        await reloadLists()
    }

    /// After the phone's subscriptions or positions changed: one gPodder sync a few seconds later,
    /// however many changes come in between.
    private func scheduleSync() {
        guard !syncs.isEmpty, !isOffline else { return }
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            for sync in self.syncs.values { _ = try? await sync.sync() }
        }
    }

    // MARK: - Shows

    @discardableResult
    func follow(_ feedURL: URL, into ref: SourceRef = .phone) async throws -> SourcedShow {
        guard let source = source(ref) else { throw SourceError.notFound }
        let show: Show
        if case .library(_, let library) = ref, let abs = source as? AudiobookshelfPodcastSource {
            show = try await abs.follow(feedURL: feedURL, libraryId: library)
        } else {
            show = try await source.follow(feedURL: feedURL)
        }
        await reloadLists()
        if ref == .phone { scheduleSync() }
        return SourcedShow(source: ref.serverId.map { .server($0) } ?? .phone, show: show)
    }

    func unfollow(_ show: SourcedShow) async {
        do {
            try await source(show.source)?.unfollow(showId: show.show.id)
            if nowPlaying?.source == show.source, nowPlaying?.episode.showId == show.show.id { stopPlayback() }
            shows.removeAll { $0.id == show.id }
            inbox.removeAll { $0.source == show.source && $0.episode.showId == show.show.id }
            if show.source == .phone { scheduleSync() }
        } catch {
            actionError = Self.message(for: error)
        }
    }

    func episodes(of show: SourcedShow) async throws -> [SourcedEpisode] {
        guard let source = source(show.source) else { throw SourceError.notFound }
        return try await source.episodes(showId: show.show.id).map { SourcedEpisode(source: show.source, episode: $0) }
    }

    func refresh(_ show: SourcedShow) async {
        guard !isOffline else { return }
        _ = try? await source(show.source)?.refresh(showId: show.show.id)
        await reloadLists()
    }

    func updateSettings(_ settings: ShowSettings, for show: SourcedShow) async {
        do {
            try await source(show.source)?.updateSettings(settings, showId: show.show.id)
            await reloadLists()
        } catch {
            actionError = Self.message(for: error)
        }
    }

    func show(for episode: SourcedEpisode) -> Show? {
        shows.first { $0.source == episode.source && $0.show.id == episode.episode.showId }?.show
    }

    // MARK: - Episodes

    func progress(of episode: SourcedEpisode) -> ListeningProgress? { progress[episode.id] }

    func dismiss(_ episode: SourcedEpisode) async {
        inbox.removeAll { $0.id == episode.id }
        try? await source(episode.source)?.dismissFromInbox([episode.episode.key])
    }

    func markPlayed(_ episode: SourcedEpisode, _ played: Bool) async {
        do {
            try await source(episode.source)?.markPlayed(episode.episode.key, played)
            progress[episode.id] = ListeningProgress(positionMs: played ? (progress[episode.id]?.positionMs ?? 0) : 0, played: played)
            if played { inbox.removeAll { $0.id == episode.id } }
            if episode.source == .phone { scheduleSync() }
        } catch {
            actionError = Self.message(for: error)
        }
    }

    // MARK: - Playing

    struct PendingResume: Identifiable {
        let id = UUID()
        let episode: SourcedEpisode
        let localMs: Int64
        let otherMs: Int64
    }

    /// Another device got somewhere else in the episode; asked, never applied silently.
    var pendingResume: PendingResume?

    func play(_ item: SourcedEpisode, startAt: Int64? = nil) async {
        guard let source = source(item.source) else { return }
        let local = progress[item.id]
        var start: Int64
        if let startAt {
            start = startAt
        } else {
            // A server may know a newer position from another device.
            let remote = item.source == .phone || isOffline ? nil : try? await source.progress(item.episode.key)
            if let local, let remote, !local.played, !remote.played, abs(local.positionMs - remote.positionMs) > 30_000, local.positionMs > 0 {
                pendingResume = PendingResume(episode: item, localMs: local.positionMs, otherMs: remote.positionMs)
                return
            }
            let newest = [local, remote].compactMap { $0 }.max { $0.updatedAt < $1.updatedAt }
            start = newest.map { $0.played ? 0 : $0.positionMs } ?? 0
        }
        let show = show(for: item)
        if start == 0, let skip = show?.settings.skipIntroSecs, skip > 0 { start = Int64(skip * 1000) }
        do {
            let playback = try await source.playback(item.episode.key)
            let duration = item.episode.durationMs ?? 0
            let chapters = await chapters(for: item.episode, durationMs: duration)
            let spoken = SpokenBook(
                id: item.id, title: item.episode.title, author: show?.title,
                parts: [SpokenPart(id: "audio", url: playback.url, durationMs: duration, isHLS: playback.isHLS, contentType: item.episode.audioType ?? Self.audioType(forExtension: item.episode.audioURL?.pathExtension))], chapters: chapters
            )
            nowPlaying = item
            nowPlayingShow = show
            engine.load(spoken, at: start, autoplay: true)
            engine.setRate(show?.settings.speed ?? settings.defaultRate)
        } catch {
            actionError = Self.message(for: error)
        }
    }

    /// The type of an episode whose source names none, from its original file's extension.
    static func audioType(forExtension ext: String?) -> String? {
        switch ext?.lowercased() {
        case "mp3": "audio/mpeg"
        case "m4a", "m4b", "mp4", "aac": "audio/mp4"
        case "ogg", "oga", "opus": "audio/ogg"
        case "flac": "audio/flac"
        case "wav": "audio/wav"
        default: nil
        }
    }

    /// Lets go of the episode everywhere: the engine, the mini player, the lock screen.
    func stopPlayback() {
        engine.stop()
        nowPlaying = nil
        nowPlayingShow = nil
    }

    func setRate(_ rate: Float) {
        engine.setRate(min(max(rate, 0.5), 3.0))
    }

    func applyPlaybackSettings() {
        engine.skipForwardSecs = settings.skipForwardSecs
        engine.skipBackwardSecs = settings.skipBackwardSecs
        engine.smartRewind = SmartRewind(isEnabled: settings.smartRewind)
    }

    /// The feed's chapters: inline ones, else the linked JSON document. Times past the end are
    /// dropped; the last runs to the end of the episode.
    private func chapters(for episode: Episode, durationMs: Int64) async -> [SpokenChapter] {
        var marks = episode.chapters.filter(\.isInTableOfContents).map { ($0.startMs, $0.endMs, $0.title) }
        if marks.isEmpty, let url = episode.chaptersURL, !isOffline,
           let (data, _) = try? await Self.session.data(from: url), let parsed = try? Chapters.parse(data) {
            marks = parsed.filter(\.isInTableOfContents).map { ($0.startMs, $0.endMs, $0.title) }
        }
        marks.sort { $0.0 < $1.0 }
        // Unknown length: an hour past the last start stands in until the file says.
        let end = durationMs > 0 ? durationMs : (marks.last?.0 ?? 0) + 3_600_000
        return marks.enumerated().compactMap { index, mark in
            guard durationMs == 0 || mark.0 < durationMs else { return nil }
            let next = index + 1 < marks.count ? marks[index + 1].0 : end
            return SpokenChapter(title: FeedKit.Mojibake.repair(mark.2), startMs: mark.0, endMs: min(mark.1 ?? next, next))
        }
    }

    private func positionReported(_ position: SpokenEngine.Position) {
        guard let (ref, key) = SourcedEpisode.parse(position.bookId), let source = source(ref) else { return }
        let played = position.finished || ListeningProgress.reachedEnd(positionMs: position.positionMs, durationMs: engine.durationMs)
        let value = ListeningProgress(positionMs: position.positionMs, played: played, updatedAt: position.at)
        progress[position.bookId] = value
        if played { inbox.removeAll { $0.id == position.bookId } }
        Task { _ = try? await source.saveProgress(value, for: key) }
        if ref == .phone, [.pause, .stop, .finished].contains(position.reason) { scheduleSync() }
    }

    private func artwork(for id: String) async -> NowPlayingImage? {
        guard let item = nowPlaying, item.id == id,
              let url = item.episode.imageURL ?? nowPlayingShow?.imageURL,
              let (data, _) = try? await Self.session.data(from: url) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Searching

    func search(_ term: String) async throws -> [ShowSearchResult] {
        try await ITunesShowSearch(session: Self.session).search(term)
    }

    // MARK: - Servers

    struct PendingTwoFactor: Identifiable {
        let id = UUID()
        let host: URL
        let mfaToken: String
        let email: String
        /// Signing in again to this server rather than adding one.
        var replacing: UUID?
    }

    var pendingTwoFactor: PendingTwoFactor?

    /// `kind` nil: whatever answers at the address, found out first (own.audio, podfetch and
    /// other gPodder servers, Audiobookshelf).
    func addServer(kind: ServerKind?, address: String, username: String, password: String) async throws {
        guard let kind else {
            switch await ServerDetector(session: Self.session).detect(address) {
            case .ownAudio(let host)?: try await addServer(kind: .ownAudio, address: host.absoluteString, username: username, password: password)
            case .audiobookshelf(let host)?: try await addServer(kind: .audiobookshelf, address: host.absoluteString, username: username, password: password)
            case .gpodder(let host)?: try await addServer(kind: .gpodder, address: host.absoluteString, username: username, password: password)
            case nil: throw AddServerError.notRecognised
            }
            return
        }
        var lastError: Error = SourceError.network
        for host in Self.candidates(for: address, kind: kind) {
            do {
                let record: ServerRecord
                switch kind {
                case .ownAudio:
                    let tokens: OwnAudioKit.Tokens
                    do {
                        tokens = try await OwnAudioClient.signIn(host: host, email: username, password: password, device: Self.ownAudioDevice, session: Self.session)
                    } catch OwnAudioError.twoFactorRequired(let mfaToken, _) {
                        pendingTwoFactor = PendingTwoFactor(host: host, mfaToken: mfaToken, email: username)
                        return
                    }
                    record = ServerRecord(displayName: Self.displayName(host), kind: .ownAudio, host: host, username: username, ownAudioTokens: tokens)
                case .audiobookshelf:
                    let signIn = try await AudiobookshelfClient.signIn(host: host, username: username, password: password, session: Self.session)
                    let client = AudiobookshelfClient(host: host, tokens: AudiobookshelfKit.TokenSession(signIn.tokens), session: Self.session)
                    guard try await !client.podcastLibraries().isEmpty else { throw AddServerError.noPodcastLibrary }
                    record = ServerRecord(displayName: Self.displayName(host), kind: .audiobookshelf, host: host, username: signIn.user.username, audiobookshelfTokens: signIn.tokens, canAddShows: signIn.user.permissions.upload)
                case .gpodder:
                    let client = GPodderClient(host: host, username: username, password: password, session: Self.session)
                    try await client.login()
                    try await client.registerDevice(id: Self.gpodderDevice, caption: UIDevice.current.name)
                    record = ServerRecord(displayName: Self.displayName(host), kind: .gpodder, host: host, username: username, password: password,
                                          software: await Self.isPodfetch(host) ? "podfetch" : nil)
                }
                try await save(record)
                return
            } catch let error where Self.isUnreachable(error) {
                lastError = error
            }
        }
        throw lastError
    }

    func finishTwoFactor(code: String) async throws {
        guard let pending = pendingTwoFactor else { return }
        let tokens = try await OwnAudioClient.finishTwoFactor(host: pending.host, mfaToken: pending.mfaToken, code: code, session: Self.session)
        pendingTwoFactor = nil
        if let id = pending.replacing, var record = server(id) {
            record.ownAudioTokens = tokens
            record.username = pending.email
            try await update(record)
            return
        }
        try await save(ServerRecord(displayName: Self.displayName(pending.host), kind: .ownAudio, host: pending.host, username: pending.email, ownAudioTokens: tokens))
    }

    func addDemoServer() async throws {
        struct Body: Decodable {
            struct Demo: Decodable { let email: String; let password: String }
            let demo: Demo?
        }
        guard let (data, _) = try? await Self.session.data(from: Self.demoHost.appending(path: "api/v1/server")),
              let demo = try? JSONDecoder().decode(Body.self, from: data).demo else { throw SourceError.network }
        try await addServer(kind: .ownAudio, address: Self.demoHost.absoluteString, username: demo.email, password: demo.password)
        if let index = servers.firstIndex(where: { $0.host == Self.demoHost }) {
            servers[index].displayName = String(localized: "own.audio demo")
            try? await store.update(servers[index])
        }
    }

    func removeServer(_ id: UUID) async {
        if activeSource?.serverId == id { activeSource = nil }
        serverIcons[id] = nil
        if case .server(id)? = nowPlaying?.source { stopPlayback() }
        try? await store.remove(id: id)
        servers.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: serverDirectory(id))
        rebuildSources()
        await reloadLists()
    }

    private func save(_ record: ServerRecord) async throws {
        try await store.add(record)
        servers.append(record)
        rebuildSources()
        Task {
            await loadServerIcons()
            await loadLibraries()
        }
        if record.kind == .gpodder, let sync = syncs[record.id] {
            _ = try? await sync.sync()
            await noteAccountFeeds()
        }
        await reloadLists()
    }

    // MARK: - Connections

    enum ConnectionState: Equatable { case checking, connected(URL), unreachable }

    struct ConnectionCheck {
        enum Status { case ok, rejected, unreachable }
        let status: Status
        let at: Date
    }

    private(set) var connectionStates: [UUID: ConnectionState] = [:]
    private(set) var connectionChecks: [UUID: ConnectionCheck] = [:]
    private(set) var checkingConnections: Set<UUID> = []
    /// What the server says it is: its version, for the server page.
    private(set) var serverVersions: [UUID: String] = [:]
    private(set) var lastSyncs: [UUID: Date] = [:]
    @ObservationIgnored private var chosenAddresses: [UUID: URL] = [:]

    /// Each server's own icon, as the server itself serves it (Audiobookshelf's, podfetch's…),
    /// loaded at run time and kept beside its data, so the app ships no one else's artwork.
    private(set) var serverIcons: [UUID: UIImage] = [:]

    func icon(_ ref: SourceRef) -> UIImage? {
        ref.serverId.flatMap { serverIcons[$0] }
    }

    /// Each Audiobookshelf server's podcast libraries, read again and kept on its record.
    func loadLibraries() async {
        guard !isOffline else { return }
        for record in servers where record.kind == .audiobookshelf {
            guard let abs = sources[record.id] as? AudiobookshelfPodcastSource,
                  let found = try? await abs.podcastLibraries() else { continue }
            let libraries = found.map { ServerLibrary(id: $0.id, name: $0.name) }
            if libraries != record.libraries {
                var updated = record
                updated.libraries = libraries
                try? await update(updated, rebuild: false)
            }
        }
    }

    func setLibrary(_ library: String, hidden: Bool, on id: UUID) async {
        guard var record = server(id) else { return }
        record.hiddenLibraries.removeAll { $0 == library }
        if hidden { record.hiddenLibraries.append(library) }
        if case .library(id, library)? = activeSource, hidden { activeSource = .server(id) }
        try? await update(record, rebuild: false)
        await reloadLists()
    }

    /// Where each kind of server keeps its icon, best first.
    private static func iconPaths(_ record: ServerRecord) -> [String] {
        switch record.kind {
        case .ownAudio: []
        case .audiobookshelf: ["icon192.png", "icon64.png", "favicon.ico"]
        case .gpodder: record.software == "podfetch" ? ["ui/logo.png", "ui/favicon.ico"] : ["apple-touch-icon.png", "favicon.ico"]
        }
    }

    /// From disk first; asked of the server when there is none yet (or `force`).
    func loadServerIcons(force: Bool = false) async {
        for record in servers where !Self.iconPaths(record).isEmpty {
            let file = serverDirectory(record.id).appendingPathComponent("icon.png")
            if !force, serverIcons[record.id] == nil, let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
                serverIcons[record.id] = image
            }
            guard force || serverIcons[record.id] == nil, !isOffline else { continue }
            let host = address(for: record)
            for path in Self.iconPaths(record) {
                guard let (data, response) = try? await Self.probeSession.data(from: host.appending(path: path)),
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      (response.mimeType ?? "").hasPrefix("image/"),
                      let image = UIImage(data: data), image.size.width >= 16 else { continue }
                serverIcons[record.id] = image
                try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? image.pngData()?.write(to: file, options: .atomic)
                break
            }
        }
    }

    /// The address requests go to: the one chosen on this network, else the fixed one, else the
    /// one the server was added with.
    func address(for record: ServerRecord) -> URL {
        chosenAddresses[record.id] ?? record.fixedAddress ?? record.host
    }

    /// Short timeouts: an address on another network should fail fast, not hold the others up.
    private static let probeSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 4
        configuration.httpAdditionalHeaders = ["User-Agent": "own.audio Podcasts/\(appVersion) iOS"]
        return URLSession(configuration: configuration)
    }()

    /// For every server, the address that answers fastest on this network (or the fixed one, if
    /// it answers); the clients are rebuilt when one changes.
    func chooseAddresses() async {
        guard !settings.offlineMode else { return }
        var changed = false
        for record in servers {
            if connectionStates[record.id] == nil { connectionStates[record.id] = .checking }
            if let best = await bestAddress(record) {
                if chosenAddresses[record.id] != best { chosenAddresses[record.id] = best; changed = true }
                connectionStates[record.id] = .connected(best)
            } else {
                connectionStates[record.id] = .unreachable
            }
        }
        if changed { rebuildSources() }
    }

    private func bestAddress(_ record: ServerRecord) async -> URL? {
        if let fixed = record.fixedAddress { return await answers(record, at: fixed) ? fixed : nil }
        let candidates = record.candidateAddresses.map(\.url)
        return await withTaskGroup(of: URL?.self) { group in
            for url in candidates {
                group.addTask { await self.answers(record, at: url) ? url : nil }
            }
            for await found in group {
                if let found {
                    group.cancelAll()
                    return found
                }
            }
            return nil
        }
    }

    /// Whether `url` answers as this server: own.audio with its identity, Audiobookshelf with its
    /// status, a gPodder server with any answer from its API.
    nonisolated private func answers(_ record: ServerRecord, at url: URL) async -> Bool {
        switch record.kind {
        case .ownAudio:
            guard let (data, response) = try? await Self.probeSession.data(from: url.appending(path: "api/v1/server")),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
            if let identity = record.serverIdentity { return json["id"] as? String == identity }
            return true
        case .audiobookshelf:
            guard let (_, response) = try? await Self.probeSession.data(from: url.appending(path: "status")) else { return false }
            return (response as? HTTPURLResponse)?.statusCode == 200
        case .gpodder:
            guard let (_, response) = try? await Self.probeSession.data(from: url.appending(path: "api/2/devices/own-audio-probe.json")),
                  let status = (response as? HTTPURLResponse)?.statusCode else { return false }
            return status < 500 && status != 404
        }
    }

    /// The server page's button: the addresses again, then the sign-in, and what the server says
    /// about itself (own.audio names its other addresses, which are learned).
    func checkNow(id: UUID) async {
        guard let record = server(id) else { return }
        checkingConnections.insert(id)
        defer { checkingConnections.remove(id) }
        await chooseAddresses()
        guard case .connected(let url)? = connectionStates[id] else {
            connectionChecks[id] = ConnectionCheck(status: .unreachable, at: Date())
            return
        }
        await learnAboutServer(record, at: url)
        let status: ConnectionCheck.Status
        do {
            switch record.kind {
            case .gpodder:
                guard let password = record.password else { throw GPodderError.unauthorized }
                try await GPodderClient(host: url, username: record.username, password: password, session: Self.session).login()
            case .ownAudio, .audiobookshelf:
                _ = try await source(.server(id))?.shows()
            }
            status = .ok
        } catch let error where Self.isUnreachable(error) {
            status = .unreachable
        } catch {
            status = .rejected
        }
        connectionChecks[id] = ConnectionCheck(status: status, at: Date())
    }

    private func learnAboutServer(_ record: ServerRecord, at url: URL) async {
        switch record.kind {
        case .ownAudio:
            guard let (data, _) = try? await Self.probeSession.data(from: url.appending(path: "api/v1/server")),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
            serverVersions[record.id] = json["version"] as? String
            var updated = record
            if updated.serverIdentity == nil { updated.serverIdentity = json["id"] as? String }
            let known = Set(updated.candidateAddresses.map { ServerAddress.normalized($0.url) })
            for entry in json["addresses"] as? [[String: Any]] ?? [] {
                guard let text = entry["url"] as? String, let named = URL(string: text), !known.contains(ServerAddress.normalized(named)) else { continue }
                updated.addresses.append(ServerAddress(url: named, origin: .server))
            }
            if updated != record { try? await update(updated, rebuild: false) }
        case .audiobookshelf:
            guard let (data, _) = try? await Self.probeSession.data(from: url.appending(path: "status")),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
            serverVersions[record.id] = json["serverVersion"] as? String
        case .gpodder:
            if await Self.isPodfetch(url) {
                serverVersions[record.id] = "podfetch"
                if record.software != "podfetch" {
                    var updated = record
                    updated.software = "podfetch"
                    try? await update(updated, rebuild: false)
                }
            }
        }
    }

    /// podfetch answers its own configuration endpoint; other gPodder servers don't.
    nonisolated static func isPodfetch(_ host: URL) async -> Bool {
        guard let (data, _) = try? await probeSession.data(from: host.appending(path: "api/v1/sys/config")),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        return json["rssFeed"] != nil && json["basicAuth"] != nil
    }

    /// Saves a changed record (a new name, address or sign-in) and rebuilds what uses it.
    func update(_ record: ServerRecord, rebuild: Bool = true) async throws {
        try await store.update(record)
        if let index = servers.firstIndex(where: { $0.id == record.id }) { servers[index] = record }
        if rebuild {
            chosenAddresses[record.id] = nil
            rebuildSources()
            await chooseAddresses()
            await reloadLists()
        }
    }

    func rename(id: UUID, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var record = server(id), !trimmed.isEmpty else { return }
        record.displayName = trimmed
        try? await update(record, rebuild: false)
    }

    func addAddress(_ text: String, to id: UUID) async throws {
        guard var record = server(id) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let withScheme = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard let url = URL(string: withScheme), url.host() != nil else { throw AddServerError.badAddress }
        guard !record.candidateAddresses.contains(where: { ServerAddress.normalized($0.url) == ServerAddress.normalized(url) }) else { return }
        record.addresses.append(ServerAddress(url: url, origin: .user))
        try await update(record)
    }

    func removeAddress(_ url: URL, from id: UUID) async {
        guard var record = server(id) else { return }
        record.addresses.removeAll { $0.url == url }
        if record.fixedAddress == url { record.fixedAddress = nil }
        try? await update(record)
    }

    func setFixedAddress(_ url: URL?, for id: UUID) async {
        guard var record = server(id) else { return }
        record.fixedAddress = url
        try? await update(record)
    }

    /// The same account, signed in again (a changed password, a refused refresh).
    func signInAgain(id: UUID, username: String, password: String) async throws {
        guard var record = server(id) else { return }
        let host = address(for: record)
        switch record.kind {
        case .ownAudio:
            do {
                record.ownAudioTokens = try await OwnAudioClient.signIn(host: host, email: username, password: password, device: Self.ownAudioDevice, session: Self.session)
            } catch OwnAudioError.twoFactorRequired(let mfaToken, _) {
                pendingTwoFactor = PendingTwoFactor(host: host, mfaToken: mfaToken, email: username, replacing: id)
                return
            }
        case .audiobookshelf:
            let signIn = try await AudiobookshelfClient.signIn(host: host, username: username, password: password, session: Self.session)
            record.audiobookshelfTokens = signIn.tokens
            record.canAddShows = signIn.user.permissions.upload
        case .gpodder:
            try await GPodderClient(host: host, username: username, password: password, session: Self.session).login()
            record.password = password
        }
        record.username = username
        try await update(record)
        connectionChecks[id] = nil
    }

    /// A gPodder account's sync, now.
    func syncNow(id: UUID) async throws {
        guard let sync = syncs[id] else { return }
        try await sync.sync()
        lastSyncs[id] = Date()
        await noteAccountFeeds()
        await reloadLists()
    }

    private static var ownAudioDevice: OwnAudioClient.Device {
        OwnAudioClient.Device(name: UIDevice.current.name, kind: "ios")
    }

    private static func displayName(_ host: URL) -> String { host.host() ?? host.absoluteString }

    /// The addresses to try for what was typed. The hosted service's web addresses mean its API;
    /// with no scheme, HTTPS first and then plain HTTP (a home server on the LAN).
    static func candidates(for typed: String, kind: ServerKind) -> [URL] {
        var text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        if kind == .ownAudio {
            let bare = text.lowercased().replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
            if ["own.audio", "www.own.audio", "app.own.audio"].contains(bare) { return [URL(string: "https://api.own.audio")!] }
        }
        guard !text.isEmpty else { return [] }
        if text.hasPrefix("http://") || text.hasPrefix("https://") { return URL(string: text).map { [$0] } ?? [] }
        return ["https://", "http://"].compactMap { URL(string: $0 + text) }.filter { $0.host() != nil }
    }

    private static func isUnreachable(_ error: Error) -> Bool {
        switch error {
        case SourceError.network, OwnAudioError.network, AudiobookshelfError.network, GPodderError.network: true
        case OwnAudioError.decoding, AudiobookshelfError.decoding, GPodderError.decoding: true
        case OwnAudioError.http(404), AudiobookshelfError.http(404, _), GPodderError.http(404): true
        default: false
        }
    }

    enum AddServerError: Error { case noPodcastLibrary, notRecognised, badAddress }

    /// What the listener is told when something fails.
    static func message(for error: Error) -> String {
        switch error {
        case SourceError.notAFeed:
            String(localized: "That address is not a podcast feed.")
        case SourceError.signInRejected, AudiobookshelfError.invalidCredentials, GPodderError.unauthorized, OwnAudioError.problem:
            String(localized: "The name or password is wrong.")
        case AudiobookshelfError.signedOut, OwnAudioError.signedOut:
            String(localized: "The server signed this iPhone out. Remove the server and add it again.")
        case AddServerError.badAddress:
            String(localized: "That doesn't look like a server address.")
        case AddServerError.notRecognised:
            String(localized: "No own.audio, Audiobookshelf or gPodder server answers at that address.")
        case GPodderError.http(409):
            String(localized: "The server refuses this account for syncing. On podfetch the admin account can't sync: add a separate user there and sign in with it.")
        case AddServerError.noPodcastLibrary:
            String(localized: "This account has no podcast library on the server.")
        case _ where isUnreachable(error):
            String(localized: "The server can't be reached. Check the address and the network.")
        default:
            String(localized: "Something went wrong. Try again.")
        }
    }
}
