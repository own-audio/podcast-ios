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

    /// CarPlay's guidelines ask for short lists; the system also caps them.
    private static let maxItems = 100
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
        guard !model.isEmpty else {
            let item = CPListItem(text: String(localized: "Follow a show on your iPhone"), detailText: nil)
            item.isEnabled = false
            interfaceController?.setRootTemplate(CPListTemplate(title: Self.title, sections: [CPListSection(items: [item])]), animated: true) { _, _ in }
            return
        }
        let entries: [(String, String, () async -> Void)] = [
            (String(localized: "New Episodes"), "tray", { [weak self] in self?.pushNewEpisodes() }),
            (String(localized: "Downloads"), "arrow.down.circle", { [weak self] in self?.pushDownloads() }),
            (String(localized: "Shows"), "square.grid.2x2", { [weak self] in self?.pushShows() }),
        ]
        let items = entries.map { text, symbol, action -> CPListItem in
            let item = CPListItem(text: text, detailText: nil, image: UIImage(systemName: symbol))
            item.accessoryType = .disclosureIndicator
            item.handler = { _, completion in
                Task {
                    await action()
                    completion()
                }
            }
            return item
        }
        interfaceController?.setRootTemplate(CPListTemplate(title: Self.title, sections: [CPListSection(items: items)]), animated: true) { _, _ in }
    }

    // MARK: - Lists

    /// Offline, only what is on the phone.
    private func pushNewEpisodes() {
        let episodes = model.inbox.filter(model.canPlay)
        pushEpisodeList(episodes, title: String(localized: "New Episodes"), emptyText: String(localized: "No new episodes"))
    }

    /// From the download index alone, so it works with no signal.
    private func pushDownloads() {
        let entries = model.downloads.episodes.values.filter(\.isComplete).sorted { ($0.finishedAt ?? $0.startedAt) > ($1.finishedAt ?? $1.startedAt) }
        pushEpisodeList(entries.compactMap(\.item), title: String(localized: "Downloads"), emptyText: String(localized: "Nothing downloaded"))
    }

    private func pushShows() {
        push(title: String(localized: "Shows"), items: model.shows.prefix(Self.maxItems).map { show in
            let item = CPListItem(text: show.show.title, detailText: show.show.author)
            item.accessoryType = .disclosureIndicator
            item.handler = { [weak self] _, completion in
                Task {
                    guard let self else { completion(); return }
                    let episodes = ((try? await self.model.episodes(of: show)) ?? [])
                        .sorted { ($0.episode.publishedAt ?? .distantPast) > ($1.episode.publishedAt ?? .distantPast) }
                        .filter(self.model.canPlay)
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
            if let progress = model.progress(of: episode), let duration = episode.episode.durationMs, duration > 0, !progress.played {
                item.playbackProgress = CGFloat(min(Double(progress.positionMs) / Double(duration), 1))
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
        let rates: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
        let current = model.engine.rate
        model.setRate(rates.first { $0 > current + 0.01 } ?? rates[0])
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
        let template = CPListTemplate(title: title, sections: [CPListSection(items: items)])
        template.emptyViewTitleVariants = [emptyText]
        interfaceController?.pushTemplate(template, animated: true) { _, _ in }
    }

    /// The row appears at once; its picture fills in when loaded.
    private func loadPicture(for item: CPListItem, url: URL?) {
        Task {
            if let data = await model.smallPicture(url, size: 60), let image = UIImage(data: data) { item.setImage(image) }
        }
    }
}
