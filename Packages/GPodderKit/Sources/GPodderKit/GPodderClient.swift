import Foundation

public enum GPodderError: Error, Sendable, Equatable {
    /// Wrong name or password.
    case unauthorized
    /// Signed in, but this account may not do that (a read-only demo). Some servers (podfetch)
    /// also answer wrong credentials with 403, which is why `login()` reads it as `unauthorized`.
    case forbidden
    case http(Int)
    case decoding
    case network
}

/// One episode action, as the gPodder API records them: a download, a play (with where it
/// started, where it stopped and how long the episode is), a delete, or new.
public struct EpisodeAction: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case download, play, delete, new }

    /// The show's feed URL.
    public var podcast: String
    /// The episode's enclosure URL — what the API identifies episodes by.
    public var episode: String
    public var action: Kind
    /// When it happened, in UTC.
    public var timestamp: Date?
    /// Seconds, `play` only.
    public var started: Int?
    public var position: Int?
    public var total: Int?
    public var device: String?
    public var guid: String?

    public init(podcast: String, episode: String, action: Kind, timestamp: Date? = nil, started: Int? = nil, position: Int? = nil, total: Int? = nil, device: String? = nil, guid: String? = nil) {
        self.podcast = podcast
        self.episode = episode
        self.action = action
        self.timestamp = timestamp
        self.started = started
        self.position = position
        self.total = total
        self.device = device
        self.guid = guid
    }
}

public struct SubscriptionChanges: Decodable, Sendable, Equatable {
    public let add: [String]
    public let remove: [String]
    /// Pass back as `since` next time.
    public let timestamp: Int64
}

public struct EpisodeActions: Decodable, Sendable, Equatable {
    public let actions: [EpisodeAction]
    public let timestamp: Int64
}

/// What an upload answers: the new `since`, and URLs the server cleaned up (old, new).
public struct UploadAnswer: Decodable, Sendable, Equatable {
    public let timestamp: Int64
    public let updateUrls: [[String]]

    enum CodingKeys: String, CodingKey { case timestamp, updateUrls = "update_urls" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try c.decode(Int64.self, forKey: .timestamp)
        updateUrls = try c.decodeIfPresent([[String]].self, forKey: .updateUrls) ?? []
    }
}

/// The gPodder API with HTTP basic authentication on every request, which every server that
/// speaks it accepts (gpodder.net also hands out a session cookie; nothing here needs it).
public struct GPodderClient: Sendable {
    public let host: URL
    public let username: String
    private let password: String
    private let session: URLSession

    public init(host: URL, username: String, password: String, session: URLSession = .shared) {
        self.host = host
        self.username = username
        self.password = password
        self.session = session
    }

    /// Checks the name and password.
    public func login() async throws {
        do {
            _ = try await raw("POST", "api/2/auth/\(escaped(username))/login.json", body: nil)
        } catch GPodderError.forbidden {
            throw GPodderError.unauthorized
        }
    }

    /// Registers (or renames) this phone as a device, which subscriptions are kept per.
    public func registerDevice(id: String, caption: String) async throws {
        struct Body: Encodable { let caption: String; let type: String }
        _ = try await raw("POST", "api/2/devices/\(escaped(username))/\(escaped(id)).json", body: try JSONEncoder().encode(Body(caption: caption, type: "mobile")))
    }

    /// What changed in the account's subscriptions on every device since `since`, where the
    /// server keeps such a list (gpodder.net, podfetch); nil where it does not. On servers that
    /// keep subscriptions per device, this is how shows added in another app arrive.
    public func allSubscriptionChanges(since: Int64) async throws -> SubscriptionChanges? {
        do {
            return try decode(try await raw("GET", "api/2/subscriptions/\(escaped(username)).json", query: ["since": String(since)], body: nil))
        } catch GPodderError.http(let status) where status == 404 || status == 400 || status == 405 {
            return nil
        } catch GPodderError.decoding {
            return nil
        }
    }

    /// What changed in the device's subscriptions since `since` (0 for everything).
    public func subscriptionChanges(device: String, since: Int64) async throws -> SubscriptionChanges {
        try decode(try await raw("GET", "api/2/subscriptions/\(escaped(username))/\(escaped(device)).json", query: ["since": String(since)], body: nil))
    }

    public func uploadSubscriptionChanges(device: String, add: [String], remove: [String]) async throws -> UploadAnswer {
        struct Body: Encodable { let add: [String]; let remove: [String] }
        return try decode(try await raw("POST", "api/2/subscriptions/\(escaped(username))/\(escaped(device)).json", body: try JSONEncoder().encode(Body(add: add, remove: remove))))
    }

    /// Every device's episode actions since `since`.
    public func episodeActions(since: Int64) async throws -> EpisodeActions {
        try decode(try await raw("GET", "api/2/episodes/\(escaped(username)).json", query: ["since": String(since)], body: nil))
    }

    public func uploadEpisodeActions(_ actions: [EpisodeAction]) async throws -> UploadAnswer {
        try decode(try await raw("POST", "api/2/episodes/\(escaped(username)).json", body: try Self.encoder.encode(actions)))
    }

    // MARK: - Transport

    /// The API's timestamps are UTC without a zone: "2026-10-17T08:00:00".
    static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .formatted(timestampFormatter)
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = timestampFormatter.date(from: String(text.prefix(19))) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "timestamp \(text)"))
        }
        return decoder
    }()

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw GPodderError.decoding
        }
    }

    private func escaped(_ part: String) -> String {
        part.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? part
    }

    private func raw(_ method: String, _ path: String, query: [String: String] = [:], body: Data?) async throws -> Data {
        var components = URLComponents(url: host.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: components.url!, timeoutInterval: 30)
        request.httpMethod = method
        // Credentials go with every request. A session cookie from an earlier sign-in would
        // otherwise outrank them on servers that honour it first (podfetch), so a wrong
        // password could pass after a right one.
        request.httpShouldHandleCookies = false
        request.setValue("Basic " + Data("\(username):\(password)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        request.setValue("own.audio Podcasts", forHTTPHeaderField: "User-Agent")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GPodderError.network
        }
        guard let http = response as? HTTPURLResponse else { throw GPodderError.network }
        if http.statusCode == 401 { throw GPodderError.unauthorized }
        if http.statusCode == 403 { throw GPodderError.forbidden }
        guard (200..<300).contains(http.statusCode) else { throw GPodderError.http(http.statusCode) }
        return data
    }
}
