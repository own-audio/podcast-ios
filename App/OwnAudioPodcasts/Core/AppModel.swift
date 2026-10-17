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

    var id: String {
        switch self {
        case .phone: "phone"
        case .server(let id): id.uuidString
        }
    }

    init?(id: String) {
        if id == "phone" {
            self = .phone
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
            if connected { Task { await self?.refresh() } }
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

    func sourceName(_ ref: SourceRef) -> String {
        switch ref {
        case .phone: String(localized: "This iPhone")
        case .server(let id): server(id)?.displayName ?? String(localized: "Removed server")
        }
    }

    func capabilities(_ ref: SourceRef) -> Capabilities {
        source(ref)?.capabilities ?? []
    }

    /// Where shows can be followed: the phone always, and every server that takes a feed URL.
    var followTargets: [SourceRef] {
        [.phone] + servers.filter { $0.kind != .gpodder && sources[$0.id]?.capabilities.contains(.addByURL) == true }.map { .server($0.id) }
    }

    func source(_ ref: SourceRef) -> (any PodcastSource)? {
        switch ref {
        case .phone: phone
        case .server(let id): sources[id]
        }
    }

    // MARK: - Loading

    func load() async {
        guard !hasLoaded else { return }
        if UITestFlags.isUITesting { await store.clear() }
        servers = await store.loadAll()
        rebuildSources()
        await addFromLaunchArguments()
        await reloadLists()
        hasLoaded = true
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
                let client = OwnAudioClient(host: record.host, tokens: tokens, session: Self.session)
                sources[record.id] = OwnAudioPodcastSource(client: client, store: ListeningStore(directory: serverDirectory(record.id)))
            case .audiobookshelf:
                let tokens = AudiobookshelfKit.TokenSession(record.audiobookshelfTokens, keeper: AudiobookshelfTokenKeeper(store: store, serverId: record.id))
                let client = AudiobookshelfClient(host: record.host, tokens: tokens, session: Self.session)
                sources[record.id] = AudiobookshelfPodcastSource(client: client, store: ListeningStore(directory: serverDirectory(record.id)), fetcher: FeedFetcher(session: Self.session), canAddShows: record.canAddShows)
            case .gpodder:
                guard let password = record.password else { continue }
                let client = GPodderClient(host: record.host, username: record.username, password: password, session: Self.session)
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
                allShows += try await source.shows().map { SourcedShow(source: ref, show: $0) }
                allInbox += try await source.inbox(limit: 200).map { SourcedEpisode(source: ref, episode: $0) }
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
        for sync in syncs.values { _ = try? await sync.sync() }
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
        let show = try await source.follow(feedURL: feedURL)
        await reloadLists()
        if ref == .phone { scheduleSync() }
        return SourcedShow(source: ref, show: show)
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
                parts: [SpokenPart(id: "audio", url: playback.url, durationMs: duration, contentType: item.episode.audioType ?? Self.audioType(forExtension: item.episode.audioURL?.pathExtension))], chapters: chapters
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
                    record = ServerRecord(displayName: Self.displayName(host), kind: .gpodder, host: host, username: username, password: password)
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
        if record.kind == .gpodder, let sync = syncs[record.id] {
            _ = try? await sync.sync()
        }
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

    enum AddServerError: Error { case noPodcastLibrary, notRecognised }

    /// What the listener is told when something fails.
    static func message(for error: Error) -> String {
        switch error {
        case SourceError.notAFeed:
            String(localized: "That address is not a podcast feed.")
        case SourceError.signInRejected, AudiobookshelfError.invalidCredentials, GPodderError.unauthorized, OwnAudioError.problem:
            String(localized: "The name or password is wrong.")
        case AudiobookshelfError.signedOut, OwnAudioError.signedOut:
            String(localized: "The server signed this iPhone out. Remove the server and add it again.")
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
