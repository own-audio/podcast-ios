import PodcastLibrary
import SwiftUI

/// First run: find a show or add a server. After that four tabs — New Episodes, Shows,
/// Downloads, Search — with the mini player above the tab bar and the full player as a cover.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var isShowingPlayer = false
    @State private var tab: AppTab = .inbox

    private enum AppTab: Hashable { case inbox, shows, downloads, search }

    var body: some View {
        Group {
            if !model.hasLoaded {
                ProgressView()
            } else if model.isEmpty {
                OnboardingView()
            } else {
                tabs
            }
        }
        .task { await model.load() }
        .onChange(of: scenePhase) { _, phase in model.setForeground(phase == .active) }
        .onOpenURL { url in
            Task {
                if !model.hasLoaded { await model.load() }
                await model.open(url)
            }
        }
        .sheet(isPresented: Binding(get: { model.pendingFeedAddress != nil && model.hasLoaded }, set: { if !$0 { model.pendingFeedAddress = nil } })) {
            AddFeedView(address: model.pendingFeedAddress ?? "")
        }
        .fullScreenCover(isPresented: $isShowingPlayer) { PlayerView() }
        .alert("That Didn't Work", isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.actionError ?? "")
        }
        .confirmationDialog(
            "Continue from another device?",
            isPresented: Binding(get: { model.pendingResume != nil }, set: { if !$0 { model.pendingResume = nil } }),
            titleVisibility: .visible,
            presenting: model.pendingResume
        ) { pending in
            Button("Continue from \(ProgressText.clock(pending.otherMs))") {
                model.pendingResume = nil
                Task { await model.play(pending.episode, startAt: pending.otherMs) }
            }
            .accessibilityIdentifier("resume.other")
            Button("Keep this iPhone's position (\(ProgressText.clock(pending.localMs)))") {
                model.pendingResume = nil
                Task { await model.play(pending.episode, startAt: pending.localMs) }
            }
            .accessibilityIdentifier("resume.local")
        } message: { pending in
            Text("Another device got to \(ProgressText.clock(pending.otherMs)); this iPhone was at \(ProgressText.clock(pending.localMs)).")
        }
        .onChange(of: model.engine.errorMessage) { _, message in
            if let message, !isShowingPlayer { model.actionError = message }
        }
    }

    /// On iPad the tabs become a sidebar that can be shown or hidden; the iPhone keeps its tab bar.
    @ViewBuilder
    private var tabs: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            tabView.tabViewStyle(.sidebarAdaptable)
        } else {
            tabView
        }
    }

    private var tabView: some View {
        TabView(selection: $tab) {
            Tab("New Episodes", systemImage: "tray", value: AppTab.inbox) {
                NavigationStack { InboxView().appDestinations() }
                    .miniPlayerInset { isShowingPlayer = true }
            }
            .accessibilityIdentifier("tab.inbox")
            Tab("Shows", systemImage: "square.grid.2x2", value: AppTab.shows) {
                NavigationStack { ShowsView().appDestinations() }
                    .miniPlayerInset { isShowingPlayer = true }
            }
            .accessibilityIdentifier("tab.shows")
            Tab("Downloads", systemImage: "arrow.down.circle", value: AppTab.downloads) {
                NavigationStack { DownloadsView().appDestinations() }
                    .miniPlayerInset { isShowingPlayer = true }
            }
            .accessibilityIdentifier("tab.downloads")
            Tab("Discover", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                NavigationStack { SearchView().appDestinations() }
                    .miniPlayerInset { isShowingPlayer = true }
            }
            .accessibilityIdentifier("tab.search")
        }
    }
}

extension View {
    /// Where every list's rows lead: a show, an episode, a search result.
    func appDestinations() -> some View {
        navigationDestination(for: SourcedShow.self) { ShowView(show: $0) }
            .navigationDestination(for: SourcedEpisode.self) { EpisodeView(item: $0) }
            .navigationDestination(for: ShowSearchResult.self) { SearchResultView(result: $0) }
            .navigationDestination(for: CatalogueCategory.self) { CategoryView(category: $0) }
    }

    fileprivate func miniPlayerInset(onTap: @escaping () -> Void) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            MiniPlayerBar(onTap: onTap)
        }
    }
}
