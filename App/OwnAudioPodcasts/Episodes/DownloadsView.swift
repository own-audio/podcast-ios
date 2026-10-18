import FeedKit
import PodcastLibrary
import SwiftUI

/// What is on this iPhone, from every source, each row saying where it came from: newest
/// download first, grouped by source when there is more than one, to open, play or remove;
/// failed downloads can be tried again together. Laid out as the books app's.
struct DownloadsView: View {
    @Environment(AppModel.self) private var model
    @State private var isConfirmingRemoveAll = false

    private var entries: [DownloadManager.DownloadedEpisode] {
        model.downloads.episodes.values.sorted { ($0.finishedAt ?? $0.startedAt) > ($1.finishedAt ?? $1.startedAt) }
    }

    /// By source, this iPhone first and then the servers in their order; one unnamed group
    /// while everything comes from one source.
    private var groups: [(name: String?, entries: [DownloadManager.DownloadedEpisode])] {
        let bySource = Dictionary(grouping: entries) { $0.sourceRef?.serverId?.uuidString ?? "phone" }
        guard bySource.count > 1 else { return [(nil, entries)] }
        var out: [(String?, [DownloadManager.DownloadedEpisode])] = []
        if let phone = bySource["phone"] { out.append((model.sourceName(.phone), phone)) }
        for server in model.serversInOrder { if let found = bySource[server.id.uuidString] { out.append((server.displayName, found)) } }
        let known = Set(["phone"] + model.servers.map(\.id.uuidString))
        for (key, found) in bySource where !known.contains(key) { out.append((String(localized: "Removed server"), found)) }
        return out
    }

    private var failed: [String] {
        model.downloads.episodes.keys.filter { if case .failed = model.downloads.state(of: $0) { true } else { false } }
    }

    private var downloadingCount: Int {
        model.downloads.episodes.keys.filter { if case .downloading = model.downloads.state(of: $0) { true } else { false } }.count
    }

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label("Nothing Downloaded", systemImage: "arrow.down.circle")
                } description: {
                    Text("Episodes you download appear here, with the source each came from, and play with no network.")
                }
                .accessibilityIdentifier("downloads.empty")
            }
            if downloadingCount > 0 || !failed.isEmpty {
                Section {
                    if downloadingCount > 0 { LabeledContent("Downloading", value: "\(downloadingCount)") }
                    if !failed.isEmpty {
                        Button("Retry \(failed.count) Failed") { for id in failed { model.downloads.retry(id) } }
                            .accessibilityIdentifier("downloads.retryFailed")
                    }
                }
            }
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                Section {
                    ForEach(group.entries) { entry in row(entry) }
                } header: {
                    if let name = group.name { Text(name) }
                }
            }
            if !entries.isEmpty {
                Section {
                    Button("Remove All Downloads", role: .destructive) { isConfirmingRemoveAll = true }
                        .accessibilityIdentifier("downloads.removeAll")
                } footer: {
                    Text("\(ByteCountFormatter.string(fromByteCount: model.downloads.totalBytes, countStyle: .file)) on this iPhone.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Downloads")
        .confirmationDialog("Remove All Downloads?", isPresented: $isConfirmingRemoveAll, titleVisibility: .visible) {
            Button("Remove All Downloads", role: .destructive) { model.downloads.removeAll() }
                .accessibilityIdentifier("downloads.removeAll.confirm")
        }
    }

    @ViewBuilder
    private func row(_ entry: DownloadManager.DownloadedEpisode) -> some View {
        if let item = entry.item {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                NavigationLink(value: item) {
                    HStack(alignment: .top, spacing: Theme.Spacing.md) {
                        ArtworkView(url: entry.episode.imageURL ?? entry.show?.imageURL, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            if let show = entry.show {
                                Text(Mojibake.repair(show.title)).font(.caption).foregroundStyle(Theme.Colors.muted).lineLimit(1)
                            }
                            Text(Mojibake.repair(entry.episode.title)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.Colors.foreground).lineLimit(2)
                            // Which source it came from: with several, the same show can be on more than one.
                            DownloadSourceLabel(entry: entry)
                            Text(status(entry)).font(.caption).foregroundStyle(Theme.Colors.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("downloads.\(entry.episode.id)")
                PlayButton(item: item)
            }
            .swipeActions {
                Button(role: .destructive) { model.removeDownload(item) } label: { Label("Remove", systemImage: "trash") }
            }
        }
    }

    private func status(_ entry: DownloadManager.DownloadedEpisode) -> String {
        switch model.downloads.state(of: entry.id) {
        case .downloading(let fraction): String(localized: "Downloading… \(Int(fraction * 100))%")
        case .failed(let message): message
        case .downloaded, nil: ByteCountFormatter.string(fromByteCount: entry.bytes, countStyle: .file)
        }
    }
}

/// "This iPhone", a server's name, or "Removed server" once the server is gone.
struct DownloadSourceLabel: View {
    @Environment(AppModel.self) private var model
    let entry: DownloadManager.DownloadedEpisode

    var body: some View {
        let ref = entry.sourceRef
        let known = ref.map { $0 == .phone || $0.serverId.map { id in model.servers.contains { $0.id == id } } == true } ?? false
        HStack(spacing: 4) {
            Image(systemName: ref == .phone ? "iphone" : "server.rack").imageScale(.small).accessibilityHidden(true)
            Text(known ? model.sourceName(ref!) : String(localized: "Removed server"))
        }
        .font(.caption)
        .foregroundStyle(Theme.Colors.muted)
        .lineLimit(1)
        .accessibilityIdentifier("downloads.source.\(entry.episode.id)")
    }
}
