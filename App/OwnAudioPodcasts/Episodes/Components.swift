import FeedKit
import PodcastLibrary
import SwiftUI

/// A show's or an episode's picture, square, with the mark of the app while it loads or when
/// there is none.
struct ArtworkView: View {
    let url: URL?
    var size: CGFloat = 56
    var radius: CGFloat = 8

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: Theme.coverCrossfade))) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    Theme.Colors.backgroundAlt
                    Image(systemName: "mic").font(.system(size: size * 0.35)).foregroundStyle(Theme.Colors.muted)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Theme.Colors.border, lineWidth: 0.5))
        .accessibilityHidden(true)
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
            Text(ProgressText.line(episode: episode, progress: progress))
                .font(.caption)
                .foregroundStyle(Theme.Colors.muted)
                .lineLimit(lineLimit == nil ? nil : 1)
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
