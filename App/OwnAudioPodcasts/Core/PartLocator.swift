import Foundation
import PodcastLibrary
import SpokenEngine

/// Where an episode plays from, decided every time it is needed — at play, when the player asks
/// before loading, and offline for the lists: the listener's download first, then the listening
/// cache, then the stream. From own.audio Books' `PartLocator`; an episode is one file, so there
/// is no partly downloaded case here.
struct PartLocator {
    enum Source: Equatable {
        case downloaded(URL)
        case cached(URL)
        case stream

        var localURL: URL? {
            switch self {
            case .downloaded(let url), .cached(let url): url
            case .stream: nil
            }
        }
    }

    /// The listener's download of an episode (`DownloadManager.fileURL`).
    var downloaded: @MainActor (_ id: String) -> URL?
    /// A whole copy in the listening cache.
    var cached: @Sendable (_ id: String) async -> URL?

    @MainActor
    func locate(_ id: String) async -> Source {
        if let url = downloaded(id) { return .downloaded(url) }
        if let url = await cached(id) { return .cached(url) }
        return .stream
    }

    /// The player's part for an episode that streams. Only the file itself streams through the
    /// look-ahead window: an HLS playlist or a stream a server makes as it plays has no length
    /// to fetch pieces of. The type goes with the file, for an address with no extension.
    static func streamedPart(_ playback: Playback, durationMs: Int64, contentType: String?) -> SpokenPart {
        let original = !playback.isHLS && !playback.isTranscode
        return SpokenPart(
            id: AppModel.episodePartId, url: playback.url, durationMs: durationMs, isHLS: playback.isHLS,
            streamsByRange: original, contentType: original ? contentType : nil
        )
    }

    /// Episode ids with a whole copy in the listening cache, read from its file names (the cache
    /// names a file by the id in URL-safe base64): the lists must know at once, with no network,
    /// which episodes play.
    nonisolated static func cachedIds(in directory: URL) -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(names.compactMap { name in
            let base = (name as NSString).deletingPathExtension
                .replacingOccurrences(of: "_", with: "/")
                .replacingOccurrences(of: "-", with: "+")
            return Data(base64Encoded: base).flatMap { String(data: $0, encoding: .utf8) }
        })
    }
}

/// The player asked for a link in Offline Mode (the listener's choice): a message, since no
/// signal is coming to end a wait.
struct PartNotOnPhone: LocalizedError {
    var errorDescription: String? {
        String(localized: "This episode is not on this iPhone. Download it, or turn Offline Mode off.")
    }
}

/// The player asked for a link while there is no network: it waits for one ("No signal —
/// waiting") and tries again when the network returns.
struct NoSignal: LocalizedError, NetworkUnavailable {
    var errorDescription: String? { String(localized: "No signal — waiting") }
}
