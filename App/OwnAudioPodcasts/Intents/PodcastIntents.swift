import AppIntents
import Foundation
import PodcastLibrary

/// A show as Siri and Shortcuts see it: its source and id, so the same show on two sources stays
/// two shows. Shaped like the books app's `BookEntity`.
struct ShowEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Show")
    static let defaultQuery = ShowEntityQuery()

    let id: String
    let title: String
    let author: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: author.map { "\($0)" })
    }

    init(_ show: SourcedShow) {
        id = show.id
        title = show.show.title
        author = show.show.author
    }
}

/// Finds shows by what was said, among those followed on every source.
struct ShowEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [ShowEntity] {
        let model = await loadedModel()
        return model.shows.filter { identifiers.contains($0.id) }.map(ShowEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [ShowEntity] {
        let model = await loadedModel()
        let needle = string.trimmingCharacters(in: .whitespaces)
        return model.shows
            .filter { $0.show.title.localizedCaseInsensitiveContains(needle) || ($0.show.author?.localizedCaseInsensitiveContains(needle) ?? false) }
            .prefix(10).map(ShowEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [ShowEntity] {
        await loadedModel().shows.prefix(10).map(ShowEntity.init)
    }

    @MainActor
    private func loadedModel() async -> AppModel {
        let model = AppModel.shared
        if !model.hasLoaded { await model.load() }
        return model
    }
}

/// "Play Hacker Public Radio in own.podcast": the episode under way, else the newest unplayed.
struct PlayShowIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play a Show"
    static let description = IntentDescription("Plays a show you follow: the episode you are in, or its newest.")

    @Parameter(title: "Show")
    var show: ShowEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$show)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let model = AppModel.shared
        if !model.hasLoaded { await model.load() }
        guard let followed = model.shows.first(where: { $0.id == show.id }) else { throw IntentError.notFound }
        guard let episodes = try? await model.episodes(of: followed), !episodes.isEmpty else { throw IntentError.nothingToPlay }
        let byDate = episodes.sorted { ($0.episode.publishedAt ?? .distantPast) > ($1.episode.publishedAt ?? .distantPast) }
        let under = byDate.first { (model.progress(of: $0)?.positionMs ?? 0) > 0 && model.progress(of: $0)?.played != true }
        let next = under ?? byDate.first { model.progress(of: $0)?.played != true && model.canPlay($0) } ?? byDate[0]
        try await play(next, model: model)
        return .result()
    }
}

/// "Continue listening in own.podcast": the episode in the player, else the last one played,
/// else one under way, else the newest new episode.
struct ContinueListeningIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Continue Listening"
    static let description = IntentDescription("Goes on with the episode you were listening to.")

    @MainActor
    func perform() async throws -> some IntentResult {
        let model = AppModel.shared
        if !model.hasLoaded { await model.load() }
        if model.nowPlaying == nil { await model.restoreLastPlayed() }
        if model.nowPlaying != nil {
            if !model.engine.isPlaying { model.engine.play() }
            return .result()
        }
        let candidates = model.inbox.filter(model.canPlay)
        let under = candidates.first { (model.progress(of: $0)?.positionMs ?? 0) > 0 }
        guard let next = under ?? candidates.first else { throw IntentError.nothingToPlay }
        try await play(next, model: model)
        return .result()
    }
}

/// Siri can't be asked where to continue: the newer position wins, as in the car.
@MainActor
private func play(_ item: SourcedEpisode, model: AppModel) async throws {
    await model.play(item)
    if let pending = model.pendingResume {
        model.pendingResume = nil
        await model.play(pending.episode, startAt: pending.otherMs)
    }
    if model.nowPlaying?.id != item.id { throw IntentError.cantPlay }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case notFound, nothingToPlay, cantPlay

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notFound: "You don't follow that show any more."
        case .nothingToPlay: "There is nothing to play; follow a show in own.podcast first."
        case .cantPlay: "That episode can't play right now."
        }
    }
}

/// The phrases Siri answers to without any setup in Shortcuts.
struct PodcastShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ContinueListeningIntent(),
            phrases: [
                "Continue listening in \(.applicationName)",
                "Continue my podcast in \(.applicationName)",
                "Resume my podcast in \(.applicationName)",
            ],
            shortTitle: "Continue Listening",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: PlayShowIntent(),
            phrases: [
                "Play \(\.$show) in \(.applicationName)",
                "Listen to \(\.$show) in \(.applicationName)",
            ],
            shortTitle: "Play a Show",
            systemImageName: "mic"
        )
    }
}
