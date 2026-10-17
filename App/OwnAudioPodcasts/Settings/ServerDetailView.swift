import SwiftUI

/// One server: whether it answers and accepts the sign-in, the account, what it is, which
/// address is in use and how it is picked, every address it is known by, and its name.
struct ServerDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let serverId: UUID
    @State private var isAddingAddress = false
    @State private var newAddress = ""
    @State private var isRenaming = false
    @State private var newName = ""
    @State private var isSigningIn = false
    @State private var confirmRemove = false
    @State private var errorMessage: String?
    @State private var isSyncing = false

    private var server: ServerRecord? { model.server(serverId) }

    var body: some View {
        if let server {
            List {
                Section {
                    statusRow(server)
                    Button {
                        Task { await model.checkNow(id: server.id) }
                    } label: {
                        HStack {
                            Text("Check Now")
                            Spacer()
                            if model.checkingConnections.contains(server.id) { ProgressView() }
                        }
                    }
                    .disabled(model.checkingConnections.contains(server.id) || model.isOffline)
                    .accessibilityIdentifier("serverDetail.check")
                    checkResult(server)
                }

                Section {
                    Button("Sign In Again") { isSigningIn = true }
                        .accessibilityIdentifier("serverDetail.signInAgain")
                } header: {
                    Text("Account")
                } footer: {
                    Text("Signed in as \(server.username).")
                }

                Section {
                    LabeledContent("Kind", value: server.kind.name)
                    if let version = model.serverVersions[server.id] {
                        LabeledContent("Version", value: version)
                            .accessibilityIdentifier("serverDetail.version")
                    }
                    Button {
                        newName = server.displayName
                        isRenaming = true
                    } label: {
                        LabeledContent("Name", value: server.displayName)
                    }
                    .foregroundStyle(Theme.Colors.foreground)
                    .accessibilityIdentifier("serverDetail.rename")
                } header: {
                    Text("Server")
                }

                if server.kind == .gpodder {
                    Section {
                        Button {
                            Task {
                                isSyncing = true
                                defer { isSyncing = false }
                                do { try await model.syncNow(id: server.id) } catch { errorMessage = AppModel.message(for: error) }
                            }
                        } label: {
                            HStack {
                                Text("Sync Now")
                                Spacer()
                                if isSyncing { ProgressView() }
                            }
                        }
                        .disabled(isSyncing || model.isOffline)
                        .accessibilityIdentifier("serverDetail.sync")
                        if let last = model.lastSyncs[server.id] {
                            LabeledContent("Last Synced", value: last.formatted(.relative(presentation: .named)))
                        }
                    } header: {
                        Text("Sync")
                    } footer: {
                        Text("This iPhone's shows and positions are kept in step with the account, as every other app signed in to it does.")
                    }
                }

                Section("Connection") {
                    Picker("Use", selection: Binding(
                        get: { server.fixedAddress },
                        set: { url in Task { await model.setFixedAddress(url, for: server.id) } }
                    )) {
                        Text("Automatic").tag(URL?.none)
                        ForEach(server.candidateAddresses) { address in
                            Text(address.url.absoluteString).tag(URL?.some(address.url))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .accessibilityIdentifier("serverDetail.mode")
                }

                Section {
                    ForEach(server.candidateAddresses) { address in
                        addressRow(address)
                            .swipeActions {
                                if address.origin != .added {
                                    Button(role: .destructive) {
                                        Task { await model.removeAddress(address.url, from: server.id) }
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                            }
                    }
                    Button {
                        newAddress = ""
                        isAddingAddress = true
                    } label: {
                        Label("Add Address", systemImage: "plus")
                    }
                    .accessibilityIdentifier("serverDetail.addAddress")
                } header: {
                    Text("Addresses")
                } footer: {
                    Text(server.kind == .ownAudio
                         ? "The server tells the app its other addresses. Add one it doesn't know, such as a VPN like Tailscale; on each network the app uses the fastest that answers as this server."
                         : "Add the server's address on your home network, a VPN such as Tailscale, or a second public name. On each network the app uses the fastest one that answers.")
                }

                Section {
                    Button("Remove Server", role: .destructive) { confirmRemove = true }
                        .accessibilityIdentifier("serverDetail.remove")
                }
            }
            .navigationTitle(server.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .task(id: server.id) {
                if model.connectionChecks[server.id] == nil, !model.isOffline { await model.checkNow(id: server.id) }
            }
            .sheet(isPresented: $isSigningIn) { SignInAgainView(server: server) }
            .alert("Add Address", isPresented: $isAddingAddress) {
                TextField("http://192.168.1.20:8080", text: $newAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button("Cancel", role: .cancel) {}
                Button("Add") {
                    let text = newAddress
                    Task {
                        do { try await model.addAddress(text, to: server.id) } catch { errorMessage = AppModel.message(for: error) }
                    }
                }
            }
            .alert("Rename", isPresented: $isRenaming) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    let name = newName
                    Task { await model.rename(id: server.id, to: name) }
                }
            }
            .alert("That Didn't Work", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .confirmationDialog("Remove \(server.displayName)?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    Task {
                        await model.removeServer(server.id)
                        dismiss()
                    }
                }
            } message: {
                Text(server.kind == .gpodder ? "Shows on this iPhone stay; they are no longer kept in step." : "Its shows leave this iPhone. Nothing changes on the server.")
            }
        }
    }

    @ViewBuilder
    private func statusRow(_ server: ServerRecord) -> some View {
        switch model.connectionStates[server.id] {
        case .connected(let url):
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connected · \(AddressScope.infer(url).title)")
                    Text(url.absoluteString).font(.caption).foregroundStyle(Theme.Colors.muted)
                }
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Colors.success)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("serverDetail.status")
        case .unreachable:
            Label("No address answers right now", systemImage: "wifi.exclamationmark")
                .foregroundStyle(.orange)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("serverDetail.status")
        case .checking, nil:
            Label(model.isOffline ? "Offline" : "Checking…", systemImage: "antenna.radiowaves.left.and.right")
                .foregroundStyle(Theme.Colors.muted)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("serverDetail.status")
        }
    }

    /// What the last check found, so the button visibly did something.
    @ViewBuilder
    private func checkResult(_ server: ServerRecord) -> some View {
        if !model.checkingConnections.contains(server.id), let check = model.connectionChecks[server.id] {
            let when = check.at.formatted(date: .omitted, time: .shortened)
            Group {
                switch check.status {
                case .ok:
                    Label("Checked at \(when): the server answers and accepts the sign-in.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Colors.success)
                case .rejected:
                    Label("Checked at \(when): the server refuses the sign-in. Sign in again below.", systemImage: "xmark.circle.fill")
                        .foregroundStyle(Theme.Colors.error)
                case .unreachable:
                    Label("Checked at \(when): no address of the server answers.", systemImage: "wifi.exclamationmark")
                        .foregroundStyle(.orange)
                }
            }
            .font(.footnote)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("serverDetail.checkResult")
        }
    }

    private func addressRow(_ address: ServerAddress) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(address.url.absoluteString).lineLimit(1)
            Text("\(address.scope.title) · \(address.origin.title)")
                .font(.caption)
                .foregroundStyle(Theme.Colors.muted)
        }
        .accessibilityIdentifier("serverDetail.address.\(address.url.absoluteString)")
    }
}

extension ServerAddress.Origin {
    var title: String {
        switch self {
        case .added: String(localized: "added with")
        case .server: String(localized: "from the server")
        case .user: String(localized: "added by you")
        }
    }
}

/// The saved server's sign-in, entered again: its user name kept, the password asked for.
private struct SignInAgainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let server: ServerRecord
    @State private var username = ""
    @State private var password = ""
    @State private var code = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if model.pendingTwoFactor?.replacing == server.id {
                    Section {
                        TextField("123456", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                    } header: {
                        Text("Two-Factor Code")
                    } footer: {
                        Text("Enter the code from your authenticator app.")
                    }
                } else {
                    Section {
                        TextField(server.kind == .ownAudio ? "Email" : "User Name", text: $username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("signInAgain.username")
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .accessibilityIdentifier("signInAgain.password")
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Theme.Colors.error)
                }
            }
            .navigationTitle(server.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if model.pendingTwoFactor?.replacing == server.id { model.pendingTwoFactor = nil }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Button(model.pendingTwoFactor?.replacing == server.id ? "Verify" : "Sign In") { Task { await submit() } }
                            .disabled(model.pendingTwoFactor?.replacing == server.id ? code.count < 6 : username.isEmpty || password.isEmpty)
                            .accessibilityIdentifier("signInAgain.submit")
                    }
                }
            }
            .onAppear { username = server.username }
        }
    }

    private func submit() async {
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            if model.pendingTwoFactor?.replacing == server.id {
                try await model.finishTwoFactor(code: code)
            } else {
                try await model.signInAgain(id: server.id, username: username.trimmingCharacters(in: .whitespaces), password: password)
            }
            if model.pendingTwoFactor?.replacing != server.id { dismiss() }
        } catch {
            errorMessage = AppModel.message(for: error)
        }
    }
}
