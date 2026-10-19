import Foundation
import OwnAudioKit
import PodcastLibrary

/// A show Discover suggests, and the followed show that brought it up.
struct Suggestion: Identifiable, Hashable {
    var id: String { show.id }
    let show: ShowSearchResult
    let because: String
}

extension AppModel {
    /// The first own.audio server that answers with a catalogue, else Apple's directory.
    var showCatalogue: any ShowCatalogue {
        if let id = catalogueServerId, let server = source(.server(id)) as? OwnAudioPodcastSource {
            return OwnAudioShowCatalogue(client: server.client)
        }
        return AppleShowCatalogue(session: Self.session)
    }

    /// Whether the catalogue knows which shows are alike: only an own.audio one does.
    var catalogueSuggests: Bool { catalogueServerId != nil }

    var catalogueName: String {
        catalogueServerId.flatMap { server($0)?.displayName } ?? "Apple Podcasts"
    }

    /// Asked once per launch, and again when the servers change; a server that answers an error
    /// (no metadata service) is skipped.
    func findCatalogue() async {
        guard !isOffline else { return }
        var found: UUID?
        for record in serversInOrder where record.kind == .ownAudio {
            guard let server = source(.server(record.id)) as? OwnAudioPodcastSource else { continue }
            if await OwnAudioShowCatalogue(client: server.client).isAvailable() {
                found = record.id
                break
            }
        }
        if found != catalogueServerId {
            catalogueServerId = found
            suggestions = nil
        }
    }

    /// "More like your shows": shows like the ones followed most recently, a few from each in
    /// turn, without any already followed. From what is followed, never from what is played.
    func loadSuggestions() async {
        guard catalogueSuggests, !isOffline else { return }
        let catalogue = showCatalogue
        let seeds = shows.filter { $0.show.feedURL != nil }
            .sorted { $0.show.followedAt > $1.show.followedAt }
            .prefix(6)
        var lists: [(String, [ShowSearchResult])] = []
        await withTaskGroup(of: (Int, String, [ShowSearchResult]).self) { group in
            for (index, seed) in seeds.enumerated() {
                group.addTask {
                    let found = (try? await catalogue.similar(to: seed.show.feedURL!)) ?? nil
                    return (index, seed.show.title, found ?? [])
                }
            }
            var collected: [(Int, String, [ShowSearchResult])] = []
            for await answer in group { collected.append(answer) }
            lists = collected.sorted { $0.0 < $1.0 }.map { ($0.1, $0.2) }
        }
        let followed = Set(shows.compactMap { $0.show.feedURL?.absoluteString.lowercased() })
        var seen = followed
        var out: [Suggestion] = []
        var round = 0
        while out.count < 20, lists.contains(where: { round < $0.1.count }) {
            for (because, list) in lists where round < list.count {
                let show = list[round]
                if seen.insert(show.feedURL.absoluteString.lowercased()).inserted {
                    out.append(Suggestion(show: show, because: because))
                }
            }
            round += 1
        }
        suggestions = out
    }

    /// Shows like `feedURL`, from the catalogue; nil without one that knows.
    func similarShows(to feedURL: URL) async -> [ShowSearchResult]? {
        guard catalogueSuggests, !isOffline, let found = try? await showCatalogue.similar(to: feedURL) else { return nil }
        let followed = Set(shows.compactMap { $0.show.feedURL?.absoluteString.lowercased() })
        return found.filter { !followed.contains($0.feedURL.absoluteString.lowercased()) && $0.feedURL != feedURL }
    }
}
