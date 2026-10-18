import Foundation
import PodcastLibrary
import UIKit

// The widget, the links that open the app, and the small pictures both of them and the Live
// Activity use. Copied in shape from the books app.

extension AppModel {
    /// A picture as a small JPEG (`size` points square at 2×), kept for the app's lifetime.
    func smallPicture(_ url: URL?, size: CGFloat) async -> Data? {
        guard let url else { return nil }
        if let known = smallPictures[url] { return known }
        guard let (data, _) = try? await Self.session.data(from: url), let image = UIImage(data: data) else { return nil }
        let side = size * 2
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        let small = renderer.jpegData(withCompressionQuality: 0.75) { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        smallPictures[url] = small
        return small
    }

    /// The widget's snapshot a moment later, so a burst of changes writes it once.
    func scheduleWidgetUpdate() {
        widgetTask?.cancel()
        widgetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.updateWidget()
        }
    }

    /// The episode playing (or last played), then the ones under way, then the newest in New
    /// Episodes; three at most.
    func updateWidget() async {
        var picked: [SourcedEpisode] = []
        if let now = nowPlaying { picked.append(now) }
        let started = inbox.filter { (progress[$0.id]?.positionMs ?? 0) > 0 && progress[$0.id]?.played != true }
        for item in started + inbox where !picked.contains(where: { $0.id == item.id }) && picked.count < 3 {
            picked.append(item)
        }
        var entries: [WidgetSnapshot.Entry] = []
        for item in picked {
            let show = show(for: item) ?? (item.id == nowPlaying?.id ? nowPlayingShow : nil)
            let duration = item.id == nowPlaying?.id && engine.durationMs > 0 ? engine.durationMs : (item.episode.durationMs ?? 0)
            let position = item.id == nowPlaying?.id ? engine.positionMs : (progress[item.id]?.positionMs ?? 0)
            entries.append(.init(
                id: item.id, title: item.episode.title, show: show?.title ?? "",
                fraction: duration > 0 ? min(Double(position) / Double(duration), 1) : 0,
                remainingMs: max(duration - position, 0),
                cover: await smallPicture(item.episode.imageURL ?? show?.imageURL, size: 56)
            ))
        }
        WidgetSnapshot(entries: entries, at: Date()).save()
    }

    /// `ownpodcast://play/<id>` from the widget and the Live Activity; `feed://`, `podcast://`
    /// and `pcast://` from a web page or another app, to follow a show.
    func open(_ url: URL) async {
        if let id = WidgetSnapshot.episodeId(from: url) {
            await playLink(id)
        } else if ["feed", "podcast", "pcast"].contains(url.scheme?.lowercased() ?? "") {
            pendingFeedAddress = url.absoluteString
        }
    }

    /// Plays an episode known only by its id: from the lists, the downloads, or its source.
    func playLink(_ id: String) async {
        if nowPlaying?.id == id {
            if !engine.isPlaying { engine.play() }
            return
        }
        if let known = inbox.first(where: { $0.id == id }) ?? downloads.episodes[id]?.item {
            await play(known)
            return
        }
        guard let (ref, key) = SourcedEpisode.parse(id), let source = source(ref),
              let episode = try? await source.episode(key) else {
            actionError = String(localized: "That episode is not here any more.")
            return
        }
        await play(SourcedEpisode(source: ref, episode: episode))
    }
}
