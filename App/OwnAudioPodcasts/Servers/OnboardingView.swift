import SwiftUI

/// The first screen, until a show or a server is added: no account is needed, so the first
/// thing offered is finding a show.
struct OnboardingView: View {
    @State private var sheet: Sheet?

    private enum Sheet: Identifiable {
        case search, feed, server
        var id: Self { self }
    }

    var body: some View {
        ZStack {
            HeroBackground()
            VStack(spacing: Theme.Spacing.md) {
                OwnAudioMark.tribe(size: 72)
                RotatingWordmark()
                Text("Your podcasts. No account, no server needed.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.muted)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("welcome.tagline")
                VStack(spacing: Theme.Spacing.sm) {
                    Button { sheet = .search } label: {
                        Label("Find a Show", systemImage: "magnifyingglass").frame(maxWidth: .infinity, minHeight: Theme.minTarget)
                    }
                    .buttonStyle(.borderedProminent)
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
                .padding(.top, Theme.Spacing.lg)
                Link(destination: URL(string: "https://github.com/own-audio/podcast-ios")!) {
                    Text("Free and open source · MPL-2.0").font(.footnote)
                }
                .padding(.top, Theme.Spacing.sm)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .frame(maxWidth: 420)
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
            }
        }
    }
}
