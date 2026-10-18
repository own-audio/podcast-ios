import Foundation
import Observation

/// The listener's preferences, in UserDefaults: skip intervals, the speed episodes start at
/// (a show can have its own), smart rewind, Offline Mode, downloads and mobile data.
@Observable
@MainActor
final class PlaybackSettings {
    /// The books app has a third choice, Saver, a smaller stream the server makes; a feed has
    /// one file per episode, so there is nothing smaller to ask for here.
    enum MobileData: String, CaseIterable {
        /// Stream as on Wi-Fi.
        case stream
        /// Play only what is downloaded.
        case downloadedOnly
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        skipForwardSecs = defaults.object(forKey: "playback.skipForward") as? Double ?? 30
        skipBackwardSecs = defaults.object(forKey: "playback.skipBackward") as? Double ?? 15
        defaultRate = defaults.object(forKey: "playback.defaultRate") as? Float ?? 1.0
        smartRewind = defaults.object(forKey: "playback.smartRewind") as? Bool ?? true
        offlineMode = defaults.bool(forKey: "downloads.offlineMode")
        wifiOnlyDownloads = defaults.object(forKey: "downloads.wifiOnly") as? Bool ?? true
        storageCapBytes = defaults.object(forKey: "downloads.capBytes") as? Int64
        mobileData = MobileData(rawValue: defaults.string(forKey: "playback.mobileData") ?? "") ?? .stream
    }

    var wifiOnlyDownloads: Bool { didSet { defaults.set(wifiOnlyDownloads, forKey: "downloads.wifiOnly") } }
    /// nil is no limit.
    var storageCapBytes: Int64? { didSet { defaults.set(storageCapBytes, forKey: "downloads.capBytes") } }
    var mobileData: MobileData { didSet { defaults.set(mobileData.rawValue, forKey: "playback.mobileData") } }

    static let storageCapChoices: [Int64?] = [nil, 1 << 30, 2 << 30, 5 << 30, 10 << 30]

    /// Show and play only what is on the phone, and ask nothing of feeds or servers.
    var offlineMode: Bool { didSet { defaults.set(offlineMode, forKey: "downloads.offlineMode") } }
    var skipForwardSecs: Double { didSet { defaults.set(skipForwardSecs, forKey: "playback.skipForward") } }
    var skipBackwardSecs: Double { didSet { defaults.set(skipBackwardSecs, forKey: "playback.skipBackward") } }
    var defaultRate: Float { didSet { defaults.set(defaultRate, forKey: "playback.defaultRate") } }
    var smartRewind: Bool { didSet { defaults.set(smartRewind, forKey: "playback.smartRewind") } }

    static let skipChoices: [Double] = [5, 10, 15, 30, 45, 60, 90]
}
