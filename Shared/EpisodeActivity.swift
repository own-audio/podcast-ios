import ActivityKit
import AppIntents
import Foundation

/// The player's Live Activity: what the lock screen and the Dynamic Island show while an
/// episode plays. The attributes are fixed for the episode; the state moves with the position.
/// Copied from the books app's `BookActivity`, with the skip intervals in the state so the
/// buttons' icons say what they do.
struct EpisodeActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var chapter: String?
        var positionMs: Int64
        var durationMs: Int64
        var isPlaying: Bool
        var rate: Float
        /// When `positionMs` was true, so the view can count on while playing.
        var at: Date
        /// A JPEG in the App Group container, by file name. In the state rather than the
        /// attributes: the picture often arrives after the activity has started.
        var coverFile: String?
        var skipBackSecs: Int
        var skipForwardSecs: Int
    }

    /// The episode's id, as `ownpodcast://play/<id>` wants it.
    let episodeId: String
    let title: String
    let show: String

    static let appGroup = "group.audio.own.podcastplayer"

    static func coverURL(file: String?) -> URL? {
        guard let file else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appendingPathComponent(file)
    }

    /// SF Symbols has numbered skip icons for these intervals; others get the plain arrow.
    static func skipSymbol(back: Bool, seconds: Int) -> String {
        let numbered = [5, 10, 15, 30, 45, 60, 75, 90]
        let base = back ? "gobackward" : "goforward"
        return numbered.contains(seconds) ? "\(base).\(seconds)" : base
    }
}

/// The Live Activity's buttons. iOS runs the intent in the app, where `handler` is set; the
/// widget extension only names the type.
struct PlaybackControlIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Control Playback"
    static let isDiscoverable = false

    enum Action: String, AppEnum {
        case toggle, back, forward
        static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Action")
        static let caseDisplayRepresentations: [Action: DisplayRepresentation] = [
            .toggle: "Play or Pause", .back: "Skip Back", .forward: "Skip Forward",
        ]
    }

    @Parameter(title: "Action")
    var action: Action

    init() {}
    init(_ action: Action) { self.action = action }

    /// Set by the app at launch; nil in the widget extension.
    nonisolated(unsafe) static var handler: (@MainActor (Action) async -> Void)?

    @MainActor
    func perform() async throws -> some IntentResult {
        await Self.handler?(action)
        return .result()
    }
}
