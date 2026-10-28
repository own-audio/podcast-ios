import Foundation
import Testing

@testable import OwnAudioKit

@Suite("Account")
struct AccountTests {
    private let host = URL(string: "https://podcasts.example.com")!

    private func client(_ handler: @escaping @Sendable (URLRequest) -> MockURLProtocol.StubbedResponse) async -> (OwnAudioClient, TokenSession, MockURLProtocol.StubbedSession) {
        let mock = await MockURLProtocol.makeStubbedSession(handler)
        let tokens = TokenSession(Tokens(accessToken: "a", refreshToken: "r", expiresAt: Date().addingTimeInterval(3600), scope: ""))
        return (OwnAudioClient(host: host, tokens: tokens, session: mock.urlSession), tokens, mock)
    }

    @Test("the statistics ask /api/v1 with the range and the phone's offset, and decode")
    func stats() async throws {
        let (client, _, mock) = await client { request in
            switch request.url?.path {
            case "/api/v1/stats/me":
                return .init(statusCode: 200, body: Data(#"{"range":"30d","total_seconds":5400,"by_kind":[{"media_kind":"podcast","seconds":5400,"sessions":3}],"by_day":[{"day":"2026-10-27","seconds":5400}],"top_items":[{"media_kind":"podcast","item_id":"e1","title":null,"seconds":5400,"sessions":3}],"streak_days":2,"completed_items":0,"stats_visibility":"family_admin"}"#.utf8), headers: ["Content-Type": "application/json"])
            case "/api/v1/stats/family":
                return .init(statusCode: 200, body: Data(#"[{"user_id":"u1","display_name":"Jana","display_label":null,"total_seconds":null,"by_kind":null,"hidden":true}]"#.utf8), headers: ["Content-Type": "application/json"])
            default:
                return .init(statusCode: 404, body: Data())
            }
        }
        let stats = try await client.listeningStats(.month, timeZone: TimeZone(secondsFromGMT: 3600)!)
        #expect(stats.totalSeconds == 5400 && stats.streakDays == 2)
        #expect(stats.topItems.first?.title == nil)
        #expect(stats.statsVisibility == "family_admin")
        let family = try await client.familyListening(.week, timeZone: TimeZone(secondsFromGMT: 0)!)
        #expect(family.first?.name == "Jana" && family.first?.totalSeconds == nil)
        let queries = await mock.requestLog().map { $0.url!.query ?? "" }
        #expect(queries == ["range=30d&tz_offset_minutes=60", "range=7d&tz_offset_minutes=0"])
    }

    @Test("deleting the account signs out; the last admin's 400 comes through as is")
    func delete() async throws {
        let (client, tokens, mock) = await client { request in
            .init(statusCode: request.httpMethod == "DELETE" && request.url?.path == "/api/v1/users/me" ? 204 : 404, body: Data())
        }
        try await client.deleteAccount()
        #expect(await tokens.current == nil)
        #expect(await mock.requestLog().map { "\($0.httpMethod!) \($0.url!.path)" } == ["DELETE /api/v1/users/me"])

        let (refusing, refusedTokens, _) = await self.client { _ in .init(statusCode: 400, body: Data()) }
        await #expect(throws: OwnAudioError.http(400)) { try await refusing.deleteAccount() }
        #expect(await refusedTokens.current != nil)
    }

    @Test("sharing with the family's admin sends the visibility")
    func share() async throws {
        let (client, _, mock) = await client { _ in .init(statusCode: 200, body: Data("{}".utf8), headers: ["Content-Type": "application/json"]) }
        try await client.setStatsShared(withFamilyAdmin: true)
        let request = try #require(await mock.requestLog().first)
        #expect(request.httpMethod == "PUT" && request.url?.path == "/api/v1/stats/me/visibility")
    }
}
