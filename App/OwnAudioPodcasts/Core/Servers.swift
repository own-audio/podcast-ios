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

    init(id: UUID = UUID(), displayName: String, kind: ServerKind, host: URL, username: String, audiobookshelfTokens: AudiobookshelfKit.Tokens? = nil, ownAudioTokens: OwnAudioKit.Tokens? = nil, password: String? = nil, canAddShows: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.host = host
        self.username = username
        self.audiobookshelfTokens = audiobookshelfTokens
        self.ownAudioTokens = ownAudioTokens
        self.password = password
        self.canAddShows = canAddShows
    }

    var isSignedIn: Bool {
        switch kind {
        case .ownAudio: ownAudioTokens != nil
        case .audiobookshelf: audiobookshelfTokens != nil
        case .gpodder: password != nil
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
