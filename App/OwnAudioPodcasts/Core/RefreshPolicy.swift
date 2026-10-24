import Foundation

/// When a refresh of every feed and server runs. A full refresh is a gPodder sync, a fetch of
/// every RSS feed, a request per show on own.audio and Audiobookshelf, and the download rules:
/// too much to run each time the app comes back from Control Center or the phone moves from
/// Wi-Fi to mobile data. So the app's own refreshes wait at least `minimumInterval` after the
/// last one and never run in the background while an episode plays; a pull to refresh always runs.
enum RefreshPolicy {
    static let minimumInterval: TimeInterval = 15 * 60

    enum Trigger: Equatable {
        /// The listener pulled the list down, or turned Offline Mode off.
        case asked
        /// The app by itself: launch, coming to the front, a new network, the background task.
        case automatic
    }

    static func shouldRun(_ trigger: Trigger, lastRun: Date?, now: Date, inBackground: Bool, isPlaying: Bool) -> Bool {
        switch trigger {
        case .asked:
            return true
        case .automatic:
            if inBackground && isPlaying { return false }
            guard let lastRun else { return true }
            return now.timeIntervalSince(lastRun) >= minimumInterval
        }
    }

    /// Whether sources should skip their own short-lived caches (Audiobookshelf's ten minutes
    /// per feed): only when the listener asked.
    static func forcesFeeds(_ trigger: Trigger) -> Bool { trigger == .asked }
}
