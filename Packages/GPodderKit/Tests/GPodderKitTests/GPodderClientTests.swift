import Foundation
import Testing

@testable import GPodderKit

@Suite("GPodderClient")
struct GPodderClientTests {
    @Test("subscriptions and episode actions: paths, basic auth, since, the API's timestamps")
    func requests() async throws {
        let mock = await MockURLProtocol.makeStubbedSession { request in
            let json = { (body: String) in MockURLProtocol.StubbedResponse(statusCode: 200, body: Data(body.utf8), headers: ["Content-Type": "application/json"]) }
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic " + Data("jo:secret".utf8).base64EncodedString())
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/api/2/auth/jo/login.json"): return .init(statusCode: 200, body: Data())
            case ("POST", "/api/2/devices/jo/phone-1.json"): return .init(statusCode: 200, body: Data())
            case ("GET", "/api/2/subscriptions/jo/phone-1.json"):
                #expect(request.url?.query == "since=0")
                return json(#"{"add":["https://a.example/rss"],"remove":["https://b.example/rss"],"timestamp":12345}"#)
            case ("POST", "/api/2/subscriptions/jo/phone-1.json"): return json(#"{"timestamp":12346,"update_urls":[["https://c.example/rss ","https://c.example/rss"]]}"#)
            case ("GET", "/api/2/episodes/jo.json"):
                return json(#"{"actions":[{"podcast":"https://a.example/rss","episode":"https://a.example/1.mp3","action":"play","timestamp":"2026-10-17T08:00:00","started":0,"position":120,"total":600,"device":"laptop"}],"timestamp":12347}"#)
            case ("POST", "/api/2/episodes/jo.json"): return json(#"{"timestamp":12348}"#)
            default: return .init(statusCode: 404, body: Data())
            }
        }
        let client = GPodderClient(host: URL(string: "https://gpodder.example")!, username: "jo", password: "secret", session: mock.urlSession)
        try await client.login()
        try await client.registerDevice(id: "phone-1", caption: "iPhone")
        let changes = try await client.subscriptionChanges(device: "phone-1", since: 0)
        #expect(changes == SubscriptionChanges(add: ["https://a.example/rss"], remove: ["https://b.example/rss"], timestamp: 12345))
        let uploaded = try await client.uploadSubscriptionChanges(device: "phone-1", add: ["https://c.example/rss "], remove: [])
        #expect(uploaded.timestamp == 12346 && uploaded.updateUrls == [["https://c.example/rss ", "https://c.example/rss"]])
        let actions = try await client.episodeActions(since: 0)
        #expect(actions.actions.first?.position == 120 && actions.actions.first?.timestamp == ISO8601DateFormatter().date(from: "2026-10-17T08:00:00Z"))
        let sent = try await client.uploadEpisodeActions([EpisodeAction(podcast: "https://a.example/rss", episode: "https://a.example/1.mp3", action: .play, timestamp: ISO8601DateFormatter().date(from: "2026-10-17T09:30:00Z"), started: 0, position: 300, total: 600, device: "phone-1")])
        #expect(sent.timestamp == 12348 && sent.updateUrls.isEmpty)
        let body = await mock.requestLog().last.flatMap { request -> String? in
            guard let stream = request.httpBodyStream else { return request.httpBody.map { String(decoding: $0, as: UTF8.self) } }
            stream.open(); defer { stream.close() }
            var data = Data(); let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096); defer { buffer.deallocate() }
            while stream.hasBytesAvailable { let n = stream.read(buffer, maxLength: 4096); if n <= 0 { break }; data.append(buffer, count: n) }
            return String(decoding: data, as: UTF8.self)
        }
        #expect(body?.contains(#""timestamp":"2026-10-17T09:30:00""#) == true, "the API's own timestamp form")
    }

    @Test("a wrong password is unauthorized")
    func unauthorized() async throws {
        let mock = await MockURLProtocol.makeStubbedSession { _ in .init(statusCode: 401, body: Data()) }
        let client = GPodderClient(host: URL(string: "https://gpodder.example")!, username: "jo", password: "wrong", session: mock.urlSession)
        await #expect(throws: GPodderError.unauthorized) { try await client.login() }
    }

    @Test("podfetch's 403 for wrong credentials still reads as a wrong password at sign-in")
    func forbiddenAtLogin() async throws {
        let mock = await MockURLProtocol.makeStubbedSession { _ in .init(statusCode: 403, body: Data()) }
        let client = GPodderClient(host: URL(string: "https://gpodder.example")!, username: "jo", password: "wrong", session: mock.urlSession)
        await #expect(throws: GPodderError.unauthorized) { try await client.login() }
        await #expect(throws: GPodderError.forbidden) { _ = try await client.uploadEpisodeActions([]) }
    }
}
