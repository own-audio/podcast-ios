import AudiobookshelfKit
import FeedKit
import Foundation
import Testing

@testable import PodcastLibrary

private let host = URL(string: "https://abs.example.com")!

/// A server with one podcast library and one show of two episodes on the server, whose feed has
/// a third the server never downloaded.
private func server(progress: [String: (Double, Bool, Int64)] = [:]) async -> MockURLProtocol.StubbedSession {
    let episodes = #"""
    [{"id":"ep1","libraryItemId":"show1","title":"On the server one","publishedAt":1791000000000,"duration":600,"guid":"g1","enclosure":{"url":"https://pub.example/1.mp3"},"audioFile":{"ino":"101","mimeType":"audio/mpeg","duration":600},"chapters":[{"id":0,"start":0,"end":300,"title":"A"},{"id":1,"start":300,"end":600,"title":"B"}]},
     {"id":"ep2","libraryItemId":"show1","title":"On the server two","publishedAt":1792000000000,"duration":1200,"audioFile":{"ino":"102","mimeType":"audio/mpeg","duration":1200},"chapters":[]}]
    """#
    let feed = """
    <?xml version="1.0"?><rss version="2.0"><channel><title>Show</title>
    <item><title>On the server one</title><guid>g1</guid><enclosure url="https://pub.example/1.mp3" type="audio/mpeg"/></item>
    <item><title>On the server two</title><guid>other-guid</guid><enclosure url="https://pub.example/2.mp3" type="audio/mpeg"/></item>
    <item><title>Only in the feed</title><guid>g3</guid><pubDate>Mon, 12 Oct 2026 08:00:00 +0000</pubDate><enclosure url="https://pub.example/3.mp3" type="audio/mpeg"/></item>
    </channel></rss>
    """
    let me = progress.map { key, value in
        #"{"id":"p-\#(key)","libraryItemId":"show1","episodeId":"\#(key)","duration":600,"progress":0.1,"currentTime":\#(value.0),"isFinished":\#(value.1),"hideFromContinueListening":false,"lastUpdate":\#(value.2)}"#
    }.joined(separator: ",")
    return await MockURLProtocol.makeStubbedSession { request in
        let path = request.url?.path ?? ""
        let json = { (body: String) in MockURLProtocol.StubbedResponse(statusCode: 200, body: Data(body.utf8), headers: ["Content-Type": "application/json"]) }
        switch (request.httpMethod ?? "GET", path) {
        case (_, "/feed.xml"): return .init(statusCode: 200, body: Data(feed.utf8))
        case ("GET", "/api/libraries"): return json(#"{"libraries":[{"id":"lib1","name":"Podcasts","mediaType":"podcast","folders":[{"id":"f1","fullPath":"/podcasts"}]},{"id":"lib2","name":"Books","mediaType":"book"}]}"#)
        case ("GET", "/api/libraries/lib1/items"):
            return json(#"{"results":[{"id":"show1","libraryId":"lib1","addedAt":1,"updatedAt":1,"media":{"metadata":{"title":"Show &amp; I&#39;m","feedUrl":"https://abs.example.com/feed.xml","type":"episodic"},"coverPath":"/c.jpg","numEpisodes":2}}],"total":1,"limit":200,"page":0}"#)
        case ("GET", "/api/items/show1"):
            return json(#"{"id":"show1","libraryId":"lib1","addedAt":1,"updatedAt":1,"media":{"metadata":{"title":"Show","feedUrl":"https://abs.example.com/feed.xml"},"coverPath":"/c.jpg","episodes":\#(episodes)}}"#)
        case ("GET", "/api/libraries/lib1/recent-episodes"): return json(#"{"episodes":\#(episodes),"limit":100,"page":0}"#)
        case ("GET", "/api/me"): return json(#"{"id":"u1","username":"t","type":"user","mediaProgress":[\#(me)]}"#)
        case ("GET", let p) where p.hasPrefix("/api/me/progress/show1/"):
            let id = String(p.split(separator: "/").last ?? "")
            guard let value = progress[id] else { return .init(statusCode: 404, body: Data()) }
            return json(#"{"id":"p-\#(id)","libraryItemId":"show1","episodeId":"\#(id)","duration":600,"progress":0.1,"currentTime":\#(value.0),"isFinished":\#(value.1),"hideFromContinueListening":false,"lastUpdate":\#(value.2)}"#)
        case ("PATCH", _): return .init(statusCode: 200, body: Data("OK".utf8))
        default: return .init(statusCode: 404, body: Data())
        }
    }
}

private func source(_ mock: MockURLProtocol.StubbedSession, canAddShows: Bool = false, now: Date = Date(timeIntervalSince1970: 1_793_000_000)) -> AudiobookshelfPodcastSource {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("abs-\(UUID().uuidString)", isDirectory: true)
    let tokens = TokenSession(Tokens(accessToken: "token", refreshToken: nil, expiresAt: Date().addingTimeInterval(3600)))
    let client = AudiobookshelfClient(host: host, tokens: tokens, session: mock.urlSession)
    return AudiobookshelfPodcastSource(client: client, store: ListeningStore(directory: directory, now: { now }), fetcher: FeedFetcher(session: mock.urlSession), canAddShows: canAddShows, now: { now })
}

@Suite("Audiobookshelf podcasts")
struct AudiobookshelfSourceTests {
    @Test("a show lists the server's episodes and the feed's others, matched by GUID, enclosure and title")
    func feedMerge() async throws {
        let abs = source(await server())
        let shows = try await abs.shows()
        #expect(shows.map(\.title) == ["Show & I'm"], "HTML entities in the server's titles are decoded")
        #expect(shows[0].imageURL?.path == "/api/items/show1/cover")
        let episodes = try await abs.episodes(showId: "show1")
        #expect(Set(episodes.map(\.id)) == ["ep1", "ep2", "feed:g3"], "g1 matches by GUID, two by title; only g3 is the feed's own")
        let one = try #require(episodes.first { $0.id == "ep1" })
        #expect(one.durationMs == 600_000 && one.chapters.map(\.title) == ["A", "B"] && one.chapters[1].startMs == 300_000)
    }

    @Test("playing: the server's copy with a token, a feed-only episode from the publisher")
    func playback() async throws {
        let abs = source(await server())
        _ = try await abs.episodes(showId: "show1")
        let server = try await abs.playback(EpisodeKey(showId: "show1", episodeId: "ep1"))
        #expect(server.isServerFile && server.url.absoluteString == "https://abs.example.com/api/items/show1/file/101?token=token")
        let feed = try await abs.playback(EpisodeKey(showId: "show1", episodeId: "feed:g3"))
        #expect(!feed.isServerFile && feed.url == URL(string: "https://pub.example/3.mp3"))
    }

    @Test("New Episodes from the recent list: the newest of a show seen for the first time")
    func inbox() async throws {
        let abs = source(await server())
        #expect(try await abs.inbox(limit: 10).map(\.id) == ["ep2"], "a show seen for the first time brings its newest, not its archive")
        try await abs.dismissFromInbox([EpisodeKey(showId: "show1", episodeId: "ep2")])
        #expect(try await abs.inbox(limit: 10).isEmpty)
    }

    @Test("positions: the newer of phone and server, feed-only ones on the phone, a server-side finish counts")
    func progress() async throws {
        let abs = source(await server(progress: ["ep1": (120, false, 1_792_900_000_000), "ep2": (1199, true, 1_792_900_000_000)]))
        let key = EpisodeKey(showId: "show1", episodeId: "ep1")
        #expect(try await abs.progress(key)?.positionMs == 120_000, "nothing on the phone: the server's")
        let newer = ListeningProgress(positionMs: 200_000, played: false, updatedAt: Date(timeIntervalSince1970: 1_792_950_000))
        #expect(try await abs.saveProgress(newer, for: key) == newer)
        #expect(try await abs.progress(key)?.positionMs == 200_000, "the phone's is newer now")
        let all = try await abs.allProgress()
        #expect(all[EpisodeKey(showId: "show1", episodeId: "ep2")]?.played == true)
        let feedKey = EpisodeKey(showId: "show1", episodeId: "feed:g3")
        _ = try await abs.saveProgress(ListeningProgress(positionMs: 5_000, played: false, updatedAt: Date()), for: feedKey)
        #expect(try await abs.progress(feedKey)?.positionMs == 5_000)
    }

    @Test("an account that may not upload cannot add shows, and nobody removes them from a player")
    func permissions() async throws {
        let abs = source(await server())
        #expect(!abs.capabilities.contains(.addByURL))
        await #expect(throws: SourceError.unsupported) { try await abs.follow(feedURL: URL(string: "https://x.example/rss")!) }
        await #expect(throws: SourceError.unsupported) { try await abs.unfollow(showId: "show1") }
        #expect(source(await server(), canAddShows: true).capabilities.contains(.addByURL))
    }
}

@Suite("Listening store")
struct ListeningStoreTests {
    @Test("first sightings decide what is new; settings, queue and positions are kept on disk")
    func store() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("store-\(UUID().uuidString)", isDirectory: true)
        var clock = Date(timeIntervalSince1970: 1_000)
        let box = ClockBox(clock)
        let store = ListeningStore(directory: directory, now: { box.now })
        let old = [Episode(id: "a", showId: "s", title: "A", publishedAt: Date(timeIntervalSince1970: 10)), Episode(id: "b", showId: "s", title: "B", publishedAt: Date(timeIntervalSince1970: 20))]
        let seen = await store.observe(old, showId: "s")
        let (newest, oldest) = (await store.isInInbox(seen[1]), await store.isInInbox(seen[0]))
        #expect(newest && !oldest, "only the newest at first sight")
        clock += 60
        box.now = clock
        let later = await store.observe(old + [Episode(id: "c", showId: "s", title: "C")], showId: "s")
        let fresh = await store.isInInbox(later[2])
        #expect(fresh && later[0].firstSeenAt == seen[0].firstSeenAt)
        try await store.setSettings(ShowSettings(inInbox: false), showId: "s")
        #expect(!(await store.isInInbox(later[2])), "a show out of the inbox")
        try await store.playLater(later[0].key)
        _ = try await store.save(ListeningProgress(positionMs: 9, played: false, updatedAt: clock), for: later[1].key)
        let reopened = ListeningStore(directory: directory, now: { box.now })
        let (queue0, position) = (await reopened.queue(), await reopened.progress(later[1].key)?.positionMs)
        #expect(queue0 == [later[0].key] && position == 9)
        #expect(await reopened.settings(showId: "s").inInbox == false)
        try await reopened.forget(showId: "s")
        let (queue, kept) = (await reopened.queue(), await reopened.progress(later[1].key))
        #expect(queue.isEmpty && kept == nil)
    }

    final class ClockBox: @unchecked Sendable {
        var now: Date
        init(_ now: Date) { self.now = now }
    }
}

@Suite("Audiobookshelf libraries")
struct AudiobookshelfLibraryTests {
    @Test("the libraries are listed in order, and a show is added into the one chosen")
    func followIntoLibrary() async throws {
        final class Sent: @unchecked Sendable { var body = "" }
        let sent = Sent()
        let mock = await MockURLProtocol.makeStubbedSession { request in
            let json = { (body: String) in MockURLProtocol.StubbedResponse(statusCode: 200, body: Data(body.utf8)) }
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("GET", "/api/libraries"):
                return json(#"{"libraries":[{"id":"lib3","name":"YouTube","mediaType":"podcast","displayOrder":2,"folders":[{"id":"f3","fullPath":"/youtube"}]},{"id":"lib1","name":"Podcasts","mediaType":"podcast","displayOrder":1,"folders":[{"id":"f1","fullPath":"/podcasts"}]}]}"#)
            case ("GET", let path) where path.hasSuffix("/items"):
                return json(#"{"results":[],"total":0,"limit":200,"page":0}"#)
            case ("GET", "/feed.xml"):
                return json("<?xml version='1.0'?><rss version='2.0'><channel><title>New Show</title><item><title>One</title><guid>1</guid><enclosure url='https://abs.example.com/1.mp3' type='audio/mpeg' length='1'/></item></channel></rss>")
            case ("POST", "/api/podcasts"):
                sent.body = request.httpBody.map { String(decoding: $0, as: UTF8.self) } ?? request.httpBodyStream.map { stream in
                    stream.open(); defer { stream.close() }
                    var data = Data(); let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096); defer { buffer.deallocate() }
                    while stream.hasBytesAvailable { let n = stream.read(buffer, maxLength: 4096); if n <= 0 { break }; data.append(buffer, count: n) }
                    return String(decoding: data, as: UTF8.self)
                } ?? ""
                return json(#"{"id":"new1","libraryId":"lib3","addedAt":1,"updatedAt":1,"media":{"metadata":{"title":"New Show","feedUrl":"https://abs.example.com/feed.xml"},"episodes":[]}}"#)
            default:
                return .init(statusCode: 404, body: Data())
            }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("abs-\(UUID().uuidString)", isDirectory: true)
        let client = AudiobookshelfClient(host: URL(string: "https://abs.example.com")!, tokens: TokenSession(Tokens(accessToken: "t", refreshToken: nil, expiresAt: Date().addingTimeInterval(3600))), session: mock.urlSession)
        let abs = AudiobookshelfPodcastSource(client: client, store: ListeningStore(directory: directory), fetcher: FeedFetcher(session: mock.urlSession), canAddShows: true)
        let libraries = try await abs.podcastLibraries()
        #expect(libraries.map(\.name) == ["Podcasts", "YouTube"], "in the server's order")
        let show = try await abs.follow(feedURL: URL(string: "https://abs.example.com/feed.xml")!, libraryId: "lib3")
        #expect(show.collection == "lib3")
        #expect(sent.body.contains("lib3") && sent.body.contains("f3"), "into the chosen library's folder: \(sent.body)")
    }
}
