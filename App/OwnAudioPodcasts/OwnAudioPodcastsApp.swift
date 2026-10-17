import SwiftUI

@main
struct OwnAudioPodcastsApp: App {
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.Colors.accent)
        }
    }
}
