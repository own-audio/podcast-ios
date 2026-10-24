import Foundation
import PlayerCore
import PodcastLibrary
import SpokenEngine
import Testing
@testable import OwnAudioPodcasts

/// An episode plays from the phone whenever it is there — the listener's download, then the
/// listening cache, then the stream — and only the file itself streams through the look-ahead
/// window. Ported from own.audio Books' `PartLocatorTests`.
@MainActor
@Suite("Part locator", .serialized)
struct PartLocatorTests {
    private func url(_ name: String) -> URL { URL(fileURLWithPath: "/phone/\(name)") }

    private func locator(downloaded: Set<String>, cached: Set<String>) -> PartLocator {
        let downloadedURLs = Dictionary(uniqueKeysWithValues: downloaded.map { ($0, url("download-\($0)")) })
        let cachedURLs = Dictionary(uniqueKeysWithValues: cached.map { ($0, url("cache-\($0)")) })
        return PartLocator(downloaded: { downloadedURLs[$0] }, cached: { cachedURLs[$0] })
    }

    private func episode(_ id: String) -> SourcedEpisode {
        SourcedEpisode(source: .phone, episode: Episode(id: id, showId: "show", title: "Episode \(id)", durationMs: 60_000))
    }

    @Test("the download wins over the listening cache, which wins over the stream")
    func order() async {
        let locator = locator(downloaded: ["a"], cached: ["a", "b"])
        #expect(await locator.locate("a") == .downloaded(url("download-a")))
        #expect(await locator.locate("b") == .cached(url("cache-b")), "a cached episode doesn't stream")
        #expect(await locator.locate("c") == .stream)
    }

    @Test("the file itself streams through the look-ahead window with its type; HLS and a server's transcode don't")
    func windowedParts() {
        let link = URL(string: "https://cdn.example/e.mp3")!
        let original = PartLocator.streamedPart(Playback(url: link, isServerFile: false), durationMs: 1000, contentType: "audio/mpeg")
        #expect(original.streamsByRange && original.contentType == "audio/mpeg" && original.id == AppModel.episodePartId)
        let hls = PartLocator.streamedPart(Playback(url: link, isServerFile: true, isHLS: true), durationMs: 1000, contentType: "audio/ogg")
        #expect(!hls.streamsByRange && hls.isHLS && hls.contentType == nil)
        let transcode = PartLocator.streamedPart(Playback(url: link, isServerFile: true, isTranscode: true), durationMs: 1000, contentType: "audio/ogg")
        #expect(!transcode.streamsByRange && transcode.contentType == nil, "made as it plays: no Range, and not the episode's type")
    }

    @Test("the ids in the listening cache are read back from its file names, as the cache itself finds them")
    func cachedIds() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ids = ["server:5F2C|show/1|ep?=+", "phone|https://feed.example/a?b=c"]
        for id in ids { try Data("x".utf8).write(to: directory.appendingPathComponent(Self.cacheName(id) + ".mp3")) }
        #expect(PartLocator.cachedIds(in: directory) == Set(ids))
        // The same names the cache uses: it finds the files written here.
        let cache = TrackFileCache(remoteURL: { _ in throw URLError(.notConnectedToInternet) }, cacheDirectory: directory)
        for id in ids { #expect(await cache.existingLocalURL(trackId: id) != nil, "\(id)") }
    }

    /// `TrackFileCache`'s file name for an id.
    static func cacheName(_ id: String) -> String {
        Data(id.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
    }

    @Test("offline, an episode whole in the listening cache can play; one that is nowhere on the phone can't")
    func offlinePlayable() async throws {
        let model = AppModel.shared
        let before = model.settings.offlineMode
        defer { model.settings.offlineMode = before }
        let cached = episode("cached-\(UUID().uuidString)")
        let file = AppModel.listeningCacheDirectory.appendingPathComponent(Self.cacheName(cached.id) + ".mp3")
        try FileManager.default.createDirectory(at: AppModel.listeningCacheDirectory, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        await model.refreshCachedIds()
        model.settings.offlineMode = true
        #expect(model.canPlay(cached), "it plays from disk, so it isn't greyed out")
        #expect(!model.canPlay(episode("nowhere")))
        model.settings.offlineMode = false
        #expect(model.canPlay(episode("nowhere")), "online everything plays")
    }

    @Test("the window is 10 minutes unless chosen otherwise, and the choice is kept")
    func lookAheadSetting() throws {
        let defaults = try #require(UserDefaults(suiteName: "lookahead-\(UUID().uuidString)"))
        #expect(PlaybackSettings(defaults: defaults).lookAheadMinutes == 10)
        PlaybackSettings(defaults: defaults).lookAheadMinutes = 15
        #expect(PlaybackSettings(defaults: defaults).lookAheadMinutes == 15)
        #expect(PlaybackSettings.lookAheadChoices == [5, 10, 15] && PlaybackSettings.constrainedLookAheadMinutes == 5)
        let model = AppModel.shared
        let before = model.settings.lookAheadMinutes
        defer { model.settings.lookAheadMinutes = before; model.applyPlaybackSettings() }
        model.settings.lookAheadMinutes = 5
        model.applyPlaybackSettings()
        #expect(model.streamWindow.lookAheadSecs == 300)
        #expect(model.engine.window === model.streamWindow)
    }

    @Test("no network makes the player wait; Offline Mode by choice is a message")
    func messages() async throws {
        #expect(PartNotOnPhone().errorDescription?.isEmpty == false)
        #expect(!SpokenEngine.isNetworkUnavailable(PartNotOnPhone()), "nothing to wait for in Offline Mode")
        #expect(SpokenEngine.isNetworkUnavailable(NoSignal()))
        #expect(SpokenEngine.isNetworkUnavailable(URLError(.notConnectedToInternet)))
        #expect(!SpokenEngine.isNetworkUnavailable(SourceError.notFound))
        // The app's refresher, in Offline Mode: the message, not a wait.
        let model = AppModel.shared
        let before = model.settings.offlineMode
        defer { model.settings.offlineMode = before }
        model.settings.offlineMode = true
        let refresher = try #require(model.engine.partRefresher)
        await #expect(throws: PartNotOnPhone.self) { _ = try await refresher("anything", AppModel.episodePartId) }
    }

    @Test("a download finishing while its episode plays reaches the player, and only for that episode")
    func downloadWhilePlaying() {
        let model = AppModel.shared
        let id = "phone|mid-episode-\(UUID().uuidString)"
        let spoken = SpokenBook(id: id, title: "T", author: nil, parts: [
            SpokenPart(id: AppModel.episodePartId, url: URL(string: "https://feed.example/e.mp3")!, durationMs: 1000, isHLS: true),
        ], chapters: [])
        model.engine.load(spoken, at: 0, autoplay: false)
        defer { model.engine.stop(reporting: false) }
        model.downloads.onFileReady?("phone|another", url("other"))
        #expect(model.engine.book?.timeline.parts[0].url.isFileURL == false)
        model.downloads.onFileReady?(id, url("download"))
        #expect(model.engine.book?.timeline.parts[0].url == url("download"))
    }
}
