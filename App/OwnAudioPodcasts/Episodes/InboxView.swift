import FeedKit
import PodcastLibrary
import SwiftUI

/// The first tab: unplayed episodes that came out since each show was followed, from every
/// source, newest first. Offline Mode and Settings sit in its toolbar, as in the other apps.
struct InboxView: View {
    @Environment(AppModel.self) private var model
    @State private var isShowingSettings = false

    var body: some View {
        List {
            if model.isOffline {
                Label(model.isOfflineByChoice ? "Offline Mode is on" : "No network", systemImage: "wifi.slash")
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.muted)
                    .listRowSeparator(.hidden)
            }
            ForEach(model.inbox) { item in
                EpisodeRow(item: item, inInbox: true)
            }
        }
        .listStyle(.plain)
        .overlay {
            if model.inbox.isEmpty {
                ContentUnavailableView {
                    Label("No New Episodes", systemImage: "tray")
                } description: {
                    Text("New episodes of the shows you follow appear here.")
                }
                .accessibilityIdentifier("inbox.empty")
            }
        }
        .refreshable { await model.refresh() }
        .navigationTitle("New Episodes")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Toggle(isOn: Binding(get: { model.settings.offlineMode }, set: { model.setOfflineMode($0) })) {
                    Label("Offline Mode", systemImage: model.settings.offlineMode ? "wifi.slash" : "wifi")
                }
                .toggleStyle(.button)
                .accessibilityIdentifier("home.offlineMode")
                Button { isShowingSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                    .accessibilityIdentifier("home.settings")
            }
        }
        .sheet(isPresented: $isShowingSettings) { SettingsView() }
    }
}

/// One episode: what it is, the play button, the notes with their links, and its chapters.
struct EpisodeView: View {
    @Environment(AppModel.self) private var model
    let item: SourcedEpisode

    var body: some View {
        let episode = item.episode
        let show = model.show(for: item)
        let progress = model.progress(of: item)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    ArtworkView(url: episode.imageURL ?? show?.imageURL, size: 96, radius: Theme.Radius.cover)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        if let show {
                            Text(Mojibake.repair(show.title)).font(.subheadline).foregroundStyle(Theme.Colors.muted)
                        }
                        Text(Mojibake.repair(episode.title))
                            .font(.title3.bold())
                            .foregroundStyle(Theme.Colors.foreground)
                            .accessibilityIdentifier("episode.title")
                        Text(ProgressText.line(episode: episode, progress: progress))
                            .font(.footnote)
                            .foregroundStyle(Theme.Colors.muted)
                        SourceLabel(source: item.source)
                    }
                }
                HStack(spacing: Theme.Spacing.md) {
                    Button {
                        Task { await model.play(item) }
                    } label: {
                        Label(progress.map { !$0.played && $0.positionMs > 0 } == true ? "Resume" : "Play", systemImage: "play.fill")
                            .frame(maxWidth: .infinity, minHeight: Theme.minTarget)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("episode.play")
                    Button {
                        Task { await model.markPlayed(item, progress?.played != true) }
                    } label: {
                        Label(progress?.played == true ? "Unplayed" : "Played", systemImage: progress?.played == true ? "circle" : "checkmark.circle")
                            .frame(maxWidth: .infinity, minHeight: Theme.minTarget)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("episode.markPlayed")
                }
                if !episode.chapters.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Chapters").font(.headline)
                        ForEach(Array(episode.chapters.filter(\.isInTableOfContents).enumerated()), id: \.offset) { _, chapter in
                            Button {
                                Task {
                                    if model.nowPlaying?.id == item.id {
                                        model.engine.seek(to: chapter.startMs)
                                        if !model.engine.isPlaying { model.engine.play() }
                                    } else {
                                        await model.play(item, startAt: chapter.startMs)
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(ProgressText.clock(chapter.startMs)).font(.caption.monospacedDigit()).foregroundStyle(Theme.Colors.muted)
                                    Text(Mojibake.repair(chapter.title)).foregroundStyle(Theme.Colors.foreground).lineLimit(2)
                                    Spacer()
                                }
                                .frame(minHeight: Theme.minTarget)
                            }
                        }
                    }
                }
                if let notes = episode.description, !notes.isEmpty {
                    Text(linkedText(Mojibake.repair(notes)))
                        .font(.body)
                        .foregroundStyle(Theme.Colors.foreground)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("episode.notes")
                }
                if let link = episode.link {
                    Link(destination: link) { Label("Episode Website", systemImage: "safari") }
                }
            }
            .padding(Theme.Spacing.screenEdge)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}
