import Foundation
import OwnAudioKit

// The household, the signed-in devices and live updates on an own.audio server. Copied from
// the books app's `Household.swift` and `OwnAudioSource`: the same server API, the same
// screens; sharing an item with the family is left out, since a podcast is followed, not owned.

/// A household on the server: the people in it. Only own.audio servers have one.
public struct HouseholdInfo: Sendable, Equatable {
    public let name: String
    /// For `HouseholdSource.picture`.
    public let picture: String?
    /// Admins invite people.
    public let isAdmin: Bool
    public let members: [HouseholdMember]
}

public struct HouseholdMember: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let isAdmin: Bool
    /// Invited, not signed in yet.
    public let isPending: Bool
    public let isMe: Bool
    /// For `HouseholdSource.picture`.
    public let picture: String?
}

/// A code that lets someone join; `joinURL` opens the server's own join page with it.
public struct HouseholdInvite: Sendable, Equatable, Identifiable {
    public let id: String
    public let code: String
    public let joinURL: URL?
    public let usesLeft: Int
    /// When it stops working; nil when the server's date can't be read.
    public let expiresAt: Date?
}

/// What the family keeps on the server, in bytes.
public struct HouseholdStorage: Sendable, Equatable {
    public let total: Int64
    public let music: Int64
    public let audiobooks: Int64
    public let podcasts: Int64
}

/// The family's prepaid credit, where the server charges for storage (the hosted service).
public struct HouseholdCredit: Sendable, Equatable {
    /// In the currency's units.
    public let balance: Decimal
    public let currency: String
    public let monthlyCost: Decimal
    /// How long the balance lasts at today's storage; nil when it isn't being drawn on.
    public let daysLeft: Int?
    public let isDepleted: Bool
}

/// A device signed in to the account.
public struct DeviceSession: Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: String
    public let name: String?
    public let signedInAt: Date
    public let lastUsedAt: Date?
    public let isThisDevice: Bool
}

public protocol HouseholdSource: PodcastSource {
    func household() async throws -> HouseholdInfo
    /// The family's or a member's picture, by what `HouseholdInfo` names it.
    func picture(_ name: String) async throws -> Data
    func storage() async throws -> HouseholdStorage
    /// Nil where the server doesn't charge.
    func credit() async throws -> HouseholdCredit?
    func invites() async throws -> [HouseholdInvite]
    func createInvite() async throws -> HouseholdInvite
    func deleteInvite(id: String) async throws
    /// Moves the account into the household the code belongs to.
    func joinHousehold(code: String) async throws -> HouseholdInfo
    func sessions() async throws -> [DeviceSession]
    func revokeSession(id: String) async throws
    /// Every device out, this one included; the server then needs a fresh sign-in.
    func signOutEverywhere() async throws
    /// One value each time something the account sees changed; ends with the connection.
    nonisolated func libraryChanges() -> AsyncThrowingStream<Void, Error>
}

extension OwnAudioPodcastSource: HouseholdSource {
    public func household() async throws -> HouseholdInfo {
        try await translating {
            async let family = client.family()
            let members = try await client.members()
            let f = try await family
            return HouseholdInfo(
                name: f.name, picture: f.image, isAdmin: f.me.role == "admin",
                members: members.map {
                    HouseholdMember(
                        id: $0.userId, name: $0.name, isAdmin: $0.role == "admin", isPending: $0.pending == true,
                        isMe: $0.userId == f.me.userId, picture: $0.image
                    )
                }
                // You first, then admins, then by name.
                .sorted { ($0.isMe ? 0 : 1, $0.isAdmin ? 0 : 1, $0.name) < ($1.isMe ? 0 : 1, $1.isAdmin ? 0 : 1, $1.name) }
            )
        }
    }

    public func picture(_ name: String) async throws -> Data {
        try await translating { try await client.picture(name) }
    }

    public func storage() async throws -> HouseholdStorage {
        try await translating {
            let s = try await client.familyStorage()
            return HouseholdStorage(total: s.totalBytes, music: s.musicBytes, audiobooks: s.audiobooksBytes, podcasts: s.podcastsBytes)
        }
    }

    public func credit() async throws -> HouseholdCredit? {
        let billing: FamilyBilling
        do {
            billing = try await client.familyBilling()
        } catch OwnAudioError.problem(let p) where p.status == 501 || p.status == 404 {
            // A server that doesn't charge (the open-source one says `feature_unavailable`).
            return nil
        } catch {
            return try await translating { throw error }
        }
        let units = { (micro: Int64) in Decimal(micro) / 1_000_000 }
        return HouseholdCredit(
            balance: units(billing.availableMicro), currency: billing.pricing.currency,
            monthlyCost: units(billing.estimatedMonthlyCostMicro), daysLeft: billing.daysRemaining.map(Int.init),
            isDepleted: billing.depleted
        )
    }

    public func invites() async throws -> [HouseholdInvite] {
        try await translating { try await client.invites().filter { $0.useCount < $0.maxUses }.map(Self.invite) }
    }

    public func createInvite() async throws -> HouseholdInvite {
        try await translating { Self.invite(try await client.createInvite()) }
    }

    public func deleteInvite(id: String) async throws {
        try await translating { try await client.deleteInvite(id: id) }
    }

    public func joinHousehold(code: String) async throws -> HouseholdInfo {
        try await translating { _ = try await client.join(code: code.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return try await household()
    }

    public func sessions() async throws -> [DeviceSession] {
        try await translating {
            try await client.sessions().map { DeviceSession(id: $0.id, kind: $0.deviceKind, name: $0.deviceName, signedInAt: $0.signedInAt, lastUsedAt: $0.lastUsedAt, isThisDevice: $0.current) }
        }
    }

    public func revokeSession(id: String) async throws {
        try await translating { try await client.revokeSession(id: id) }
    }

    public func signOutEverywhere() async throws {
        try await translating { try await client.revokeAllSessions() }
    }

    public nonisolated func libraryChanges() -> AsyncThrowingStream<Void, Error> {
        let events = client.events()
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in events where event.type == "library" { continuation.yield(()) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func invite(_ i: Invite) -> HouseholdInvite {
        HouseholdInvite(
            id: i.id, code: i.code, joinURL: i.joinUrl.flatMap(URL.init(string:)), usesLeft: max(i.maxUses - i.useCount, 0),
            expiresAt: ISO8601DateFormatter().date(from: i.expiresAt)
                ?? { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f.date(from: i.expiresAt) }()
        )
    }
}
