import Foundation

// Episode summaries and questions: own.audio's hosted service (`features.summaries`), under
// `/api/v2/summaries`. The server reads the episode's transcript; nothing here sends audio.

public struct EpisodeSummary: Decodable, Sendable, Equatable {
    public let language: String
    public let text: String
}

public struct EpisodeQuestion: Codable, Sendable, Equatable, Hashable {
    public let question: String
    public let answer: String
    public init(question: String, answer: String) {
        self.question = question
        self.answer = answer
    }
}

extension OwnAudioClient {
    /// Whether the server offers summaries (`GET /api/v1/server` → `features.summaries`).
    public func offersSummaries() async -> Bool {
        guard let data = try? await raw("GET", "/server", query: [:], body: Optional<Empty>.none, idempotencyKey: nil, api: "api/v1"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["features"] as? [String: Any]
        else { return false }
        return features["summaries"] as? Bool == true
    }

    /// The household's summary in `language`, nil when none has been made yet.
    public func summary(episodeId: String, language: String) async throws -> EpisodeSummary? {
        do {
            let data = try await raw("GET", "/summaries/episodes/\(episodeId)/summary", query: ["language": language], body: Optional<Empty>.none, idempotencyKey: nil, api: "api/v2")
            return try JSONDecoder().decode(EpisodeSummary.self, from: data)
        } catch let error where OwnAudioError.status(of: error) == 404 {
            return nil
        }
    }

    /// Made now and paid from the family's credit, or the one already made.
    /// Status 402: not enough credit; 409: today's limit for paid work; 400: no transcript.
    public func summarize(episodeId: String, language: String) async throws -> EpisodeSummary {
        struct Body: Encodable { let language: String }
        let data = try await raw("POST", "/summaries/episodes/\(episodeId)/summary", query: [:], body: Body(language: language), idempotencyKey: nil, api: "api/v2")
        return try JSONDecoder().decode(EpisodeSummary.self, from: data)
    }

    /// An answer from the episode's transcript, paid; the earlier questions go along.
    public func ask(episodeId: String, question: String, history: [EpisodeQuestion]) async throws -> String {
        struct Body: Encodable { let question: String; let history: [EpisodeQuestion] }
        struct Answer: Decodable { let answer: String }
        let data = try await raw("POST", "/summaries/episodes/\(episodeId)/ask", query: [:], body: Body(question: question, history: history), idempotencyKey: nil, api: "api/v2")
        return try JSONDecoder().decode(Answer.self, from: data).answer
    }
}

extension OwnAudioError {
    /// The HTTP status behind an error, from v2's problem details or a bare status.
    public static func status(of error: Error) -> Int? {
        switch error as? OwnAudioError {
        case .problem(let problem): problem.status
        case .http(let status): status
        default: nil
        }
    }
}
