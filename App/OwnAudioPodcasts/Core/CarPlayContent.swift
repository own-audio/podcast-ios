import CarPlay
import Foundation
import PodcastLibrary

/// What the car's screen shows, kept apart from the scene delegate so the unit tests can check it
/// without a car: the start list, which episodes each list holds and in what order, a row's
/// progress bar, and the speed the rate button goes to next.
enum CarPlayContent {
    /// CarPlay's guidelines ask for short lists; the system also caps them.
    static let maxItems = 100

    enum RootEntry: CaseIterable, Equatable {
        case newEpisodes, downloads, shows

        var title: String {
            switch self {
            case .newEpisodes: String(localized: "New Episodes")
            case .downloads: String(localized: "Downloads")
            case .shows: String(localized: "Shows")
            }
        }

        var symbol: String {
            switch self {
            case .newEpisodes: "tray"
            case .downloads: "arrow.down.circle"
            case .shows: "square.grid.2x2"
            }
        }
    }

    /// New Episodes first and downloads next, because a car often has no signal. With nothing
    /// followed, no lists at all: the start screen says to follow a show on the iPhone.
    static func rootEntries(hasShows: Bool) -> [RootEntry] {
        hasShows ? RootEntry.allCases : []
    }

    /// Offline, only what is on the phone; never more than the cap.
    static func newEpisodes(_ inbox: [SourcedEpisode], canPlay: (SourcedEpisode) -> Bool) -> [SourcedEpisode] {
        Array(inbox.filter(canPlay).prefix(maxItems))
    }

    /// Finished downloads, the newest first, from the download index alone so it works with no
    /// signal.
    static func downloads(_ entries: [DownloadManager.DownloadedEpisode]) -> [SourcedEpisode] {
        let done = entries.filter(\.isComplete).sorted { ($0.finishedAt ?? $0.startedAt) > ($1.finishedAt ?? $1.startedAt) }
        return Array(done.compactMap(\.item).prefix(maxItems))
    }

    /// One show's episodes, the newest first, only the playable ones.
    static func showEpisodes(_ episodes: [SourcedEpisode], canPlay: (SourcedEpisode) -> Bool) -> [SourcedEpisode] {
        let sorted = episodes.sorted { ($0.episode.publishedAt ?? .distantPast) > ($1.episode.publishedAt ?? .distantPast) }
        return Array(sorted.filter(canPlay).prefix(maxItems))
    }

    /// How far into an episode, for the row's bar; none for a played or not started one.
    static func progress(_ progress: ListeningProgress?, durationMs: Int64?) -> CGFloat? {
        guard let progress, let durationMs, durationMs > 0, !progress.played, progress.positionMs > 0 else { return nil }
        return CGFloat(min(Double(progress.positionMs) / Double(durationMs), 1))
    }

    /// 1× → 1.25× → … → 2× → 0.75× → 1×, the steps of the phone's speed settings.
    static let rates: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    static func nextRate(after current: Float) -> Float {
        rates.first { $0 > current + 0.01 } ?? rates[0]
    }

    /// A list as the car shows it: one section, the rows, and what it says when empty.
    static func listTemplate(title: String, items: [CPListItem], emptyText: String) -> CPListTemplate {
        let template = CPListTemplate(title: title, sections: [CPListSection(items: Array(items.prefix(maxItems)))])
        template.emptyViewTitleVariants = [emptyText]
        return template
    }
}
