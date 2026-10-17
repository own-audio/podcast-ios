import Foundation

/// What kind of server answers at an address the listener typed, so the add-server form needs
/// only the address, the name and the password.
public enum DetectedServer: Sendable, Equatable {
    case ownAudio(URL)
    case audiobookshelf(URL)
    /// A gPodder sync server: podfetch, gpodder.net, or any other that speaks its API.
    case gpodder(URL)
}

public struct ServerDetector: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Asks each address in turn — the typed one with `https://`, then `http://` for a server on
    /// the home network — what it is: own.audio first (which also speaks gPodder, and is more
    /// as itself), then podfetch, Audiobookshelf, and last any server with the gPodder API.
    /// nil when nothing known answers.
    public func detect(_ typed: String) async -> DetectedServer? {
        for host in Self.candidates(typed) {
            if let found = await probe(host) { return found }
        }
        return nil
    }

    /// The hosted service's web addresses mean its API; with no scheme, HTTPS first.
    public static func candidates(_ typed: String) -> [URL] {
        var text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        let bare = text.lowercased().replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        if ["own.audio", "www.own.audio", "app.own.audio"].contains(bare) { return [URL(string: "https://api.own.audio")!] }
        guard !text.isEmpty else { return [] }
        if text.hasPrefix("http://") || text.hasPrefix("https://") { return URL(string: text).map { [$0] } ?? [] }
        return ["https://", "http://"].compactMap { URL(string: $0 + text) }.filter { $0.host() != nil }
    }

    private func probe(_ host: URL) async -> DetectedServer? {
        // A host that does not answer at all is not asked four times.
        guard let own = await fetch(host.appending(path: "api/v1/server")) else { return nil }
        if let json = own.json, json["api"] != nil, json["edition"] != nil || json["features"] != nil {
            return .ownAudio(host)
        }
        if let json = await fetch(host.appending(path: "api/v1/sys/config"))?.json, json["rssFeed"] != nil, json["basicAuth"] != nil {
            return .gpodder(host)
        }
        if let json = await fetch(host.appending(path: "status"))?.json,
           (json["app"] as? String)?.lowercased() == "audiobookshelf" || json["serverVersion"] != nil && json["isInit"] != nil {
            return .audiobookshelf(host)
        }
        // A gPodder server asks who you are; anything else says "not found".
        if let status = await fetch(host.appending(path: "api/2/devices/own-audio-probe.json"))?.status, status == 401 || status == 403 {
            return .gpodder(host)
        }
        return nil
    }

    private func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 6)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("own.audio Podcasts", forHTTPHeaderField: "User-Agent")
        request.httpShouldHandleCookies = false
        return request
    }

    /// The status and, for a 200, the JSON object; nil when nothing answered.
    private func fetch(_ url: URL) async -> (status: Int, json: [String: Any]?)? {
        guard let (data, response) = try? await session.data(for: request(url)),
              let status = (response as? HTTPURLResponse)?.statusCode else { return nil }
        let json = status == 200 ? (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] : nil
        return (status, json)
    }
}
