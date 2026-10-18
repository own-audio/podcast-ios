import ActivityKit
import Foundation
import Observation
import OSLog
import PodcastLibrary
import UIKit

private let log = Logger(subsystem: "audio.own.podcastplayer", category: "liveActivity")

/// Keeps one Live Activity in step with the player: started when an episode loads, moved with
/// the position (at most every 15 s while playing, at once on play, pause, chapter, speed or a
/// new skip interval), ended when the player lets the episode go. The picture goes into the App
/// Group as a small JPEG, since the activity's own state may only carry a few kilobytes. Copied
/// from the books app's `LiveActivityController`.
@MainActor
final class LiveActivityController {
    private weak var model: AppModel?
    private var activity: Activity<EpisodeActivityAttributes>?
    private var activityEpisodeId: String?
    private var lastSentAt = Date.distantPast
    private var lastState: EpisodeActivityAttributes.ContentState?
    /// The picture written for the current episode, once there is one.
    private var coverFile: String?
    private var fetchingCover = false

    init(model: AppModel) {
        self.model = model
        PlaybackControlIntent.handler = { [weak model] action in
            guard let model else { return }
            switch action {
            case .toggle: model.engine.togglePlayPause()
            case .back: model.engine.skipBackward()
            case .forward: model.engine.skipForward()
            }
        }
        observe()
    }

    /// Re-registers for the next change of what the activity shows, as `@Observable` wants.
    private func observe() {
        guard let model else { return }
        withObservationTracking {
            _ = model.engine.book?.id
            _ = model.engine.isPlaying
            _ = model.engine.rate
            _ = model.engine.currentChapter?.startMs
            _ = model.settings.skipBackwardSecs
            _ = model.settings.skipForwardSecs
        } onChange: {
            Task { @MainActor [weak self] in
                self?.sync(force: true)
                self?.observe()
            }
        }
    }

    /// Called on the player's position ticks; the throttle keeps the system's budget.
    func tick() {
        sync(force: false)
    }

    private func sync(force: Bool) {
        guard let model else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let spoken = model.engine.book, let item = model.nowPlaying, spoken.id == item.id else {
            end()
            return
        }
        let state = EpisodeActivityAttributes.ContentState(
            chapter: model.engine.currentChapter?.title, positionMs: model.engine.positionMs, durationMs: model.engine.durationMs,
            isPlaying: model.engine.isPlaying, rate: model.engine.rate, at: Date(),
            coverFile: activityEpisodeId == spoken.id ? coverFile : nil,
            skipBackSecs: Int(model.settings.skipBackwardSecs), skipForwardSecs: Int(model.settings.skipForwardSecs)
        )
        if activityEpisodeId != spoken.id {
            Task { await start(item: item, show: model.nowPlayingShow, state: state) }
            return
        }
        if coverFile == nil { fetchCover(item: item) }
        guard let activity else { return }
        if !force, state.isPlaying == lastState?.isPlaying, Date().timeIntervalSince(lastSentAt) < 15 { return }
        lastSentAt = Date()
        lastState = state
        // ActivityKit's handle isn't Sendable; its calls are safe from any task.
        nonisolated(unsafe) let handle = activity
        Task { await handle.update(ActivityContent(state: state, staleDate: nil)) }
    }

    private func start(item: SourcedEpisode, show: Show?, state: EpisodeActivityAttributes.ContentState) async {
        await endCurrent()
        activityEpisodeId = item.id
        coverFile = nil
        let attributes = EpisodeActivityAttributes(episodeId: item.id, title: item.episode.title, show: show?.title ?? "")
        do {
            activity = try Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil))
            lastSentAt = Date()
            lastState = state
        } catch {
            log.error("could not start: \(String(describing: error), privacy: .public)")
            activityEpisodeId = nil
            return
        }
        fetchCover(item: item)
    }

    /// The picture as a small JPEG in the App Group; the next sync carries its name.
    private func fetchCover(item: SourcedEpisode) {
        guard !fetchingCover, coverFile == nil, let model else { return }
        fetchingCover = true
        let url = item.episode.imageURL ?? model.nowPlayingShow?.imageURL
        Task { [weak self] in
            defer { self?.fetchingCover = false }
            guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: EpisodeActivityAttributes.appGroup),
                  let data = await self?.model?.smallPicture(url, size: 160) else { return }
            let name = "cover-" + item.id.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }.map(String.init).joined() + ".jpg"
            do {
                try data.write(to: group.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } catch {
                log.error("could not write the picture: \(String(describing: error), privacy: .public)")
                return
            }
            guard let self, self.activityEpisodeId == item.id else { return }
            self.coverFile = name
            self.sync(force: true)
        }
    }

    private func end() {
        guard activity != nil else { return }
        Task { await endCurrent() }
    }

    private func endCurrent() async {
        if let activity {
            nonisolated(unsafe) let handle = activity
            await handle.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        activityEpisodeId = nil
        lastState = nil
    }
}
