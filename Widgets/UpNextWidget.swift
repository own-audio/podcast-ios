import SwiftUI
import WidgetKit

@main
struct OwnAudioPodcastsWidgets: WidgetBundle {
    var body: some Widget {
        UpNextWidget()
        EpisodeLiveActivity()
    }
}

/// The episode under way and the newest ones, a tap away: one on the small widget, three on
/// the medium. Everything comes from the snapshot the app keeps in the App Group; a tap opens
/// the app and plays that episode. Copied from the books app's Continue Listening widget.
struct UpNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "audio.own.podcastplayer.upnext", provider: Provider()) { entry in
            UpNextView(entry: entry)
                .containerBackground(for: .widget) { Color(light: 0xF7F7F8, dark: 0x0C0C0E) }
        }
        .configurationDisplayName("Up Next")
        .description("The episode you are in and the newest ones, a tap away.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let episodes: [WidgetSnapshot.Entry]
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, episodes: [.init(id: "placeholder", title: "Episode 42", show: "A Podcast", fraction: 0.4, remainingMs: 30 * 60_000, cover: nil)])
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now, episodes: WidgetSnapshot.load()?.entries ?? placeholder(in: context).episodes))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // The app reloads the timeline itself when something changes; nothing to schedule.
        completion(Timeline(entries: [Entry(date: .now, episodes: WidgetSnapshot.load()?.entries ?? [])], policy: .never))
    }
}

let accent = Color(light: 0x0A6E9C, dark: 0x29ABE2)
private let muted = Color(light: 0x6E6E73, dark: 0x98989D)

struct UpNextView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        if entry.episodes.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "mic").font(.title2).foregroundStyle(accent)
                Text("Nothing new yet").font(.caption).foregroundStyle(muted).multilineTextAlignment(.center)
            }
        } else if family == .systemSmall, let episode = entry.episodes.first {
            small(episode).widgetURL(WidgetSnapshot.playURL(for: episode.id))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(entry.episodes.prefix(3)) { episode in
                    Link(destination: WidgetSnapshot.playURL(for: episode.id) ?? URL(string: "\(WidgetSnapshot.scheme)://")!) { row(episode) }
                }
            }
        }
    }

    private func small(_ episode: WidgetSnapshot.Entry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            cover(episode, size: 56)
            Spacer(minLength: 0)
            Text(episode.title).font(.caption.weight(.semibold)).lineLimit(2)
            bar(episode)
            Text(remaining(episode)).font(.caption2).foregroundStyle(muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func row(_ episode: WidgetSnapshot.Entry) -> some View {
        HStack(spacing: 10) {
            cover(episode, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(episode.title).font(.caption.weight(.semibold)).lineLimit(1)
                if !episode.show.isEmpty { Text(episode.show).font(.caption2).foregroundStyle(muted).lineLimit(1) }
                bar(episode)
            }
            Spacer(minLength: 0)
            Text(remaining(episode)).font(.caption2).foregroundStyle(muted)
        }
    }

    @ViewBuilder
    private func cover(_ episode: WidgetSnapshot.Entry, size: CGFloat) -> some View {
        if let data = episode.cover, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill().frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8).fill(accent.opacity(0.15)).frame(width: size, height: size)
                .overlay { Image(systemName: "mic").foregroundStyle(accent) }
        }
    }

    private func bar(_ episode: WidgetSnapshot.Entry) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(accent.opacity(0.2))
                Capsule().fill(accent).frame(width: max(geometry.size.width * episode.fraction, 3))
            }
        }
        .frame(height: 4)
    }

    private func remaining(_ episode: WidgetSnapshot.Entry) -> String {
        let minutes = Int((Double(episode.remainingMs) / 60_000).rounded())
        let text = minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
        return String(localized: "\(text) left")
    }
}

extension Color {
    /// One colour for each appearance, as the app's theme has them.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}
