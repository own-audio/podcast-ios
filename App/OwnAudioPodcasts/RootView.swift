import SwiftUI

/// The first screen until the library arrives (P2): the own.audio hero, the mark, the
/// wordmark, and what the app is going to ask for — a show, not a server.
struct RootView: View {
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
                Text("Adding shows comes next.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.muted)
                Link(destination: URL(string: "https://github.com/own-audio/podcast-ios")!) {
                    Text("Free and open source · MPL-2.0").font(.footnote)
                }
                .padding(.top, Theme.Spacing.sm)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .frame(maxWidth: 420)
        }
    }
}
