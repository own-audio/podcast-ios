import SwiftUI

/// Servers, playback, and about.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var isAddingServer = false
    @State private var removing: ServerRecord?

    /// Green when an address answers, orange when none does, grey while unknown.
    private func connectionDot(_ server: ServerRecord) -> some View {
        let color: Color = switch model.connectionStates[server.id] {
        case .connected?: Theme.Colors.success
        case .unreachable?: .orange
        default: Theme.Colors.muted
        }
        return Circle().fill(color).frame(width: 10, height: 10).overlay(Circle().stroke(Theme.Colors.background, lineWidth: 2)).accessibilityHidden(true)
    }

    var body: some View {
        @Bindable var settings = model.settings
        NavigationStack {
            Form {
                Section {
                    ForEach(model.serversInOrder) { server in
                        NavigationLink {
                            ServerDetailView(serverId: server.id)
                        } label: {
                            HStack(spacing: Theme.Spacing.md) {
                                ServerIcon(brand: ServerBrand(server), image: model.serverIcons[server.id], size: 32)
                                    .overlay(alignment: .bottomTrailing) { connectionDot(server).offset(x: 3, y: 3) }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(server.displayName).foregroundStyle(Theme.Colors.foreground)
                                    Text("\(server.kind.name) · \(server.username)").font(.caption).foregroundStyle(Theme.Colors.muted)
                                }
                            }
                        }
                        .swipeActions {
                            Button("Remove", role: .destructive) { removing = server }
                        }
                        .accessibilityIdentifier("settings.server.\(server.displayName)")
                    }
                    Button { isAddingServer = true } label: { Label("Add a Server", systemImage: "plus") }
                        .accessibilityIdentifier("settings.addServer")
                } header: {
                    Text("Servers")
                } footer: {
                    Text("Shows you follow on this iPhone need no server. A server adds its own shows; a gPodder account keeps this iPhone's in step with your other players.")
                }
                Section("Playback") {
                    Picker("Skip Back", selection: $settings.skipBackwardSecs) {
                        ForEach(PlaybackSettings.skipChoices, id: \.self) { Text("\(Int($0)) s").tag($0) }
                    }
                    Picker("Skip Forward", selection: $settings.skipForwardSecs) {
                        ForEach(PlaybackSettings.skipChoices, id: \.self) { Text("\(Int($0)) s").tag($0) }
                    }
                    Picker("Speed", selection: $settings.defaultRate) {
                        ForEach([Float(0.8), 0.9, 1.0, 1.1, 1.2, 1.3, 1.5, 1.75, 2.0], id: \.self) { Text(String(format: "%.2g×", $0)).tag($0) }
                    }
                    Toggle("Smart Rewind", isOn: $settings.smartRewind)
                }
                Section("About") {
                    LabeledContent("Version", value: AppModel.appVersion)
                    Link("Source Code (MPL-2.0)", destination: URL(string: "https://github.com/own-audio/podcast-ios")!)
                    Link("Privacy", destination: URL(string: "https://github.com/own-audio/podcast-ios/blob/main/PRIVACY.md")!)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("settings.done") } }
            .onChange(of: settings.skipForwardSecs) { model.applyPlaybackSettings() }
            .onChange(of: settings.skipBackwardSecs) { model.applyPlaybackSettings() }
            .onChange(of: settings.smartRewind) { model.applyPlaybackSettings() }
            .sheet(isPresented: $isAddingServer) { AddServerView() }
            .confirmationDialog("Remove \(removing?.displayName ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible, presenting: removing) { server in
                Button("Remove", role: .destructive) { Task { await model.removeServer(server.id) } }
            } message: { server in
                Text(server.kind == .gpodder ? "Shows on this iPhone stay; they are no longer kept in step." : "Its shows leave this iPhone. Nothing changes on the server.")
            }
        }
    }
}
