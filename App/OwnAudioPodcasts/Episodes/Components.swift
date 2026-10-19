import FeedKit
import PodcastLibrary
import SwiftUI

/// A show's or an episode's picture, square, with the mark of the app while it loads or when
/// there is none. Loaded through `ArtworkLoader` rather than `AsyncImage`, which inside a
/// resizing grid can cancel its own load and never try again, and keeps nothing for offline.
struct ArtworkView: View {
    let url: URL?
    var size: CGFloat = 56
    var radius: CGFloat = 8
    @State private var image: UIImage?

    /// A few fixed sizes, so a grid laying itself out doesn't fetch the same picture again.
    private var pixels: Int { size <= 64 ? 192 : size <= 160 ? 480 : 900 }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Theme.Colors.backgroundAlt
                Image(systemName: "mic").font(.system(size: max(size * 0.35, 10))).foregroundStyle(Theme.Colors.muted)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Theme.Colors.border, lineWidth: 0.5))
        .accessibilityHidden(true)
        .task(id: url.map { ArtworkLoader.key($0) + "@\(pixels)" }) {
            guard let url else { image = nil; return }
            let loaded = await ArtworkLoader.shared.image(url, pixels: pixels)
            withAnimation(.easeOut(duration: Theme.coverCrossfade)) { image = loaded }
        }
    }
}

/// Which source something came from, small, under a title.
struct SourceLabel: View {
    @Environment(AppModel.self) private var model
    let source: SourceRef

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: source == .phone ? "iphone" : "server.rack").imageScale(.small)
            Text(model.sourceName(source))
        }
        .font(.caption)
        .foregroundStyle(Theme.Colors.muted)
    }
}

/// One episode in a list: the picture, the show, the title, when and how long, and a play
/// button. Swipes mark it played or take it out of New Episodes.
struct EpisodeRow: View {
    @Environment(AppModel.self) private var model
    let item: SourcedEpisode
    var showsShowTitle = true
    var inInbox = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private func words(episode: Episode, show: Show?, progress: ListeningProgress?, lineLimit: Int?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if showsShowTitle, let show {
                Text(Mojibake.repair(show.title)).font(.caption).foregroundStyle(Theme.Colors.muted).lineLimit(lineLimit == nil ? 2 : 1)
            }
            Text(Mojibake.repair(episode.title))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(progress?.played == true ? Theme.Colors.muted : Theme.Colors.foreground)
                .lineLimit(lineLimit)
            HStack(spacing: 4) {
                if model.isQueued(item) {
                    Image(systemName: "text.line.first.and.arrowtriangle.forward").font(.caption).foregroundStyle(Theme.Colors.accent)
                        .accessibilityLabel("In Up Next")
                }
                DownloadBadge(state: model.downloadState(item))
                Text(ProgressText.line(episode: episode, progress: progress))
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .lineLimit(lineLimit == nil ? nil : 1)
            }
        }
    }

    var body: some View {
        let episode = item.episode
        let show = model.show(for: item)
        let progress = model.progress(of: item)
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // The largest text: the picture and play button on a row of their own, the words
                // the whole width under them.
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack {
                        ArtworkView(url: episode.imageURL ?? show?.imageURL, size: 56)
                        Spacer()
                        PlayButton(item: item)
                    }
                    NavigationLink(value: item) {
                        words(episode: episode, show: show, progress: progress, lineLimit: nil)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("episode.\(episode.id)")
                }
            } else {
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    NavigationLink(value: item) {
                        HStack(alignment: .top, spacing: Theme.Spacing.md) {
                            ArtworkView(url: episode.imageURL ?? show?.imageURL, size: 56)
                            words(episode: episode, show: show, progress: progress, lineLimit: 2)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("episode.\(episode.id)")
                    PlayButton(item: item)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        // Offline, what isn't on the phone can't play.
        .opacity(model.canPlay(item) ? 1 : 0.45)
        .swipeActions(edge: .leading) {
            Button {
                Task { await model.markPlayed(item, progress?.played != true) }
            } label: {
                progress?.played == true ? Label("Unplayed", systemImage: "circle") : Label("Played", systemImage: "checkmark.circle")
            }
            .tint(Theme.Colors.accent)
        }
        .swipeActions(edge: .trailing) {
            if inInbox {
                Button {
                    Task { await model.dismiss(item) }
                } label: {
                    Label("Dismiss", systemImage: "tray.and.arrow.up")
                }
                .tint(.gray)
            }
        }
        .contextMenu {
            Button {
                Task { await model.play(item) }
            } label: { Label("Play", systemImage: "play") }
            Button {
                Task { await model.markPlayed(item, progress?.played != true) }
            } label: {
                progress?.played == true ? Label("Mark as Unplayed", systemImage: "circle") : Label("Mark as Played", systemImage: "checkmark.circle")
            }
            if model.isQueued(item) {
                Button { model.removeFromUpNext(item.id) } label: { Label("Remove from Up Next", systemImage: "minus.circle") }
            } else {
                Button { model.playNext(item) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
                Button { model.playLater(item) } label: { Label("Play Later", systemImage: "text.line.last.and.arrowtriangle.forward") }
            }
            switch model.downloadState(item) {
            case nil:
                Button { model.download(item) } label: { Label("Download", systemImage: "arrow.down.circle") }
                    .disabled(model.isOffline)
            case .failed?:
                Button { model.removeDownload(item); model.download(item) } label: { Label("Try the Download Again", systemImage: "arrow.clockwise") }
                    .disabled(model.isOffline)
                Button(role: .destructive) { model.removeDownload(item) } label: { Label("Remove Download", systemImage: "trash") }
            case .downloading?:
                Button(role: .destructive) { model.removeDownload(item) } label: { Label("Cancel Download", systemImage: "xmark.circle") }
            case .downloaded?:
                Button(role: .destructive) { model.removeDownload(item) } label: { Label("Remove Download", systemImage: "trash") }
            }
            if inInbox {
                Button {
                    Task { await model.dismiss(item) }
                } label: { Label("Remove from New Episodes", systemImage: "tray.and.arrow.up") }
            }
        }
    }
}

/// Plays the episode, or pauses it when it is the one playing.
struct PlayButton: View {
    @Environment(AppModel.self) private var model
    let item: SourcedEpisode

    var body: some View {
        let isCurrent = model.nowPlaying?.id == item.id
        let isPlaying = isCurrent && model.engine.isPlaying
        Button {
            Haptics.impact(.medium)
            if isCurrent {
                model.engine.togglePlayPause()
            } else {
                Task { await model.play(item) }
            }
        } label: {
            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.title)
                .foregroundStyle(Theme.Colors.accent)
                .frame(minWidth: Theme.minTarget, minHeight: Theme.minTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!model.canPlay(item))
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
        .accessibilityIdentifier("play.\(item.episode.id)")
    }
}

/// Durations, dates and positions as the screens say them.
enum ProgressText {
    /// "1 h 12 min", "38 min".
    static func length(_ ms: Int64) -> String {
        let minutes = Int((Double(ms) / 60_000).rounded())
        let hours = minutes / 60
        if hours > 0 {
            return minutes % 60 == 0 ? String(localized: "\(hours) h") : String(localized: "\(hours) h \(minutes % 60) min")
        }
        return String(localized: "\(max(minutes, 1)) min")
    }

    /// "1:02:07" or "3:07".
    static func clock(_ ms: Int64) -> String {
        formatDuration(Double(max(ms, 0)) / 1000)
    }

    /// "16 Oct · 48 min", "16 Oct · 12 min left", "16 Oct · Played".
    static func line(episode: Episode, progress: ListeningProgress?) -> String {
        var parts: [String] = []
        if let date = episode.publishedAt { parts.append(date.formatted(Self.dateStyle(date))) }
        if progress?.played == true {
            parts.append(String(localized: "Played"))
        } else if let progress, progress.positionMs > 0, let duration = episode.durationMs, duration > progress.positionMs {
            parts.append(String(localized: "\(length(duration - progress.positionMs)) left"))
        } else if let duration = episode.durationMs, duration > 0 {
            parts.append(length(duration))
        }
        return parts.joined(separator: " · ")
    }

    private static func dateStyle(_ date: Date) -> Date.FormatStyle {
        Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
            ? .dateTime.day().month(.abbreviated)
            : .dateTime.day().month(.abbreviated).year()
    }

    /// "2 h 10 min left" at the speed the episode plays at.
    static func leftAtSpeed(_ ms: Int64, rate: Float) -> String {
        let atSpeed = Int64(Double(max(ms, 0)) / Double(max(rate, 0.1)))
        return String(localized: "\(length(atSpeed)) left")
    }
}

/// Plain text with its web addresses made into links.
func linkedText(_ text: String) -> AttributedString {
    var attributed = AttributedString(text)
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return attributed }
    for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
        guard let url = match.url, let range = Range(match.range, in: text),
              let lower = AttributedString.Index(range.lowerBound, within: attributed),
              let upper = AttributedString.Index(range.upperBound, within: attributed) else { continue }
        attributed[lower..<upper].link = url
    }
    return attributed
}

/// The download button on an episode's page: an arrow, a ring while downloading, a check when
/// done. Copied from the books app's.
struct DownloadButton: View {
    @Environment(AppModel.self) private var model
    let item: SourcedEpisode
    @State private var isConfirmingRemove = false

    var body: some View {
        let state = model.downloadState(item)
        Button {
            switch state {
            case .downloaded: isConfirmingRemove = true
            case .downloading: break
            case .failed: model.removeDownload(item); model.download(item)
            case nil: model.download(item)
            }
        } label: {
            Group {
                switch state {
                case .downloaded:
                    Image(systemName: "checkmark.circle.fill").font(.title2)
                case .downloading(let fraction):
                    ZStack {
                        Circle().stroke(Theme.Colors.accent.opacity(0.25), lineWidth: 3)
                        Circle().trim(from: 0, to: max(fraction, 0.02)).stroke(Theme.Colors.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                    }
                    .frame(width: 22, height: 22)
                case .failed:
                    Image(systemName: "exclamationmark.arrow.circlepath").font(.title2)
                case nil:
                    Image(systemName: "arrow.down.circle").font(.title2)
                }
            }
            .frame(minWidth: Theme.minTarget, minHeight: Theme.minTarget)
        }
        .buttonStyle(.bordered)
        .tint(Theme.Colors.accent)
        .disabled(model.isOffline && state == nil)
        .accessibilityIdentifier("episode.download")
        .accessibilityLabel(label(state))
        .confirmationDialog("Remove Download?", isPresented: $isConfirmingRemove, titleVisibility: .visible) {
            Button("Remove Download", role: .destructive) { model.removeDownload(item) }
                .accessibilityIdentifier("episode.download.remove")
        }
    }

    private func label(_ state: DownloadManager.State?) -> String {
        switch state {
        case .downloaded: String(localized: "Downloaded")
        case .downloading(let fraction): String(localized: "Downloading \(Int(fraction * 100))%")
        case .failed: String(localized: "Download failed, try again")
        case nil: String(localized: "Download")
        }
    }
}

/// Beside an episode's date: a ring while downloading, an arrow when it is on the phone.
struct DownloadBadge: View {
    let state: DownloadManager.State?

    var body: some View {
        switch state {
        case .downloaded:
            Image(systemName: "arrow.down.circle.fill")
                .font(.caption)
                .foregroundStyle(Theme.Colors.accent)
                .accessibilityLabel("Downloaded")
        case .downloading(let fraction):
            ZStack {
                Circle().stroke(Theme.Colors.accent.opacity(0.25), lineWidth: 1.5)
                Circle().trim(from: 0, to: max(fraction, 0.02)).stroke(Theme.Colors.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round)).rotationEffect(.degrees(-90))
            }
            .frame(width: 11, height: 11)
            .accessibilityLabel("Downloading")
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(Theme.Colors.error)
                .accessibilityLabel("Download failed")
        case nil:
            EmptyView()
        }
    }
}

/// Something a screen loads: still coming, here, or failed with a message to show. Copied from
/// the books app.
enum LoadState<Value> {
    case loading
    case loaded(Value)
    case failed(String)
}

struct LoadStateView<Value, Content: View>: View {
    let state: LoadState<Value>
    let retry: () -> Void
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        switch state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 120)
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't Load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { retry() }.accessibilityIdentifier("load.retry")
            }
        case .loaded(let value):
            content(value)
        }
    }
}
