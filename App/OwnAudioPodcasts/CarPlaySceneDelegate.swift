import CarPlay
import PodcastLibrary
import SpokenEngine
import UIKit

/// The car's screen. It runs in the same process as the phone UI and drives the same model and
/// player, so an episode started here shows on the phone and the lock screen, and the other way
/// round. Now Playing is the system's own template, with the chapters behind its Up Next button
/// and the speed on its rate button; the skip buttons come from the remote commands the player
/// already registers. Copied from the books app's `CarPlaySceneDelegate`.
///
/// Lists are short on purpose: CarPlay is for a glance and a tap. New Episodes comes first and
/// downloads next, because a car often has no signal.
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPNowPlayingTemplateObserver {
    private var interfaceController: CPInterfaceController?
    private var model: AppModel { AppModel.shared }

    private static var maxItems: Int { CarPlayContent.maxItems }
    private static let title = "own.podcast"

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        interfaceController.setRootTemplate(CPListTemplate(title: Self.title, sections: []), animated: false) { _, _ in }
        CPNowPlayingTemplate.shared.add(self)
        configureNowPlaying()
        Task {
            // CarPlay can start the app without the phone UI ever appearing.
            if !model.hasLoaded { await model.load() }
            showRoot()
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        CPNowPlayingTemplate.shared.remove(self)
        self.interfaceController = nil
    }

    // MARK: - Root

    private func showRoot() {
        let entries = CarPlayContent.rootEntries(hasShows: !model.isEmpty)
        guard !entries.isEmpty else {
            let item = CPListItem(text: String(localized: "Follow a show on your iPhone"), detailText: nil)
            item.isEnabled = false
            interfaceController?.setRootTemplate(CPListTemplate(title: Self.title, sections: [CPListSection(items: [item])]), animated: true) { _, _ in }
            return
        }
        let items = entries.map { entry -> CPListItem in
            let item = CPListItem(text: entry.title, detailText: nil, image: UIImage(systemName: entry.symbol))
            item.accessoryType = .disclosureIndicator
            item.handler = { [weak self] _, completion in
                switch entry {
                case .newEpisodes: self?.pushNewEpisodes()
                case .downloads: self?.pushDownloads()
                case .shows: self?.pushShows()
                }
                completion()
            }
            return item
        }
        interfaceController?.setRootTemplate(CPListTemplate(title: Self.title, sections: [CPListSection(items: items)]), animated: true) { _, _ in }
    }

    // MARK: - Lists

    /// Offline, only what is on the phone.
    private func pushNewEpisodes() {
        let episodes = CarPlayContent.newEpisodes(model.inbox, canPlay: model.canPlay)
        pushEpisodeList(episodes, title: String(localized: "New Episodes"), emptyText: String(localized: "No new episodes"))
    }

    /// From the download index alone, so it works with no signal.
    private func pushDownloads() {
        pushEpisodeList(CarPlayContent.downloads(Array(model.downloads.episodes.values)), title: String(localized: "Downloads"), emptyText: String(localized: "Nothing downloaded"))
    }

    private func pushShows() {
        push(title: String(localized: "Shows"), items: model.shows.prefix(Self.maxItems).map { show in
            let item = CPListItem(text: show.show.title, detailText: show.show.author)
            item.accessoryType = .disclosureIndicator
            item.handler = { [weak self] _, completion in
                Task {
                    guard let self else { completion(); return }
                    let episodes = CarPlayContent.showEpisodes((try? await self.model.episodes(of: show)) ?? [], canPlay: self.model.canPlay)
                    self.pushEpisodeList(episodes, title: show.show.title, emptyText: String(localized: "Nothing here yet"))
                    completion()
                }
            }
            loadPicture(for: item, url: show.show.imageURL)
            return item
        }, emptyText: String(localized: "No shows yet"))
    }

    private func pushEpisodeList(_ episodes: [SourcedEpisode], title: String, emptyText: String) {
        push(title: title, items: episodes.prefix(Self.maxItems).map { episode in
            let show = model.show(for: episode) ?? model.downloads.episodes[episode.id]?.show
            let item = CPListItem(text: episode.episode.title, detailText: show?.title)
            item.isPlaying = model.nowPlaying?.id == episode.id
            if let progress = CarPlayContent.progress(model.progress(of: episode), durationMs: episode.episode.durationMs) {
                item.playbackProgress = progress
            }
            item.handler = { [weak self] _, completion in
                Task {
                    await self?.play(episode)
                    completion()
                }
            }
            loadPicture(for: item, url: episode.episode.imageURL ?? show?.imageURL)
            return item
        }, emptyText: emptyText)
    }

    // MARK: - Playing

    private func play(_ episode: SourcedEpisode) async {
        await model.play(episode)
        // No question in the car: the newer position wins.
        if let pending = model.pendingResume {
            model.pendingResume = nil
            await model.play(pending.episode, startAt: pending.otherMs)
        }
        showNowPlaying()
    }

    private func configureNowPlaying() {
        let template = CPNowPlayingTemplate.shared
        let rate = CPNowPlayingPlaybackRateButton { [weak self] _ in self?.cycleRate() }
        template.updateNowPlayingButtons([rate])
        template.isUpNextButtonEnabled = true
        template.upNextTitle = String(localized: "Chapters")
    }

    nonisolated func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        Task { @MainActor in self.pushChapters() }
    }

    /// 1× → 1.25× → … → 2× → 0.75× → 1×, the steps of the phone's speed settings.
    private func cycleRate() {
        model.setRate(CarPlayContent.nextRate(after: model.engine.rate))
    }

    private func pushChapters() {
        guard let episode = model.engine.book else { return }
        let current = model.engine.currentChapter
        let items = episode.timeline.chapters.enumerated().map { index, chapter -> CPListItem in
            let item = CPListItem(text: chapter.title.isEmpty ? String(localized: "Chapter \(index + 1)") : chapter.title, detailText: ProgressText.clock(chapter.startMs))
            item.isPlaying = chapter == current
            item.handler = { [weak self] _, completion in
                guard let self else { completion(); return }
                self.model.engine.seek(to: chapter.startMs)
                if !self.model.engine.isPlaying { self.model.engine.play() }
                self.interfaceController?.popTemplate(animated: true) { _, _ in }
                completion()
            }
            return item
        }
        push(title: String(localized: "Chapters"), items: items, emptyText: String(localized: "No chapters"))
    }

    // MARK: - Helpers

    /// A tapped row should visibly start something, not leave the driver on the list.
    private func showNowPlaying() {
        guard model.nowPlaying != nil, interfaceController?.topTemplate !== CPNowPlayingTemplate.shared else { return }
        interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true) { _, _ in }
    }

    private func push(title: String, items: [CPListItem], emptyText: String) {
        interfaceController?.pushTemplate(CarPlayContent.listTemplate(title: title, items: items, emptyText: emptyText), animated: true) { _, _ in }
    }

    /// The row appears at once; its picture fills in when loaded.
    private func loadPicture(for item: CPListItem, url: URL?) {
        Task {
            if let data = await model.smallPicture(url, size: 60), let image = UIImage(data: data) { item.setImage(image) }
        }
    }
}
