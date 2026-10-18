import FeedKit
import OwnAudioKit
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
            ForEach(model.visibleInbox) { item in
                EpisodeRow(item: item, inInbox: true)
            }
        }
        .listStyle(.plain)
        .overlay {
            if model.visibleInbox.isEmpty {
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
            if model.switchableSources.count > 1 {
                ToolbarItem(placement: .topBarLeading) { SourceMenu() }
            }
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
                EpisodeSummarySection(item: item)
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

/// A summary of the episode and answers to questions about it, made by an own.audio server
/// from the episode's transcript and paid from the family's credit. Shown only where the server
/// offers it and the episode has a transcript.
struct EpisodeSummarySection: View {
    @Environment(AppModel.self) private var model
    let item: SourcedEpisode
    @State private var available = false
    @State private var checked = false
    @State private var length: SummaryLength = .medium
    @State private var summary: EpisodeSummary?
    @State private var working = false
    @State private var error: String?
    @State private var question = ""
    @State private var turns: [EpisodeAnswer] = []
    @State private var isConfirmingClear = false
    @State private var asking = false

    var body: some View {
        Group {
            if available {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Summary").font(.headline)
                    Picker("Summary Length", selection: $length) {
                        Text("Short").tag(SummaryLength.short)
                        Text("Medium").tag(SummaryLength.medium)
                        Text("Long").tag(SummaryLength.long)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("episode.summaryLength")
                    if let summary {
                        Text(summary.text)
                            .foregroundStyle(Theme.Colors.foreground)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("episode.summary")
                        price(summary.chargedMicro ?? 0)
                    } else if checked {
                        Text("A summary is made from the transcript with AI and paid from your family's credit, usually a cent or two. Everyone in the family can then read it.")
                            .font(.footnote)
                            .foregroundStyle(Theme.Colors.muted)
                        Button {
                            Task { await make() }
                        } label: {
                            Label(working ? "Summarizing…" : "Summarize Episode", systemImage: "sparkles")
                                .frame(maxWidth: .infinity, minHeight: Theme.minTarget)
                        }
                        .buttonStyle(.bordered)
                        .disabled(working)
                        .accessibilityIdentifier("episode.summarize")
                    }
                    if checked {
                        ForEach(turns) { turn in
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Text(turn.question).font(.subheadline.bold()).foregroundStyle(Theme.Colors.foreground)
                                Text(turn.answer).foregroundStyle(Theme.Colors.muted).textSelection(.enabled)
                                price(turn.chargedMicro)
                            }
                        }
                        HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
                            TextField("Ask about this episode", text: $question, axis: .vertical)
                                .lineLimit(1...4)
                                .textFieldStyle(.roundedBorder)
                                .submitLabel(.send)
                                .onSubmit { Task { await ask() } }
                                .accessibilityIdentifier("episode.question")
                            Button {
                                Task { await ask() }
                            } label: {
                                if asking { ProgressView() } else { Text("Ask") }
                            }
                            .buttonStyle(.bordered)
                            .disabled(asking || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("episode.ask")
                        }
                        Text("Answers come from the episode's transcript only, and each one is paid from your family's credit. Your questions are kept for you alone.")
                            .font(.footnote)
                            .foregroundStyle(Theme.Colors.muted)
                        if !turns.isEmpty {
                            Button("Clear Questions", role: .destructive) { isConfirmingClear = true }
                                .font(.footnote)
                                .accessibilityIdentifier("episode.clearQuestions")
                                .confirmationDialog("Delete your questions and answers for this episode?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
                                    Button("Clear Questions", role: .destructive) { Task { await clear() } }
                                }
                        }
                    }
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(Theme.Colors.error).accessibilityIdentifier("episode.summaryError")
                    }
                }
            }
        }
        .task(id: item.id) {
            guard await model.offersSummaries(item) else { return }
            turns = (try? await model.questions(item)) ?? []
        }
        .task(id: "\(item.id)-\(length.rawValue)") {
            available = await model.offersSummaries(item)
            guard available else { return }
            error = nil
            summary = try? await model.summary(item, length: length)
            checked = true
        }
    }

    private func clear() async {
        error = nil
        do {
            try await model.clearQuestions(item)
            turns = []
        } catch {
            self.error = AppModel.summaryMessage(for: error)
        }
    }

    @ViewBuilder private func price(_ micro: Int64) -> some View {
        if micro > 0 {
            Text("Cost \(AppModel.price(micro: micro))").font(.caption).foregroundStyle(Theme.Colors.muted)
        }
    }

    private func make() async {
        working = true
        defer { working = false }
        error = nil
        do {
            let asked = length
            let made = try await model.summarize(item, length: asked)
            // The listener may have switched length while it was being made.
            if asked == length { summary = made }
        } catch {
            self.error = AppModel.summaryMessage(for: error)
        }
    }

    private func ask() async {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !asking else { return }
        asking = true
        defer { asking = false }
        error = nil
        do {
            turns.append(try await model.ask(item, question: text))
            question = ""
        } catch {
            self.error = AppModel.summaryMessage(for: error)
        }
    }
}

/// With more than one source, which one New Episodes and Shows show is a tap away — all of them
/// together, this iPhone's own shows, or one server's — as the books and music apps switch
/// servers on Home.
struct SourceMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        @Bindable var model = model
        Menu {
            Picker("Source", selection: $model.activeSource) {
                Label("All Sources", systemImage: "square.stack.3d.up").tag(SourceRef?.none)
                ForEach(model.switchableSources, id: \.self) { ref in
                    Label {
                        Text(model.sourceName(ref))
                    } icon: {
                        model.brand(ref).menuIcon(dark: colorScheme == .dark, image: model.icon(ref))
                    }
                    .tag(SourceRef?.some(ref))
                }
            }
        } label: {
            // As in the music app: the server symbol, the name read out.
            Label(model.activeSource.map { model.sourceName($0) } ?? String(localized: "All Sources"), systemImage: "server.rack")
        }
        .accessibilityIdentifier("home.serverMenu")
    }
}
