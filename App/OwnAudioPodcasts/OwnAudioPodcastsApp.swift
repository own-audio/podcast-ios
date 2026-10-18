import SwiftUI

/// Registers the background refresh, and hands the background download session's events back to
/// the app (iOS relaunches it when a download finishes while it was gone).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BackgroundRefresh.register()
        return true
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            guard identifier == DownloadManager.sessionIdentifier else { return completionHandler() }
            AppModel.shared.downloads.backgroundCompletion = completionHandler
            AppModel.shared.downloads.resume()
        }
    }
}

@main
struct OwnAudioPodcastsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.Colors.accent)
        }
    }
}
