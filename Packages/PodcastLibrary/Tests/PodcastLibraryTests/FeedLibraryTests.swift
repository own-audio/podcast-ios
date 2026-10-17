import FeedKit
import Foundation
import Testing

@testable import PodcastLibrary

/// A feed whose content the test changes between fetches, and a clock it moves.
private final class World: @unchecked Sendable {
    var feeds: [String: String] = [:]
    var etags: [String: String] = [:]
    var time = Date(timeIntervalSince1970: 1_800_000_000)
    private let lock = NSLock()

    func feed(_ path: String) -> (String?, String?) { lock.withLock { (feeds[path], etags[path]) } }
    func set(_ path: String, _ xml: String, etag: String? = nil) { lock.withLock { feeds[path] = xml; etags[path] = etag } }
    func advance(_ seconds: TimeInterval) { lock.withLock { time += seconds } }
    var now: Date { lock.withLock { time } }
}

private func rss(title: String = "Show", serial: Bool = false, moved: String? = nil, items: [(id: String, day: Int, duration: String?)]) -> String {
    let entries = items.map { item in
        """
        <item><title>Episode \(item.id)</title><guid>\(item.id)</guid>
        <pubDate>\(String(format: "%02d", item.day)) Oct 2026 08:00:00 +0000</pubDate>
        <enclosure url="https://cdn.example.com/\(item.id).mp3" type="audio/mpeg" length="100"/>
        \(item.duration.map { "<itunes:duration>\($0)</itunes:duration>" } ?? "")</item>
        """
    }.joined(separator: "\n")
    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel>
    <title>\(title)</title><itunes:author>Host</itunes:author>
    \(serial ? "<itunes:type>serial</itunes:type>" : "")
    \(moved.map { "<itunes:new-feed-url>\($0)</itunes:new-feed-url>" } ?? "")
    <item><title>A post</title><guid>post</guid></item>
    \(entries)
    </channel></rss>
    """
}

private func makeLibrary(_ world: World, directory: URL? = nil) async -> (FeedLibrary, URL) {
    let mock = await MockURLProtocol.makeStubbedSession { request in
        let path = request.url?.path ?? ""
        let (xml, etag) = world.feed(path)
        guard let xml else { return .init(statusCode: 404, body: Data()) }
        if let etag, request.value(forHTTPHeaderField: "If-None-Match") == etag { return .init(statusCode: 304, body: Data()) }
        return .init(statusCode: 200, body: Data(xml.utf8), headers: etag.map { ["ETag": $0] } ?? [:])
    }
    let directory = directory ?? FileManager.default.temporaryDirectory.appendingPathComponent("feedlib-\(UUID().uuidString)", isDirectory: true)
    let library = FeedLibrary(directory: directory, fetcher: FeedFetcher(session: mock.urlSession), now: { world.now })
    return (library, directory)
}

private let feedURL = URL(string: "https://feeds.example.com/show.xml")!

@Suite("FeedLibrary")
struct FeedLibraryTests {
    @Test("following a feed keeps its audio episodes; the inbox holds only the newest one")
    func follow() async throws {
        let world = World()
        world.set("/show.xml", rss(items: [("e1", 1, "10:00"), ("e2", 2, "20:00"), ("e3", 3, nil)]))
        let (library, _) = await makeLibrary(world)
        let show = try await library.follow(feedURL: feedURL)
        #expect(show.title == "Show" && show.author == "Host" && show.feedURL == feedURL)
        #expect(try await library.episodes(showId: show.id).map(\.id) == ["e3", "e2", "e1"], "newest first; the post without audio is left out")
        #expect(await library.inbox().map(\.id) == ["e3"], "a new follow brings its latest episode, not the archive")
        let again = try await library.follow(feedURL: feedURL)
        let count = await library.shows().count
        #expect(again.id == show.id && count == 1, "following twice is one show")
    }

    @Test("a refresh brings new episodes into the inbox; known ones keep when they were first seen")
    func refresh() async throws {
        let world = World()
        world.set("/show.xml", rss(items: [("e1", 1, nil), ("e2", 2, nil)]), etag: "\"a\"")
        let (library, _) = await makeLibrary(world)
        let show = try await library.follow(feedURL: feedURL)
        let firstSeen = try await library.episode(EpisodeKey(showId: show.id, episodeId: "e1")).firstSeenAt
        #expect(await library.refresh().isEmpty, "unchanged (304): nothing new")
        world.advance(3600)
        world.set("/show.xml", rss(items: [("e1", 1, nil), ("e2", 2, nil), ("e4", 4, nil)]), etag: "\"b\"")
        let fresh = await library.refresh()
        #expect(fresh.map(\.id) == ["e4"])
        #expect(await library.inbox().map(\.id) == ["e4", "e2"])
        #expect(try await library.episode(EpisodeKey(showId: show.id, episodeId: "e1")).firstSeenAt == firstSeen)
    }

    @Test("a feed that moved is followed to its new address; a dropped episode stays only if it is being heard")
    func movedAndDropped() async throws {
        let world = World()
        world.set("/show.xml", rss(items: [("e1", 1, "60:00"), ("e2", 2, "60:00"), ("e3", 3, "60:00")]))
        let (library, _) = await makeLibrary(world)
        let show = try await library.follow(feedURL: feedURL)
        try await library.record(positionMs: 600_000, for: EpisodeKey(showId: show.id, episodeId: "e1"))
        world.advance(60)
        world.set("/show.xml", rss(moved: "https://new.example.com/show.xml", items: [("e3", 3, "60:00")]))
        _ = await library.refresh()
        #expect(await library.shows().first?.feedURL == URL(string: "https://new.example.com/show.xml"))
        #expect(Set(try await library.episodes(showId: show.id).map(\.id)) == ["e3", "e1"], "e1 is half heard and stays; e2 goes")
    }

    @Test("the queue: next, later, move, remove; when it runs out the inbox plays on")
    func queue() async throws {
        let world = World()
        world.set("/show.xml", rss(items: [("e1", 1, nil), ("e2", 2, nil), ("e3", 3, nil)]))
        let (library, _) = await makeLibrary(world)
        let show = try await library.follow(feedURL: feedURL)
        let key = { EpisodeKey(showId: show.id, episodeId: $0) }
        try await library.playLater(key("e1"))
        try await library.playLater(key("e2"))
        try await library.playNext(key("e3"))
        try await library.playLater(key("e1"))
        #expect(await library.queue().map(\.episodeId) == ["e3", "e1", "e2"], "next goes first; queuing twice is once")
        try await library.moveInQueue(from: [2], to: 0)
        #expect(await library.queue().map(\.episodeId) == ["e2", "e3", "e1"])
        try await library.removeFromQueue(key("e3"))
        #expect(try await library.takeNext(after: nil)?.id == "e2")
        #expect(try await library.takeNext(after: key("e2"))?.id == "e1")
        #expect(try await library.takeNext(after: key("e1"))?.id == "e3", "the queue is empty: the newest inbox episode")
        #expect(try await library.takeNext(after: key("e3")) == nil, "nothing else is new")
    }

    @Test("new episodes of a show set to auto-queue join the queue, oldest first")
    func autoQueue() async throws {
        let world = World()
        world.set("/show.xml", rss(items: [("e1", 1, nil)]))
        let (library, _) = await makeLibrary(world)
        let show = try await library.follow(feedURL: feedURL)
        try await library.updateSettings(ShowSettings(autoQueue: true), showId: show.id)
        world.advance(60)
        world.set("/show.xml", rss(items: [("e1", 1, nil), ("e3", 3, nil), ("e2", 2, nil)]))
        _ = await library.refresh()
        #expect(await library.queue().map(\.episodeId) == ["e2", "e3"])
    }

    @Test("positions: the end counts as heard, a stale report cannot move back, played leaves the inbox and the queue")
    func progress() async throws {
        let world = World()
        world.set("/show.xml", rss(items: [("e1", 1, "10:00")]))
        let (library, _) = await makeLibrary(world)
        let show = try await library.follow(feedURL: feedURL)
        let key = EpisodeKey(showId: show.id, episodeId: "e1")
        try await library.playLater(key)
        try await library.record(positionMs: 120_000, for: key)
        #expect(await library.progress(key)?.played == false)
        let stale = ListeningProgress(positionMs: 5_000, played: false, updatedAt: world.now.addingTimeInterval(-60))
        #expect(try await library.saveProgress(stale, for: key).positionMs == 120_000, "an older report loses")
        world.advance(10)
        try await library.record(positionMs: 580_000, for: key)
        #expect(await library.progress(key)?.played == true, "20 s before the end is heard")
        let (inbox, queue) = (await library.inbox(), await library.queue())
        #expect(inbox.isEmpty && queue.isEmpty)
        try await library.markPlayed(key, false)
        let (unplayed, position) = (await library.inbox(), await library.progress(key)?.positionMs)
        #expect(unplayed.map(\.id) == ["e1"] && position == 0)
    }

    @Test("everything is on disk: a new library over the same folder has the shows, queue, positions and dismissals")
    func persistence() async throws {
        let world = World()
        world.set("/show.xml", rss(items: [("e1", 1, "10:00"), ("e2", 2, "10:00")]))
        let (library, directory) = await makeLibrary(world)
        let show = try await library.follow(feedURL: feedURL)
        let key = { EpisodeKey(showId: show.id, episodeId: $0) }
        try await library.playLater(key("e1"))
        try await library.record(positionMs: 42_000, for: key("e1"))
        try await library.dismissFromInbox([key("e2")])
        try await library.updateSettings(ShowSettings(skipIntroSecs: 30, speed: 1.5), showId: show.id)
        let (reopened, _) = await makeLibrary(world, directory: directory)
        #expect(await reopened.shows().map(\.id) == [show.id])
        #expect(await reopened.shows().first?.settings == ShowSettings(skipIntroSecs: 30, speed: 1.5))
        #expect(await reopened.queue() == [key("e1")])
        #expect(await reopened.progress(key("e1"))?.positionMs == 42_000)
        #expect(await reopened.inbox().isEmpty, "e2 was dismissed")
        try await reopened.unfollow(showId: show.id)
        let (shows, queue) = (await reopened.shows(), await reopened.queue())
        #expect(shows.isEmpty && queue.isEmpty)
    }

    @Test("a page that is not a feed is refused as such")
    func notAFeed() async throws {
        let world = World()
        world.set("/page", "<!DOCTYPE html><html><body>hi</body></html>")
        let (library, _) = await makeLibrary(world)
        await #expect(throws: SourceError.notAFeed) { try await library.follow(feedURL: URL(string: "https://feeds.example.com/page")!) }
        await #expect(throws: SourceError.network) { try await library.follow(feedURL: URL(string: "https://feeds.example.com/missing")!) }
    }

    @Test("a serial show lists oldest first and brings nothing old into the inbox")
    func serial() async throws {
        let world = World()
        world.set("/show.xml", rss(serial: true, items: [("e1", 1, nil), ("e2", 2, nil)]))
        let (library, _) = await makeLibrary(world)
        let show = try await library.follow(feedURL: feedURL)
        #expect(try await library.episodes(showId: show.id).map(\.id) == ["e1", "e2"])
        #expect(await library.inbox().isEmpty)
    }
}

@Suite("Episode keys")
struct EpisodeKeyTests {
    @Test("a key round-trips through its text, ids with bars included")
    func roundTrip() {
        let key = EpisodeKey(showId: "S1", episodeId: "https://x.example/a|b")
        #expect(EpisodeKey(key.description) == key)
        #expect(EpisodeKey("no-bar") == nil)
    }

    @Test("the end of an episode counts as heard", arguments: [(Int64(570_001), true), (590_000, true), (500_000, false), (0, false)])
    func reachedEnd(position: Int64, heard: Bool) {
        #expect(ListeningProgress.reachedEnd(positionMs: position, durationMs: 600_000) == heard)
        #expect(!ListeningProgress.reachedEnd(positionMs: position, durationMs: nil))
    }
}

/// Follows the first of `FEED_URLS` for real, refreshes it, and reads the inbox.
@Suite("Feeds, live", .enabled(if: !(ProcessInfo.processInfo.environment["FEED_URLS"] ?? "").isEmpty))
struct FeedLibraryLiveTests {
    @Test("a real feed followed, refreshed conditionally, its newest episode in the inbox")
    func live() async throws {
        let url = try #require((ProcessInfo.processInfo.environment["FEED_URLS"] ?? "").split(separator: " ").first.flatMap { URL(string: String($0)) })
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("feedlib-live-\(UUID().uuidString)", isDirectory: true)
        let library = FeedLibrary(directory: directory)
        let show = try await library.follow(feedURL: url)
        #expect(!show.title.isEmpty)
        let episodes = try await library.episodes(showId: show.id)
        #expect(!episodes.isEmpty && episodes.allSatisfy { $0.audioURL != nil })
        #expect(await library.refresh().isEmpty, "a refresh right after the follow finds nothing new")
        #expect(await library.inbox().count == 1)
    }
}
