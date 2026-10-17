import Foundation
import Observation

/// The listener's preferences, in UserDefaults: skip intervals, the speed episodes start at
/// (a show can have its own), smart rewind, and Offline Mode.
@Observable
@MainActor
final class PlaybackSettings {
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        skipForwardSecs = defaults.object(forKey: "playback.skipForward") as? Double ?? 30
        skipBackwardSecs = defaults.object(forKey: "playback.skipBackward") as? Double ?? 15
        defaultRate = defaults.object(forKey: "playback.defaultRate") as? Float ?? 1.0
        smartRewind = defaults.object(forKey: "playback.smartRewind") as? Bool ?? true
        offlineMode = defaults.bool(forKey: "downloads.offlineMode")
    }

    /// Show and play only what is on the phone, and ask nothing of feeds or servers.
    var offlineMode: Bool { didSet { defaults.set(offlineMode, forKey: "downloads.offlineMode") } }
    var skipForwardSecs: Double { didSet { defaults.set(skipForwardSecs, forKey: "playback.skipForward") } }
    var skipBackwardSecs: Double { didSet { defaults.set(skipBackwardSecs, forKey: "playback.skipBackward") } }
    var defaultRate: Float { didSet { defaults.set(defaultRate, forKey: "playback.defaultRate") } }
    var smartRewind: Bool { didSet { defaults.set(smartRewind, forKey: "playback.smartRewind") } }

    static let skipChoices: [Double] = [5, 10, 15, 30, 45, 60, 90]
}
