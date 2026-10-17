import SwiftUI

/// Adds a server: own.audio, Audiobookshelf, or a gPodder account that keeps this iPhone's
/// shows and positions in step with other players.
struct AddServerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var kind: ServerKind = .ownAudio
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var code = ""
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if model.pendingTwoFactor != nil {
                    Section {
                        TextField("123456", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .accessibilityIdentifier("addServer.code")
                    } header: {
                        Text("Two-Factor Code")
                    } footer: {
                        Text("Enter the code from your authenticator app.")
                    }
                } else {
                    Section {
                        Picker("Kind", selection: $kind) {
                            ForEach(ServerKind.allCases) { kind in Text(kind.name).tag(kind) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("addServer.kind")
                    } footer: {
                        Text(explanation)
                    }
                    Section {
                        TextField(kind == .ownAudio ? "own.audio" : "http://192.168.1.10:13378", text: $address)
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("addServer.address")
                        TextField(kind == .ownAudio ? "Email" : "User Name", text: $username)
                            .textContentType(kind == .ownAudio ? .emailAddress : .username)
                            .keyboardType(kind == .ownAudio ? .emailAddress : .default)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("addServer.username")
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .accessibilityIdentifier("addServer.password")
                    }
                    if kind == .ownAudio {
                        Section {
                            Button("Try the Public Demo") { Task { await addDemo() } }
                                .accessibilityIdentifier("addServer.demo")
                        } footer: {
                            Text("A shared own.audio server with sample shows, to look around without an account.")
                        }
                    }
                }
                if let error {
                    Text(error).foregroundStyle(Theme.Colors.error).accessibilityIdentifier("addServer.error")
                }
            }
            .navigationTitle("Add a Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.pendingTwoFactor = nil
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Button(model.pendingTwoFactor == nil ? "Add" : "Verify") { Task { await submit() } }
                            .disabled(model.pendingTwoFactor == nil ? address.isEmpty || username.isEmpty || password.isEmpty : code.count < 6)
                            .accessibilityIdentifier("addServer.add")
                    }
                }
            }
        }
    }

    private var explanation: LocalizedStringKey {
        switch kind {
        case .ownAudio: "Your own.audio account: its shows, New Episodes and positions on every device."
        case .audiobookshelf: "The podcast libraries of an Audiobookshelf server, with its downloaded episodes and positions."
        case .gpodder: "A gPodder sync account (podfetch, Nextcloud gPodder Sync): this iPhone's shows and positions are kept in step with your other players."
        }
    }

    private func submit() async {
        isWorking = true
        defer { isWorking = false }
        error = nil
        do {
            if model.pendingTwoFactor != nil {
                try await model.finishTwoFactor(code: code)
            } else {
                try await model.addServer(kind: kind, address: address, username: username, password: password)
            }
            if model.pendingTwoFactor == nil { dismiss() }
        } catch {
            self.error = AppModel.message(for: error)
        }
    }

    private func addDemo() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await model.addDemoServer()
            dismiss()
        } catch {
            self.error = AppModel.message(for: error)
        }
    }
}
