import PodcastLibrary
import SwiftUI

/// The devices signed in to an own.audio account, with this one marked; any can be signed
/// out, or all of them at once. Copied from the books app's `DevicesView`.
struct DevicesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let serverId: UUID
    @State private var sessions: [DeviceSession]?
    @State private var failure: String?
    @State private var isConfirmingAll = false

    var body: some View {
        List {
            Section {
                if let sessions {
                    ForEach(sessions) { session in
                        row(session)
                    }
                } else if let failure {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text(failure).foregroundStyle(Theme.Colors.muted)
                        Button("Try Again") { load() }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            } footer: {
                Text("Swipe a device to sign it out. Signing out everywhere ends every session, this iPhone's too, and asks for a fresh sign-in.")
            }
            Section {
                Button("Sign Out Everywhere", role: .destructive) { isConfirmingAll = true }
                    .disabled(model.isOffline)
                    .accessibilityIdentifier("devices.signOutEverywhere")
            }
        }
        .navigationTitle("Devices")
        .task(id: serverId) { load() }
        .refreshable { load() }
        .confirmationDialog("Sign Out Everywhere?", isPresented: $isConfirmingAll, titleVisibility: .visible) {
            Button("Sign Out Everywhere", role: .destructive) {
                model.perform {
                    try await model.householdSource(serverId)?.signOutEverywhere()
                    dismiss()
                }
            }
        }
    }

    private func row(_ session: DeviceSession) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: Self.symbol(session.kind))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(session.name ?? session.kind.capitalized)
                    if session.isThisDevice {
                        Text("This device")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.Colors.accent.opacity(0.15), in: Capsule())
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }
                Group {
                    if let used = session.lastUsedAt {
                        Text("Last used \(used, style: .relative) ago")
                    } else {
                        Text("Signed in \(session.signedInAt, style: .date)")
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.Colors.muted)
            }
        }
        .swipeActions {
            if !session.isThisDevice {
                Button(role: .destructive) {
                    signOut(session)
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .accessibilityIdentifier("devices.\(session.id)")
    }

    private static func symbol(_ kind: String) -> String {
        switch kind {
        case "ios": "iphone"
        case "macos": "laptopcomputer"
        case "web": "safari"
        case "android": "smartphone"
        case "tvos": "appletv"
        case "windows": "pc"
        default: "desktopcomputer"
        }
    }

    private func load() {
        Task {
            do {
                guard let source = model.householdSource(serverId) else { throw SourceError.unsupported }
                // This device first, then the most recently used.
                sessions = try await source.sessions().sorted {
                    if $0.isThisDevice != $1.isThisDevice { return $0.isThisDevice }
                    return ($0.lastUsedAt ?? $0.signedInAt) > ($1.lastUsedAt ?? $1.signedInAt)
                }
                failure = nil
            } catch {
                failure = AppModel.message(for: error)
            }
        }
    }

    private func signOut(_ session: DeviceSession) {
        sessions?.removeAll { $0.id == session.id }
        model.perform { try await model.householdSource(serverId)?.revokeSession(id: session.id) }
    }
}
