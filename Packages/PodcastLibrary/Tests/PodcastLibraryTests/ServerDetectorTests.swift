import Foundation
import Testing

@testable import PodcastLibrary

@Suite("Server detection")
struct ServerDetectorTests {
    /// One fake host per kind, answering only what that kind of server answers.
    private func detector() async -> ServerDetector {
        let mock = await MockURLProtocol.makeStubbedSession { request in
            let json = { (body: String) in MockURLProtocol.StubbedResponse(statusCode: 200, body: Data(body.utf8)) }
            switch (request.url?.host() ?? "", request.url?.path ?? "") {
            case ("own.example", "/api/v1/server"): return json(#"{"edition":"foss","api":{"version":1,"revision":16},"features":{"gpodder":true}}"#)
            case ("own.example", "/api/2/devices/own-audio-probe.json"): return .init(statusCode: 401, body: Data())
            case ("podfetch.example", "/api/v1/sys/config"): return json(#"{"rssFeed":"https://podfetch.example/rss","basicAuth":true}"#)
            case ("podfetch.example", "/status"): return json(#"{"isInit":true,"serverVersion":"2.0"}"#)
            case ("abs.example", "/status"): return json(#"{"app":"audiobookshelf","serverVersion":"2.37.1","isInit":true}"#)
            case ("gpodder.example", "/api/2/devices/own-audio-probe.json"): return .init(statusCode: 401, body: Data())
            default: return .init(statusCode: 404, body: Data())
            }
        }
        return ServerDetector(session: mock.urlSession)
    }

    @Test("each kind is told apart; own.audio and podfetch win over the APIs they also speak")
    func kinds() async {
        let d = await detector()
        #expect(await d.detect("own.example") == .ownAudio(URL(string: "https://own.example")!))
        #expect(await d.detect("https://podfetch.example/") == .gpodder(URL(string: "https://podfetch.example")!))
        #expect(await d.detect("abs.example") == .audiobookshelf(URL(string: "https://abs.example")!))
        #expect(await d.detect("gpodder.example") == .gpodder(URL(string: "https://gpodder.example")!))
        #expect(await d.detect("nothing.example") == nil)
    }

    @Test("addresses to try: the hosted service's web names mean its API; HTTPS before HTTP")
    func candidates() {
        #expect(ServerDetector.candidates("app.own.audio") == [URL(string: "https://api.own.audio")!])
        #expect(ServerDetector.candidates("192.168.1.10:13378").map(\.absoluteString) == ["https://192.168.1.10:13378", "http://192.168.1.10:13378"])
        #expect(ServerDetector.candidates("http://nas.local:8881/").map(\.absoluteString) == ["http://nas.local:8881"])
        #expect(ServerDetector.candidates("  ").isEmpty)
    }
}
