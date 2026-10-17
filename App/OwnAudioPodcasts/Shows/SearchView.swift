import PodcastLibrary
import SwiftUI

/// Finds shows by name through Apple's podcast directory, and follows one.
struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var term = ""
    @State private var results: [ShowSearchResult] = []
    @State private var state: SearchState = .idle

    private enum SearchState: Equatable { case idle, searching, done, failed }

    var body: some View {
        List(results) { result in
            NavigationLink(value: result) {
                HStack(spacing: Theme.Spacing.md) {
                    ArtworkView(url: result.imageURL, size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                        if let author = result.author { Text(author).font(.caption).foregroundStyle(Theme.Colors.muted).lineLimit(1) }
                    }
                }
            }
            .accessibilityIdentifier("search.result.\(result.title)")
        }
        .listStyle(.plain)
        .overlay {
            switch state {
            case .idle where results.isEmpty:
                ContentUnavailableView("Search for Shows", systemImage: "magnifyingglass", description: Text("Find a show by its name or its host."))
            case .searching where results.isEmpty:
                ProgressView()
            case .done where results.isEmpty:
                ContentUnavailableView.search(text: term)
            case .failed:
                ContentUnavailableView("Search Isn't Available", systemImage: "wifi.slash", description: Text("Searching needs the network."))
            default:
                EmptyView()
            }
        }
        .navigationTitle("Search")
        .searchable(text: $term, prompt: "Shows")
        .onSubmit(of: .search) { Task { await search() } }
        .task(id: term) {
            // Results as the listener types, after a pause.
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    private func search() async {
        let query = term.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            results = []
            state = .idle
            return
        }
        guard !model.isOffline else {
            state = .failed
            return
        }
        state = .searching
        do {
            let found = try await model.search(query)
            guard query == term.trimmingCharacters(in: .whitespaces) else { return }
            results = found
            state = .done
        } catch {
            state = .failed
        }
    }
}

/// A show found by searching: about it, and the button that follows it.
struct SearchResultView: View {
    @Environment(AppModel.self) private var model
    let result: ShowSearchResult
    @State private var target: SourceRef = .phone
    @State private var isWorking = false
    @State private var followed: SourcedShow?
    @State private var error: String?

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    ArtworkView(url: result.imageURL, size: 112, radius: Theme.Radius.cover)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(result.title).font(.title3.bold())
                        if let author = result.author { Text(author).font(.subheadline).foregroundStyle(Theme.Colors.muted) }
                        if let genre = result.genre { Text(genre).font(.caption).foregroundStyle(Theme.Colors.muted) }
                    }
                }
            }
            .listRowSeparator(.hidden)
            Section {
                if model.followTargets.count > 1 {
                    Picker("Follow On", selection: $target) {
                        ForEach(model.followTargets, id: \.self) { ref in Text(model.sourceName(ref)).tag(ref) }
                    }
                }
                if let followed {
                    NavigationLink(value: followed) { Label("Following — Open the Show", systemImage: "checkmark.circle.fill") }
                        .accessibilityIdentifier("search.open")
                } else if let existing {
                    NavigationLink(value: existing) { Label("Following — Open the Show", systemImage: "checkmark.circle.fill") }
                        .accessibilityIdentifier("search.open")
                } else {
                    Button {
                        Task { await follow() }
                    } label: {
                        HStack {
                            Label("Follow", systemImage: "plus.circle.fill")
                            if isWorking { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isWorking)
                    .accessibilityIdentifier("search.follow")
                }
                if let error { Text(error).foregroundStyle(Theme.Colors.error) }
            }
        }
        .navigationTitle(result.title)
            // The source on the switch, when it takes new shows.
            .onAppear { if let active = model.activeSource, model.followTargets.contains(active) { target = active } }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var existing: SourcedShow? {
        model.shows.first { $0.show.feedURL == result.feedURL }
    }

    private func follow() async {
        isWorking = true
        defer { isWorking = false }
        do {
            followed = try await model.follow(result.feedURL, into: target)
        } catch {
            self.error = AppModel.message(for: error)
        }
    }
}
