import FeedKit
import PodcastLibrary
import SwiftUI

/// Every show followed, grouped by where it comes from.
struct ShowsView: View {
    @Environment(AppModel.self) private var model
    @State private var isAdding = false
    /// Remembered between launches.
    @AppStorage("shows.sort") private var sort: ShowSort = .title

    enum ShowSort: String, CaseIterable {
        case title, newEpisodes, recentlyFollowed
    }

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: Theme.Spacing.md)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                ForEach(groups, id: \.source) { group in
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        if groups.count > 1 || group.source != .phone {
                            SourceLabel(source: group.source).font(.subheadline)
                        }
                        if model.unreachable.contains(group.source) {
                            Label("Can't be reached right now", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.muted)
                        }
                        LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.lg) {
                            ForEach(group.shows) { show in
                                NavigationLink(value: show) {
                                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                        GeometryReader { geometry in
                                            ArtworkView(url: show.show.imageURL, size: geometry.size.width, radius: Theme.Radius.cover)
                                        }
                                        .aspectRatio(1, contentMode: .fit)
                                        Text(Mojibake.repair(show.show.title))
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(Theme.Colors.foreground)
                                            // Two lines always, so a row of tiles lines up at the top.
                                            .lineLimit(2, reservesSpace: true)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("show.\(show.show.title)")
                            }
                        }
                    }
                }
            }
            .padding(Theme.Spacing.screenEdge)
        }
        .overlay {
            if model.visibleShows.isEmpty {
                ContentUnavailableView {
                    Label("No Shows", systemImage: "square.stack")
                } description: {
                    Text("Follow a show by searching for it or by its feed address.")
                } actions: {
                    Button("Add a Show") { isAdding = true }.buttonStyle(.borderedProminent)
                }
            }
        }
        .refreshable { await model.refresh() }
        .navigationTitle("Shows")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isAdding = true } label: { Label("Add a Show", systemImage: "plus") }
                    .accessibilityIdentifier("shows.add")
            }
            ToolbarItem(placement: .secondaryAction) {
                Picker("Sort", selection: $sort) {
                    Text("Title").tag(ShowSort.title)
                    Text("New Episodes First").tag(ShowSort.newEpisodes)
                    Text("Recently Followed").tag(ShowSort.recentlyFollowed)
                }
                .accessibilityIdentifier("shows.sort")
            }
        }
        .sheet(isPresented: $isAdding) { AddFeedView() }
    }

    private var groups: [(source: SourceRef, shows: [SourcedShow])] {
        var order: [SourceRef] = []
        var bySource: [SourceRef: [SourcedShow]] = [:]
        for show in model.visibleShows {
            if bySource[show.source] == nil { order.append(show.source) }
            bySource[show.source, default: []].append(show)
        }
        // In the switch's order: own.audio first, then this iPhone, then the other servers.
        let rank = Dictionary(uniqueKeysWithValues: model.switchableSources.enumerated().map { ($1, $0) })
        return order.sorted { (rank[$0] ?? .max) < (rank[$1] ?? .max) }.map { ($0, sorted(bySource[$0] ?? [])) }
    }

    private func sorted(_ shows: [SourcedShow]) -> [SourcedShow] {
        let byTitle = { (a: SourcedShow, b: SourcedShow) in a.show.title.localizedStandardCompare(b.show.title) == .orderedAscending }
        switch sort {
        case .title:
            return shows.sorted(by: byTitle)
        case .recentlyFollowed:
            return shows.sorted { $0.show.followedAt > $1.show.followedAt }
        case .newEpisodes:
            // The newest unplayed episode of each show, from New Episodes; the rest by title.
            var newest: [String: Date] = [:]
            for item in model.inbox {
                let key = item.source.id + "/" + item.episode.showId
                let date = item.episode.publishedAt ?? item.episode.firstSeenAt
                if date > newest[key] ?? .distantPast { newest[key] = date }
            }
            return shows.sorted { a, b in
                switch (newest[a.id], newest[b.id]) {
                case let (x?, y?): x > y
                case (_?, nil): true
                case (nil, _?): false
                default: byTitle(a, b)
                }
            }
        }
    }
}

/// One show: about it, its episodes, and what the listener chose for it.
struct ShowView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let show: SourcedShow
    @State private var episodes: [SourcedEpisode]?
    @State private var failed = false
    @State private var filter: EpisodeFilter = .all

    enum EpisodeFilter: Hashable { case all, unplayed, downloaded }

    private var shownEpisodes: [SourcedEpisode] {
        let all = episodes ?? []
        switch filter {
        case .all: return all
        case .unplayed: return all.filter { model.progress(of: $0)?.played != true }
        case .downloaded: return all.filter { model.downloadState($0) != nil }
        }
    }
    @State private var isShowingSettings = false
    @State private var confirmUnfollow = false

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    ArtworkView(url: show.show.imageURL, size: 112, radius: Theme.Radius.cover)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(Mojibake.repair(show.show.title)).font(.title3.bold()).accessibilityIdentifier("show.title")
                        if let author = show.show.author { Text(Mojibake.repair(author)).font(.subheadline).foregroundStyle(Theme.Colors.muted) }
                        SourceLabel(source: show.source)
                    }
                }
                if let about = show.show.description, !about.isEmpty {
                    Text(linkedText(Mojibake.repair(about))).font(.footnote).foregroundStyle(Theme.Colors.muted).lineLimit(6)
                }
            }
            .listRowSeparator(.hidden)
            Section {
                if episodes != nil {
                    Picker("Episodes", selection: $filter) {
                        Text("All").tag(EpisodeFilter.all)
                        Text("Unplayed").tag(EpisodeFilter.unplayed)
                        Text("Downloaded").tag(EpisodeFilter.downloaded)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("show.filter")
                    .listRowSeparator(.hidden)
                    ForEach(shownEpisodes) { item in
                        EpisodeRow(item: item, showsShowTitle: false)
                    }
                } else if failed {
                    Text("The episodes can't be loaded right now.").foregroundStyle(Theme.Colors.muted)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            if let feed = show.show.feedURL {
                SimilarShowsSection(feedURL: feed)
            }
        }
        .listStyle(.plain)
        .refreshable {
            await model.refresh(show)
            await load()
        }
        .task { await load() }
        .navigationTitle(Mojibake.repair(show.show.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { isShowingSettings = true } label: { Label("Show Settings", systemImage: "slider.horizontal.3") }
                        .accessibilityIdentifier("show.settings")
                    if let link = show.show.link {
                        Link(destination: link) { Label("Website", systemImage: "safari") }
                    }
                    if let feed = show.show.feedURL {
                        ShareLink(item: feed) { Label("Share Feed", systemImage: "square.and.arrow.up") }
                    }
                    // Neither own.audio nor Audiobookshelf lets a player unfollow yet; on
                    // Audiobookshelf it would delete the show for everyone on the server.
                    if show.source == .phone {
                        Button(role: .destructive) { confirmUnfollow = true } label: { Label("Unfollow", systemImage: "minus.circle") }
                            .accessibilityIdentifier("show.unfollow")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("show.menu")
            }
        }
        .sheet(isPresented: $isShowingSettings) { ShowSettingsView(show: show) }
        .confirmationDialog("Unfollow \(Mojibake.repair(show.show.title))?", isPresented: $confirmUnfollow, titleVisibility: .visible) {
            Button("Unfollow", role: .destructive) {
                Task {
                    await model.unfollow(show)
                    dismiss()
                }
            }
            .accessibilityIdentifier("show.unfollow.confirm")
        } message: {
            Text("Its episodes and positions on this source are removed.")
        }
    }

    private func load() async {
        do {
            episodes = try await model.episodes(of: show)
            failed = false
        } catch {
            failed = episodes == nil
        }
    }
}

/// What the listener chose for one show: New Episodes, a start offset, a speed of its own.
struct ShowSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let show: SourcedShow
    @State private var settings: ShowSettings

    init(show: SourcedShow) {
        self.show = show
        _settings = State(initialValue: show.show.settings)
    }

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Show in New Episodes", isOn: $settings.inInbox).accessibilityIdentifier("showSettings.inbox")
                Toggle("Add New Episodes to Up Next", isOn: $settings.autoQueue).accessibilityIdentifier("showSettings.autoQueue")
                Picker("Skip the Intro", selection: $settings.skipIntroSecs) {
                    Text("Off").tag(0.0)
                    ForEach([10.0, 15, 20, 30, 45, 60, 90, 120], id: \.self) { secs in
                        Text("\(Int(secs)) s").tag(secs)
                    }
                }
                Picker("Speed", selection: Binding(get: { settings.speed ?? 0 }, set: { settings.speed = $0 == 0 ? nil : $0 })) {
                    Text("As in Settings").tag(Float(0))
                    ForEach([0.75, 1.0, 1.25, 1.5, 1.75, 2.0] as [Float], id: \.self) { rate in
                        Text(rate.speedText).tag(rate)
                    }
                }
                Section {
                    Picker("Download New Episodes", selection: $settings.autoDownload) {
                        ForEach(ShowSettings.autoDownloadChoices, id: \.self) { count in
                            if count == 0 { Text("Off").tag(0) } else { Text("Newest \(count)").tag(count) }
                        }
                    }
                    .accessibilityIdentifier("showSettings.autoDownload")
                    Toggle("Delete When Played", isOn: $settings.deleteWhenPlayed)
                        .accessibilityIdentifier("showSettings.deleteWhenPlayed")
                    Picker("Keep at Most", selection: $settings.keepAtMost) {
                        ForEach(ShowSettings.keepAtMostChoices, id: \.self) { limit in
                            if let limit { Text("\(limit) Episodes").tag(Int?.some(limit)) } else { Text("No Limit").tag(Int?.none) }
                        }
                    }
                    .accessibilityIdentifier("showSettings.keepAtMost")
                } header: {
                    Text("Downloads")
                } footer: {
                    Text("New episodes download on their own, the newest first; unplayed ones only. Settings decides whether this waits for Wi-Fi.")
                }
            }
            .navigationTitle("Show Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Task {
                            await model.updateSettings(settings, for: show)
                            dismiss()
                        }
                    }
                    .accessibilityIdentifier("showSettings.done")
                }
            }
        }
    }
}

/// Follow a show by its feed's address, on this iPhone or on a server that takes one.
struct AddFeedView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var address: String

    /// `address` filled in when a `feed://` or `podcast://` link opened the app.
    init(address: String = "") {
        _address = State(initialValue: address)
    }
    @State private var target: SourceRef = .phone
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com/feed.xml", text: $address)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("addFeed.address")
                } header: {
                    Text("Feed Address")
                } footer: {
                    Text("The RSS address a show publishes. To find a show by name, use Discover.")
                }
                if model.followTargets.count > 1 {
                    Picker("Follow On", selection: $target) {
                        ForEach(model.followTargets, id: \.self) { ref in
                            Text(model.sourceName(ref)).tag(ref)
                        }
                    }
                }
                if let error {
                    Text(error).foregroundStyle(Theme.Colors.error).accessibilityIdentifier("addFeed.error")
                }
            }
            .navigationTitle("Add a Show")
            // The source on the switch, when it takes new shows.
            .onAppear { if let active = model.activeSource, model.followTargets.contains(active) { target = active } }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Button("Follow") { Task { await follow() } }
                            .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityIdentifier("addFeed.follow")
                    }
                }
            }
        }
    }

    private func follow() async {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        // Links shared from other apps: feed://, podcast://, or no scheme at all.
        for scheme in ["feed://", "podcast://", "pcast://"] where text.lowercased().hasPrefix(scheme) {
            text = "https://" + text.dropFirst(scheme.count)
        }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), url.host() != nil else {
            error = String(localized: "That address is not a podcast feed.")
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            try await model.follow(url, into: target)
            dismiss()
        } catch {
            self.error = AppModel.message(for: error)
        }
    }
}
