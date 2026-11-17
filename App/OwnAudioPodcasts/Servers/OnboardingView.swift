import SwiftUI

/// The first screen, until a show or a server is added: an own.audio account at the top, as in
/// Music and Books, and below it the ways in that need no account at all.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var sheet: Sheet?
    @State private var isTryingDemo = false
    @State private var errorMessage: String?

    private enum Sheet: Identifiable {
        case search, feed, server, signUp, signIn
        var id: Self { self }
    }

    var body: some View {
        ZStack {
            HeroBackground()
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    OwnAudioMark.tribe(size: 120)
                    RotatingWordmark()
                    Text("Your podcasts. No account, no server needed.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.muted)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("welcome.tagline")
                    ownAudioAccount
                        .padding(.top, Theme.Spacing.lg)
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(Theme.Colors.error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("welcome.error")
                    }
                    Text("Or listen without an account")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.Colors.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Theme.Spacing.md)
                    VStack(spacing: Theme.Spacing.sm) {
                        Button { sheet = .search } label: {
                            Label("Find a Show", systemImage: "magnifyingglass").frame(maxWidth: .infinity, minHeight: Theme.minTarget)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("welcome.search")
                        Button { sheet = .feed } label: {
                            Label("Add a Feed by Address", systemImage: "link").frame(maxWidth: .infinity, minHeight: Theme.minTarget)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("welcome.feed")
                        Button { sheet = .server } label: {
                            Label("Add a Server", systemImage: "server.rack").frame(maxWidth: .infinity, minHeight: Theme.minTarget)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("welcome.server")
                    }
                    Link(destination: URL(string: "https://github.com/own-audio/podcast-ios")!) {
                        Text("Free and open source · MPL-2.0").font(.footnote)
                    }
                    .padding(.top, Theme.Spacing.sm)
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.xxl)
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .search:
                NavigationStack {
                    SearchView()
                        .appDestinations()
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { self.sheet = nil } } }
                }
            case .feed: AddFeedView()
            case .server: AddServerView()
            case .signIn: AddServerView(ownAudio: true)
            case .signUp: SignUpView()
            }
        }
    }

    /// own.audio's hosted service: shows and positions kept in step across devices.
    private var ownAudioAccount: some View {
        VStack(spacing: Theme.Spacing.md) {
            VStack(spacing: Theme.Spacing.xs) {
                Text("Use own.audio")
                    .font(.headline)
                Text("An own.audio account keeps your shows and where you are in them on every device.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.muted)
                    .multilineTextAlignment(.center)
            }
            Button {
                sheet = .signUp
            } label: {
                Text("Create an own.audio Account").bold().frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("welcome.signUp")
            Button {
                sheet = .signIn
            } label: {
                Text("Sign In").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("welcome.signIn")
            // Someone not ready for an account can still see what the app does.
            Button {
                tryDemo()
            } label: {
                if isTryingDemo { ProgressView() } else { Text("Try the Demo Library") }
            }
            .font(.subheadline.weight(.semibold))
            .disabled(isTryingDemo)
            .accessibilityIdentifier("welcome.demo")
            Text("Sample shows on a shared own.audio server, no account needed.")
                .font(.footnote)
                .foregroundStyle(Theme.Colors.muted)
                .multilineTextAlignment(.center)
                .padding(.top, -Theme.Spacing.sm)
        }
        .padding(Theme.Spacing.lg)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.miniPlayer, style: .continuous))
    }

    private func tryDemo() {
        isTryingDemo = true
        errorMessage = nil
        Task {
            do {
                try await model.addDemoServer()
                Haptics.impact(.medium)
            } catch {
                errorMessage = AppModel.message(for: error)
            }
            isTryingDemo = false
        }
    }
}
