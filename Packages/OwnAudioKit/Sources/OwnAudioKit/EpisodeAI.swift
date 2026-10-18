import Foundation

// Episode summaries and questions: own.audio's hosted service (`features.summaries`), under
// `/api/v2/summaries`. The server reads the episode's transcript; nothing here sends audio.

/// How long a summary is; each length is made and kept on its own.
public enum SummaryLength: String, CaseIterable, Sendable, Codable {
    case short, medium, long
}

public struct EpisodeSummary: Decodable, Sendable, Equatable {
    public let language: String
    public let length: SummaryLength?
    public let text: String
    /// What the family paid for it, in micro-dollars.
    public let chargedMicro: Int64?

    enum CodingKeys: String, CodingKey {
        case language, length, text
        case chargedMicro = "charged_micro"
    }
}

/// An answer, and what the family paid for it in micro-dollars.
public struct EpisodeAnswer: Sendable, Equatable {
    public let answer: String
    public let chargedMicro: Int64
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

    /// The household's summary in `language` and `length`, nil when none has been made yet.
    public func summary(episodeId: String, language: String, length: SummaryLength) async throws -> EpisodeSummary? {
        do {
            let data = try await raw("GET", "/summaries/episodes/\(episodeId)/summary", query: ["language": language, "length": length.rawValue], body: Optional<Empty>.none, idempotencyKey: nil, api: "api/v2")
            return try JSONDecoder().decode(EpisodeSummary.self, from: data)
        } catch let error where OwnAudioError.status(of: error) == 404 {
            return nil
        }
    }

    /// Made now and paid from the family's credit, or the one already made.
    /// Status 402: not enough credit; 409: today's limit for paid work; 400: no transcript.
    public func summarize(episodeId: String, language: String, length: SummaryLength) async throws -> EpisodeSummary {
        struct Body: Encodable { let language: String; let length: SummaryLength }
        let data = try await raw("POST", "/summaries/episodes/\(episodeId)/summary", query: [:], body: Body(language: language, length: length), idempotencyKey: nil, api: "api/v2")
        return try JSONDecoder().decode(EpisodeSummary.self, from: data)
    }

    /// An answer from the episode's transcript, paid; the earlier questions go along.
    public func ask(episodeId: String, question: String, history: [EpisodeQuestion]) async throws -> EpisodeAnswer {
        struct Body: Encodable { let question: String; let history: [EpisodeQuestion] }
        struct Answer: Decodable { let answer: String; let charged_micro: Int64? }
        let data = try await raw("POST", "/summaries/episodes/\(episodeId)/ask", query: [:], body: Body(question: question, history: history), idempotencyKey: nil, api: "api/v2")
        let answer = try JSONDecoder().decode(Answer.self, from: data)
        return EpisodeAnswer(answer: answer.answer, chargedMicro: answer.charged_micro ?? 0)
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
