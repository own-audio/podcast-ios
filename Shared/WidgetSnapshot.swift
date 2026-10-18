import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// What the Up Next widget shows: the app writes it into the App Group whenever its lists load
/// or a position moves, the widget only reads. Pictures travel as small JPEGs, so the widget
/// never needs the network or a sign-in. Copied from the books app's `WidgetSnapshot`.
struct WidgetSnapshot: Codable, Equatable {
    struct Entry: Codable, Equatable, Identifiable {
        /// The episode as the app knows it (source and key), as `ownpodcast://play/<id>` wants it.
        let id: String
        let title: String
        /// The show.
        let show: String
        /// 0…1 of the episode listened to; 0 for one not started.
        let fraction: Double
        let remainingMs: Int64
        let cover: Data?
    }

    var entries: [Entry]
    var at: Date

    static let appGroup = "group.audio.own.podcastplayer"
    static let scheme = "ownpodcast"

    private static var file: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appendingPathComponent("up-next.json")
    }

    static func load() -> WidgetSnapshot? {
        guard let file, let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Writes the snapshot and asks the widgets to redraw; nothing happens when only the time changed.
    func save() {
        guard let file = Self.file, Self.load()?.entries != entries, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: file, options: .atomic)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// The link a tap opens; the id carries a `/` and maybe a `#`, so it is escaped whole.
    static func playURL(for id: String) -> URL? {
        guard let escaped = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        return URL(string: "\(scheme)://play/\(escaped)")
    }

    /// The id back out of such a link, or nil for any other link.
    static func episodeId(from url: URL) -> String? {
        guard url.scheme == scheme, url.host() == "play" else { return nil }
        let encoded = url.absoluteString.dropFirst("\(scheme)://play/".count)
        return String(encoded).removingPercentEncoding
    }
}
