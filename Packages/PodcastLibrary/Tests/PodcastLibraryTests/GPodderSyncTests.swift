import FeedKit
import Foundation
import GPodderKit
import Testing

@testable import PodcastLibrary

/// A gPodder account kept in memory, plus the feeds it points at, behind one mocked session.
private final class FakeAccount: @unchecked Sendable {
    private let lock = NSLock()
    private var clock: Int64 = 100
    private var subscriptions: [(feed: String, added: Bool, at: Int64)] = []
    private var actions: [(json: [String: Any], at: Int64)] = []
    var uploadedActions: [[String: Any]] { lock.withLock { actions.map(\.json) } }

    /// Seconds' worth of log rows handed out again: a server answering with an overlap.
    var overlap: Int64 = 0
    /// A read-only account (a public demo): uploads answer 403.
    var readOnly = false
    /// Subscriptions kept per device, as gpodder.net and podfetch keep them: the device's own
    /// list is empty, and only the account-wide list has what other apps added.
    var perDevice = false

    func serverAdds(_ feed: String) { lock.withLock { clock += 1; subscriptions.append((feed, true, clock)) } }
    func serverRemoves(_ feed: String) { lock.withLock { clock += 1; subscriptions.append((feed, false, clock)) } }
    func serverPlays(_ action: [String: Any]) { lock.withLock { clock += 1; actions.append((action, clock)) } }
    var feeds: Set<String> {
        lock.withLock {
            var out = Set<String>()
            for change in subscriptions { if change.added { out.insert(change.feed) } else { out.remove(change.feed) } }
            return out
        }
    }

    func handle(_ request: URLRequest) -> MockURLProtocol.StubbedResponse {
        let url = request.url!
        if url.host == "feeds.example.com" {
            let id = url.lastPathComponent.replacingOccurrences(of: ".xml", with: "")
            let xml = """
            <?xml version="1.0"?><rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel><title>Show \(id)</title>
            <item><title>One</title><guid>\(id)-1</guid><pubDate>01 Oct 2026 08:00:00 +0000</pubDate><itunes:duration>600</itunes:duration>
            <enclosure url="https://cdn.example.com/\(id)-1.mp3" type="audio/mpeg" length="1"/></item></channel></rss>
            """
            return .init(statusCode: 200, body: Data(xml.utf8))
        }
        let since = Int64(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "since" }?.value ?? "0") ?? 0
        let body = Self.body(request).flatMap { try? JSONSerialization.jsonObject(with: $0) }
        if readOnly, request.httpMethod == "POST" { return .init(statusCode: 403, body: Data()) }
        return lock.withLock {
            let reply = { (object: Any) in MockURLProtocol.StubbedResponse(statusCode: 200, body: try! JSONSerialization.data(withJSONObject: object)) }
            switch (request.httpMethod!, url.path) {
            case ("GET", "/api/2/subscriptions/jo/phone.json") where perDevice:
                return reply(["add": [], "remove": [], "timestamp": clock])
            case ("GET", "/api/2/subscriptions/jo.json") where !perDevice:
                return .init(statusCode: 404, body: Data())
            case ("GET", "/api/2/subscriptions/jo/phone.json"), ("GET", "/api/2/subscriptions/jo.json"):
                let recent = subscriptions.filter { $0.at > since - overlap }
                var last: [String: Bool] = [:]
                for change in recent { last[change.feed] = change.added }
                return reply(["add": last.filter { $0.value }.keys.sorted(), "remove": last.filter { !$0.value }.keys.sorted(), "timestamp": clock])
            case ("POST", "/api/2/subscriptions/jo/phone.json"):
                let changes = body as! [String: [String]]
                clock += 1
                for feed in changes["add"] ?? [] { subscriptions.append((feed, true, clock)) }
                for feed in changes["remove"] ?? [] { subscriptions.append((feed, false, clock)) }
                return reply(["timestamp": clock, "update_urls": []])
            case ("GET", "/api/2/episodes/jo.json"):
                return reply(["actions": actions.filter { $0.at > since }.map(\.json), "timestamp": clock])
            case ("POST", "/api/2/episodes/jo.json"):
                clock += 1
                for action in body as! [[String: Any]] { actions.append((action, clock)) }
                return reply(["timestamp": clock, "update_urls": []])
            default:
                return .init(statusCode: 404, body: Data())
            }
        }
    }

    private static func body(_ request: URLRequest) -> Data? {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096); defer { buffer.deallocate() }
        while stream.hasBytesAvailable { let n = stream.read(buffer, maxLength: 4096); if n <= 0 { break }; data.append(buffer, count: n) }
        return data
    }
}

private func feed(_ id: String) -> String { "https://feeds.example.com/\(id).xml" }

private func makeSync(_ account: FakeAccount) async -> (GPodderSync, FeedLibrary, URL) {
    let mock = await MockURLProtocol.makeStubbedSession { account.handle($0) }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gpsync-\(UUID().uuidString)", isDirectory: true)
    let library = FeedLibrary(directory: directory, fetcher: FeedFetcher(session: mock.urlSession))
    let client = GPodderClient(host: URL(string: "https://gpodder.example")!, username: "jo", password: "pw", session: mock.urlSession)
    return (GPodderSync(client: client, library: library, device: "phone", directory: directory), library, directory)
}

@Suite("GPodderSync")
struct GPodderSyncTests {
    @Test("subscriptions go both ways; the first sync merges and removes nothing")
    func subscriptions() async throws {
        let account = FakeAccount()
        account.serverAdds(feed("a"))
        let (sync, library, _) = await makeSync(account)
        _ = try await library.follow(feedURL: URL(string: feed("b"))!)

        let first = try await sync.sync()
        #expect(first.followed == 1 && first.uploadedShows == 1)
        #expect(Set(await library.shows().compactMap { $0.feedURL?.absoluteString }) == [feed("a"), feed("b")])
        #expect(account.feeds == [feed("a"), feed("b")])

        // Removed on the phone goes away on the account; removed on the account goes away here.
        let b = await library.shows().first { $0.feedURL?.absoluteString == feed("b") }!
        try await library.unfollow(showId: b.id)
        account.serverRemoves(feed("a"))
        account.serverAdds(feed("c"))
        let second = try await sync.sync()
        #expect(second.unfollowed == 1 && second.followed == 1)
        #expect(await library.shows().compactMap { $0.feedURL?.absoluteString } == [feed("c")])
        #expect(account.feeds == [feed("c")])
    }

    @Test("a show unfollowed on the phone stays unfollowed when the server repeats its add")
    func overlappingServer() async throws {
        let account = FakeAccount()
        account.overlap = 10
        let (sync, library, _) = await makeSync(account)
        _ = try await library.follow(feedURL: URL(string: feed("a"))!)
        try await sync.sync()
        #expect(account.feeds == [feed("a")])
        try await library.unfollow(showId: await library.shows()[0].id)
        let report = try await sync.sync()
        #expect(report.followed == 0, "the repeated add does not bring it back")
        #expect(await library.shows().isEmpty)
        #expect(account.feeds.isEmpty, "and the removal reaches the account")
    }

    @Test("a read-only account still brings its shows down; refused uploads don't stop the sync")
    func readOnlyAccount() async throws {
        let account = FakeAccount()
        account.serverAdds(feed("a"))
        account.readOnly = true
        let (sync, library, _) = await makeSync(account)
        _ = try await library.follow(feedURL: URL(string: feed("b"))!)
        try await library.record(positionMs: 60_000, for: EpisodeKey(showId: await library.shows()[0].id, episodeId: "b-1"))
        let report = try await sync.sync()
        #expect(report.followed == 1)
        #expect(Set(await library.shows().compactMap { $0.feedURL?.absoluteString }) == [feed("a"), feed("b")])
        #expect(account.feeds == [feed("a")], "nothing went up")
    }

    @Test("a server with per-device lists: a show added in another app reaches the phone")
    func perDeviceServer() async throws {
        let account = FakeAccount()
        account.perDevice = true
        account.serverAdds(feed("a"))
        let (sync, library, _) = await makeSync(account)
        let report = try await sync.sync()
        #expect(report.followed == 1)
        #expect(await library.shows().compactMap { $0.feedURL?.absoluteString } == [feed("a")])
    }

    @Test("positions: the newer side wins, and what came from the account is not sent back")
    func positions() async throws {
        let account = FakeAccount()
        account.serverAdds(feed("a"))
        let (sync, library, _) = await makeSync(account)
        try await sync.sync()
        let key = EpisodeKey(showId: await library.shows()[0].id, episodeId: "a-1")

        account.serverPlays(["podcast": feed("a"), "episode": "https://cdn.example.com/a-1.mp3", "action": "play", "timestamp": "2026-10-17T08:00:00", "started": 0, "position": 120, "total": 600, "device": "laptop"])
        let pulled = try await sync.sync()
        #expect(pulled.positionsApplied == 1 && pulled.positionsSent == 0)
        #expect(await library.progress(key)?.positionMs == 120_000)

        // Listened on the phone later: that goes up, as the API's play action.
        try await library.record(positionMs: 590_000, for: key, at: ISO8601DateFormatter().date(from: "2026-10-17T09:00:00Z"))
        let pushed = try await sync.sync()
        #expect(pushed.positionsSent == 1)
        let sent = account.uploadedActions.last { $0["device"] as? String == "phone" }
        #expect(sent?["action"] as? String == "play" && sent?["position"] as? Int == 600 && sent?["total"] as? Int == 600)
        #expect(await library.progress(key)?.played == true)

        // An older report from another device does not move it back.
        account.serverPlays(["podcast": feed("a"), "episode": "https://cdn.example.com/a-1.mp3", "action": "play", "timestamp": "2026-10-17T08:30:00", "position": 10, "total": 600])
        let stale = try await sync.sync()
        #expect(stale.positionsApplied == 0)
        #expect(await library.progress(key)?.played == true)
    }
}
