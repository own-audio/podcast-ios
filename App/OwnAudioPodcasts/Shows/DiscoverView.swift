import PodcastLibrary
import SwiftUI

/// What a category looks like: its name in the listener's language, a symbol and a colour. Fixed
/// per category, so a grid reads the same every time; a category the catalogue adds later gets
/// its own name and a neutral look.
enum CategoryStyle {
    static func name(_ key: String) -> String {
        switch key {
        case "arts": String(localized: "Arts")
        case "business": String(localized: "Business")
        case "comedy": String(localized: "Comedy")
        case "culture": String(localized: "Culture")
        case "education": String(localized: "Education")
        case "family", "kids": String(localized: "Kids & Family")
        case "fiction": String(localized: "Fiction")
        case "film", "tv": String(localized: "TV & Film")
        case "government": String(localized: "Government")
        case "health": String(localized: "Health & Fitness")
        case "history": String(localized: "History")
        case "leisure": String(localized: "Leisure")
        case "music": String(localized: "Music")
        case "news": String(localized: "News")
        case "religion", "spirituality": String(localized: "Religion & Spirituality")
        case "science": String(localized: "Science")
        case "society": String(localized: "Society")
        case "sports": String(localized: "Sports")
        case "technology": String(localized: "Technology")
        case "truecrime", "true crime": String(localized: "True Crime")
        default: key.prefix(1).uppercased() + key.dropFirst()
        }
    }

    static func symbol(_ key: String) -> String {
        switch key {
        case "arts", "culture": "theatermasks.fill"
        case "business": "briefcase.fill"
        case "comedy": "face.smiling.fill"
        case "education": "graduationcap.fill"
        case "family", "kids": "figure.2.and.child.holdinghands"
        case "fiction": "book.fill"
        case "film", "tv": "tv.fill"
        case "government": "building.columns.fill"
        case "health": "heart.fill"
        case "history": "hourglass"
        case "leisure": "gamecontroller.fill"
        case "music": "music.note"
        case "news": "newspaper.fill"
        case "religion", "spirituality": "sparkles"
        case "science": "atom"
        case "society": "person.3.fill"
        case "sports": "figure.run"
        case "technology": "cpu.fill"
        case "truecrime", "true crime": "magnifyingglass"
        default: "square.grid.2x2.fill"
        }
    }

    static func colour(_ key: String) -> Color {
        let palette: [Color] = [.indigo, .pink, .teal, .orange, .purple, .blue, .green, .red, .mint, .brown, .cyan]
        let known = ["society", "culture", "education", "business", "religion", "news", "comedy", "health", "history", "technology", "science",
                     "sports", "arts", "kids", "family", "fiction", "music", "leisure", "tv", "film", "government", "truecrime", "true crime", "spirituality"]
        let index = known.firstIndex(of: key) ?? key.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[index % palette.count]
    }
}

/// Discover before anything is typed: following by address, "More like your shows" when the
/// catalogue knows which shows are alike, and the categories to browse.
struct DiscoverHome: View {
    @Environment(AppModel.self) private var model
    @State private var categories: [CatalogueCategory]?
    @State private var isAddingFeed = false
    @State private var failed = false

    private let columns = [GridItem(.flexible(), spacing: Theme.Spacing.md), GridItem(.flexible(), spacing: Theme.Spacing.md)]

    var body: some View {
        Section {
            Button { isAddingFeed = true } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add by Address").foregroundStyle(Theme.Colors.foreground)
                        Text("A show's RSS feed").font(.caption).foregroundStyle(Theme.Colors.muted)
                    }
                } icon: {
                    Image(systemName: "link.badge.plus")
                }
            }
            .accessibilityIdentifier("discover.addByAddress")
        }
        .sheet(isPresented: $isAddingFeed) { AddFeedView() }

        if model.catalogueSuggests, !model.isOffline {
            Section {
                if let suggestions = model.suggestions {
                    if suggestions.isEmpty {
                        Text("Follow a few shows, and shows like them appear here.").font(.footnote).foregroundStyle(Theme.Colors.muted)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: Theme.Spacing.md) {
                                ForEach(suggestions) { suggestion in SuggestionCard(suggestion: suggestion) }
                            }
                            .padding(.horizontal, Theme.Spacing.screenEdge)
                        }
                        .listRowInsets(EdgeInsets())
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("More Like Your Shows")
                    Text("From the shows you follow, not from what you play.").font(.caption).textCase(nil)
                }
            }
            .listRowBackground(Color.clear)
            .accessibilityIdentifier("discover.suggestions")
            .task(id: model.catalogueServerId) { if model.suggestions == nil { await model.loadSuggestions() } }
        }

        if !model.isOffline {
            Section {
                if let categories {
                    LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                        ForEach(categories) { category in
                            NavigationLink(value: category) { CategoryTile(category: category) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("discover.category.\(category.key)")
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: Theme.Spacing.screenEdge, bottom: 0, trailing: Theme.Spacing.screenEdge))
                } else if failed {
                    Text("The categories can't be loaded right now.").foregroundStyle(Theme.Colors.muted)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Browse")
                    Text(model.catalogueSuggests
                         ? "From \(model.catalogueName)'s catalogue. Nothing you search for here leaves your own server."
                         : "Apple's top shows in each category, and Apple's search.")
                        .font(.caption).textCase(nil)
                }
            }
            .listRowBackground(Color.clear)
            .task(id: model.catalogueServerId) { await loadCategories() }
        } else {
            Section {
                Label("Discover needs the network; your own shows are found offline too.", systemImage: "wifi.slash")
                    .font(.footnote).foregroundStyle(Theme.Colors.muted)
            }
        }
    }

    private func loadCategories() async {
        categories = nil
        failed = false
        do {
            categories = try await model.showCatalogue.categories()
        } catch {
            failed = true
        }
    }
}

/// A category in the grid: its symbol, name and, where the catalogue counts them, how many
/// shows still publish in it.
struct CategoryTile: View {
    let category: CatalogueCategory

    var body: some View {
        let colour = CategoryStyle.colour(category.key)
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Image(systemName: CategoryStyle.symbol(category.key)).font(.title3).foregroundStyle(colour)
            Text(CategoryStyle.name(category.key)).font(.headline).foregroundStyle(Theme.Colors.foreground).lineLimit(2).minimumScaleFactor(0.8)
            if let count = category.showCount {
                Text("\(count.formatted()) shows").font(.caption).foregroundStyle(Theme.Colors.muted)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .padding(Theme.Spacing.md)
        .background(colour.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.cover, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A suggested show: its picture, title, and which followed show brought it up.
struct SuggestionCard: View {
    let suggestion: Suggestion

    var body: some View {
        NavigationLink(value: suggestion.show) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ArtworkView(url: suggestion.show.imageURL, size: 140, radius: Theme.Radius.cover)
                Text(suggestion.show.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.Colors.foreground).lineLimit(2)
                Text("Because you follow \(suggestion.because)").font(.caption).foregroundStyle(Theme.Colors.muted).lineLimit(2)
            }
            .frame(width: 140, alignment: .topLeading)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("suggestion.\(suggestion.show.title)")
    }
}

/// One category's shows: a page at a time from the own.audio catalogue, or Apple's chart.
struct CategoryView: View {
    @Environment(AppModel.self) private var model
    let category: CatalogueCategory
    @State private var shows: [ShowSearchResult] = []
    @State private var isLoading = false
    @State private var reachedEnd = false
    @State private var failed = false

    var body: some View {
        List {
            ForEach(shows) { show in
                ShowResultRow(result: show)
                    .onAppear { if show == shows.last { Task { await loadMore() } } }
            }
            if isLoading { ProgressView().frame(maxWidth: .infinity) }
            if failed { Text("The shows can't be loaded right now.").foregroundStyle(Theme.Colors.muted) }
        }
        .listStyle(.plain)
        .overlay {
            if shows.isEmpty, reachedEnd, !failed {
                ContentUnavailableView("Nothing Here Yet", systemImage: CategoryStyle.symbol(category.key))
            }
        }
        .navigationTitle(CategoryStyle.name(category.key))
        .task { if shows.isEmpty { await loadMore() } }
    }

    private func loadMore() async {
        guard !isLoading, !reachedEnd else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await model.showCatalogue.browse(category, offset: shows.count)
            let known = Set(shows.map(\.id))
            let new = page.filter { !known.contains($0.id) }
            shows += new
            if new.isEmpty { reachedEnd = true }
        } catch {
            failed = true
        }
    }
}

/// A show from a catalogue or a search, opening the page that follows it.
struct ShowResultRow: View {
    let result: ShowSearchResult

    var body: some View {
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
}

/// "Similar Shows" under a show: from the catalogue, without the ones already followed. Shown
/// only where the catalogue knows which shows are alike.
struct SimilarShowsSection: View {
    @Environment(AppModel.self) private var model
    let feedURL: URL
    @State private var similar: [ShowSearchResult]?

    var body: some View {
        Group {
            if let similar, !similar.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: Theme.Spacing.md) {
                            ForEach(similar) { show in
                                NavigationLink(value: show) {
                                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                        ArtworkView(url: show.imageURL, size: 112, radius: Theme.Radius.cover)
                                        Text(show.title).font(.caption.weight(.semibold)).foregroundStyle(Theme.Colors.foreground).lineLimit(2)
                                    }
                                    .frame(width: 112, alignment: .topLeading)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("similar.\(show.title)")
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.screenEdge)
                    }
                    .listRowInsets(EdgeInsets())
                } header: {
                    Text("Similar Shows")
                }
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("show.similar")
            }
        }
        .task(id: feedURL) { if model.catalogueSuggests { similar = await model.similarShows(to: feedURL) } }
    }
}
