import AudiobookshelfKit
import Foundation
import OwnAudioKit
import Security
import os

enum ServerKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case ownAudio, audiobookshelf, gpodder
    var id: Self { self }

    var name: String {
        switch self {
        case .ownAudio: "own.audio"
        case .audiobookshelf: "Audiobookshelf"
        case .gpodder: String(localized: "gPodder sync")
        }
    }
}

/// One server the listener added. The sign-in lives in the Keychain with it: rotating tokens
/// for own.audio and Audiobookshelf, the password for a gPodder account (its API asks for it on
/// every call).
struct ServerRecord: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    var displayName: String
    let kind: ServerKind
    var host: URL
    var username: String
    var audiobookshelfTokens: AudiobookshelfKit.Tokens?
    var ownAudioTokens: OwnAudioKit.Tokens?
    var password: String?
    /// Audiobookshelf: whether this account may add shows (the `upload` permission).
    var canAddShows: Bool
    /// Every other address the server is known by: named by the server (own.audio), or added by
    /// hand (the home network, a VPN).
    var addresses: [ServerAddress]
    /// nil: the fastest address that answers, chosen again on each network.
    var fixedAddress: URL?
    /// own.audio's own identity: an address answering with another id is not this server.
    var serverIdentity: String?
    /// Which software a gPodder server is, where it says (`podfetch`), for its logo.
    var software: String?

    init(id: UUID = UUID(), displayName: String, kind: ServerKind, host: URL, username: String, audiobookshelfTokens: AudiobookshelfKit.Tokens? = nil, ownAudioTokens: OwnAudioKit.Tokens? = nil, password: String? = nil, canAddShows: Bool = false, addresses: [ServerAddress] = [], fixedAddress: URL? = nil, serverIdentity: String? = nil, software: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.host = host
        self.username = username
        self.audiobookshelfTokens = audiobookshelfTokens
        self.ownAudioTokens = ownAudioTokens
        self.password = password
        self.canAddShows = canAddShows
        self.addresses = addresses
        self.fixedAddress = fixedAddress
        self.serverIdentity = serverIdentity
        self.software = software
    }

    enum CodingKeys: String, CodingKey {
        case id, displayName, kind, host, username, audiobookshelfTokens, ownAudioTokens, password, canAddShows, addresses, fixedAddress, serverIdentity, software
    }

    /// Records saved before addresses existed decode with none.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        kind = try c.decode(ServerKind.self, forKey: .kind)
        host = try c.decode(URL.self, forKey: .host)
        username = try c.decode(String.self, forKey: .username)
        audiobookshelfTokens = try c.decodeIfPresent(AudiobookshelfKit.Tokens.self, forKey: .audiobookshelfTokens)
        ownAudioTokens = try c.decodeIfPresent(OwnAudioKit.Tokens.self, forKey: .ownAudioTokens)
        password = try c.decodeIfPresent(String.self, forKey: .password)
        canAddShows = try c.decodeIfPresent(Bool.self, forKey: .canAddShows) ?? false
        addresses = try c.decodeIfPresent([ServerAddress].self, forKey: .addresses) ?? []
        fixedAddress = try c.decodeIfPresent(URL.self, forKey: .fixedAddress)
        serverIdentity = try c.decodeIfPresent(String.self, forKey: .serverIdentity)
        software = try c.decodeIfPresent(String.self, forKey: .software)
    }

    /// Every address to try, the one it was added with first, each once.
    var candidateAddresses: [ServerAddress] {
        var seen = Set<String>()
        return ([ServerAddress(url: host, origin: .added)] + addresses).filter { seen.insert(ServerAddress.normalized($0.url)).inserted }
    }

    var isSignedIn: Bool {
        switch kind {
        case .ownAudio: ownAudioTokens != nil
        case .audiobookshelf: audiobookshelfTokens != nil
        case .gpodder: password != nil
        }
    }
}

/// One address of a server, and where the app learned it.
struct ServerAddress: Codable, Sendable, Equatable, Identifiable, Hashable {
    enum Origin: String, Codable, Sendable { case added, server, user }

    var url: URL
    var origin: Origin
    var id: String { url.absoluteString }

    /// Where it can be reached from, read off the address itself.
    var scope: AddressScope { AddressScope.infer(url) }

    static func normalized(_ url: URL) -> String {
        var text = url.absoluteString.lowercased()
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }
}

enum AddressScope: Sendable {
    case lan, vpn, internet

    /// Private and link-local IPs and `.local` names are the home network; Tailscale's range
    /// and names a VPN; the rest the internet.
    static func infer(_ url: URL) -> AddressScope {
        let host = (url.host() ?? "").lowercased()
        if host.hasSuffix(".ts.net") { return .vpn }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4 {
            switch (parts[0], parts[1]) {
            case (10, _), (192, 168), (169, 254): return .lan
            case (172, 16...31): return .lan
            case (100, 64...127): return .vpn
            case (127, _): return .lan
            default: return .internet
            }
        }
        if host.hasSuffix(".local") || host.hasSuffix(".lan") || host.hasSuffix(".home.arpa") || !host.contains(".") { return .lan }
        return .internet
    }

    var title: String {
        switch self {
        case .lan: String(localized: "Home network")
        case .vpn: String(localized: "VPN")
        case .internet: String(localized: "Internet")
        }
    }
}

/// Every server in one Keychain item, so adding or removing one is one write.
actor ServerStore {
    private let service: String
    private let account = "servers"
    private let logger = Logger(subsystem: "audio.own.podcastplayer", category: "ServerStore")

    init(service: String = "audio.own.podcastplayer.servers") {
        self.service = service
    }

    func loadAll() -> [ServerRecord] {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound { logger.error("Server load failed: OSStatus \(status, privacy: .public)") }
            return []
        }
        do {
            return try JSONDecoder().decode([ServerRecord].self, from: data)
        } catch {
            logger.error("Saved servers could not be decoded.")
            return []
        }
    }

    func add(_ record: ServerRecord) throws { try persist(loadAll() + [record]) }
    func remove(id: UUID) throws { try persist(loadAll().filter { $0.id != id }) }

    func update(_ record: ServerRecord) throws {
        var records = loadAll()
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index] = record
        try persist(records)
    }

    func updateTokens(serverId: UUID, ownAudio tokens: OwnAudioKit.Tokens?) {
        var records = loadAll()
        guard let index = records.firstIndex(where: { $0.id == serverId }) else { return }
        records[index].ownAudioTokens = tokens
        try? persist(records)
    }

    func updateTokens(serverId: UUID, audiobookshelf tokens: AudiobookshelfKit.Tokens?) {
        var records = loadAll()
        guard let index = records.firstIndex(where: { $0.id == serverId }) else { return }
        records[index].audiobookshelfTokens = tokens
        try? persist(records)
    }

    func clear() { SecItemDelete(baseQuery() as CFDictionary) }

    private func persist(_ records: [ServerRecord]) throws {
        let data = try JSONEncoder().encode(records)
        let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery()
            addQuery[kSecValueData as String] = data
            // Episodes play with the screen locked, and their requests need the sign-in then.
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw ServerStoreError.keychain(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw ServerStoreError.keychain(updateStatus)
        }
    }

    private func baseQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
}

enum ServerStoreError: Error { case keychain(OSStatus) }

/// Saves rotated tokens the moment a refresh hands them out: a refresh token works once.
struct OwnAudioTokenKeeper: OwnAudioKit.TokenKeeper {
    let store: ServerStore
    let serverId: UUID
    func save(_ tokens: OwnAudioKit.Tokens?) async { await store.updateTokens(serverId: serverId, ownAudio: tokens) }
}

struct AudiobookshelfTokenKeeper: AudiobookshelfKit.TokenKeeper {
    let store: ServerStore
    let serverId: UUID
    func save(_ tokens: AudiobookshelfKit.Tokens?) async { await store.updateTokens(serverId: serverId, audiobookshelf: tokens) }
}
