import Foundation
import Observation
import PlayerCore
import PodcastLibrary
import UIKit

/// Episodes kept on the phone, through a background `URLSession`: a download goes on when the
/// app is in the background or gone, and picks up where it stopped after a kill. Copied from
/// the books app's `DownloadManager`; an episode is one file, so a download is one task.
///
/// Files live in Application Support, which iOS doesn't clear the way it clears Caches, and are
/// excluded from iCloud backup: they can always be downloaded again. An index file records
/// each episode with its show, so the Downloads tab works with no network at all.
@Observable
@MainActor
final class DownloadManager: NSObject {
    enum State: Equatable {
        case downloading(fraction: Double)
        case downloaded
        case failed(String)
    }

    /// An episode on the phone (or on its way): the episode and its show as they were, the
    /// source it came from (`SourceRef.id`), and its file.
    struct DownloadedEpisode: Codable, Equatable, Identifiable {
        /// `SourcedEpisode.id`.
        let id: String
        let source: String
        var episode: Episode
        var show: Show?
        var fileName: String?
        var bytes: Int64
        let startedAt: Date
        var finishedAt: Date?
        var lastPlayedAt: Date?

        var isComplete: Bool { fileName != nil }
        var sourceRef: SourceRef? { SourceRef(id: source) }
        var item: SourcedEpisode? { sourceRef.map { SourcedEpisode(source: $0, episode: episode) } }
    }

    private struct Index: Codable {
        var episodes: [String: DownloadedEpisode] = [:]
        /// Resume data of downloads that were interrupted, by episode id.
        var resumeData: [String: Data] = [:]
    }

    private(set) var episodes: [String: DownloadedEpisode] = [:]
    private(set) var states: [String: State] = [:]
    private var resumeData: [String: Data] = [:]
    var wifiOnly = true { didSet { if wifiOnly != oldValue { restart() } } }
    /// What the app asks for an episode's file URL; the session can't, it only knows ids.
    var urlProvider: ((_ id: String) async throws -> URL)?
    /// Called when the session reports that its background work is done, so the app can tell
    /// iOS (`handleEventsForBackgroundURLSession`).
    var backgroundCompletion: (() -> Void)?

    private let directory: URL
    private let indexURL: URL
    private var session: URLSession!
    private var tasks: [String: URLSessionDownloadTask] = [:]
    static let sessionIdentifier = "audio.own.podcastplayer.downloads"

    override init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("Downloads", isDirectory: true)
        indexURL = directory.appendingPathComponent("index.json")
        super.init()
        if UITestFlags.isUITesting { try? FileManager.default.removeItem(at: directory) }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? excluded.setResourceValues(values)
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        loadIndex()
    }

    // MARK: - Reading

    var totalBytes: Int64 { episodes.values.reduce(0) { $0 + $1.bytes } }

    func state(of id: String) -> State? { states[id] }

    func isDownloaded(_ id: String) -> Bool { episodes[id]?.isComplete == true }

    /// The local file of a downloaded episode.
    func fileURL(_ id: String) -> URL? {
        episodes[id]?.fileName.map { directory.appendingPathComponent($0) }
    }

    func notePlayed(_ id: String) {
        guard episodes[id] != nil else { return }
        episodes[id]?.lastPlayedAt = Date()
        saveIndex()
    }

    // MARK: - Changing

    func download(_ item: SourcedEpisode, show: Show?) {
        guard episodes[item.id]?.isComplete != true else { return }
        if episodes[item.id] == nil {
            episodes[item.id] = DownloadedEpisode(id: item.id, source: item.source.id, episode: item.episode, show: show, bytes: 0, startedAt: Date())
        }
        states[item.id] = .downloading(fraction: 0)
        saveIndex()
        start(item.id)
    }

    func remove(_ id: String) {
        tasks.removeValue(forKey: id)?.cancel()
        if let name = episodes.removeValue(forKey: id)?.fileName {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
        resumeData[id] = nil
        states[id] = nil
        saveIndex()
    }

    /// Everything, or what came from one source (a server and its libraries, by id prefix).
    func removeAll(where matches: (DownloadedEpisode) -> Bool = { _ in true }) {
        for entry in episodes.values where matches(entry) { remove(entry.id) }
    }

    /// Lets go of what the cap no longer allows; `protected` is the episode playing now.
    func enforce(capBytes: Int64?, protected: String?, isPlayed: (String) -> Bool) {
        let policy = EvictionPolicy(capBytes: capBytes)
        let candidates = episodes.values.filter(\.isComplete).map {
            EvictionPolicy.Candidate(id: $0.id, bytes: $0.bytes, isFinished: isPlayed($0.id), lastUsedAt: $0.lastPlayedAt ?? $0.finishedAt ?? $0.startedAt)
        }
        for id in policy.evictions(from: candidates, protected: protected) { remove(id) }
    }

    func retry(_ id: String) {
        guard let entry = episodes[id], !entry.isComplete else { return }
        states[id] = .downloading(fraction: 0)
        start(id)
    }

    /// Picks up interrupted downloads: at launch, and after the session was recreated.
    func resume() {
        session.getAllTasks { [weak self] running in
            Task { @MainActor [weak self] in
                guard let self else { return }
                for task in running as? [URLSessionDownloadTask] ?? [] {
                    if let key = task.taskDescription { self.tasks[key] = task }
                }
                for entry in self.episodes.values where !entry.isComplete && self.tasks[entry.id] == nil {
                    if case .failed = self.states[entry.id] { continue }
                    self.states[entry.id] = .downloading(fraction: 0)
                    self.start(entry.id)
                }
            }
        }
    }

    private func restart() {
        for (key, task) in tasks {
            task.cancel { [weak self] data in
                Task { @MainActor in
                    if let data { self?.resumeData[key] = data }
                    self?.tasks[key] = nil
                    self?.start(key)
                }
            }
        }
    }

    // MARK: - Work

    private func start(_ id: String) {
        guard tasks[id] == nil else { return }
        if let data = resumeData.removeValue(forKey: id) {
            let task = session.downloadTask(withResumeData: data)
            task.taskDescription = id
            tasks[id] = task
            task.resume()
            saveIndex()
            return
        }
        guard let urlProvider else { return }
        Task { [weak self] in
            do {
                let url = try await urlProvider(id)
                guard let self, self.episodes[id] != nil, self.tasks[id] == nil else { return }
                var request = URLRequest(url: url)
                request.allowsCellularAccess = !self.wifiOnly
                request.setValue("own.audio Podcasts/\(AppModel.appVersion) iOS", forHTTPHeaderField: "User-Agent")
                let task = self.session.downloadTask(with: request)
                task.taskDescription = id
                self.tasks[id] = task
                task.resume()
            } catch {
                self?.states[id] = .failed(AppModel.message(for: error))
            }
        }
    }

    private func finished(id: String, file: URL, response: URLResponse?) {
        guard var entry = episodes[id] else {
            try? FileManager.default.removeItem(at: file)
            return
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: file)
            states[id] = .failed(String(localized: "The server did not send the file."))
            return
        }
        // AVFoundation types a local file by its extension, so one is worked out: from the
        // bytes, else the server's content type, else what the feed says.
        let head = (try? FileHandle(forReadingFrom: file)).flatMap { handle -> Data? in
            defer { try? handle.close() }
            return try? handle.read(upToCount: 12)
        } ?? Data()
        let ext = TrackFileCache.fileExtension(prefix: head) ?? TrackFileCache.fileExtension(mimeType: http.mimeType)
            ?? TrackFileCache.fileExtension(mimeType: entry.episode.audioType) ?? "mp3"
        let name = Self.safeName(id) + "." + ext
        let destination = directory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: file, to: destination)
        } catch {
            states[id] = .failed(error.localizedDescription)
            return
        }
        entry.fileName = name
        entry.bytes = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0
        entry.finishedAt = Date()
        episodes[id] = entry
        states[id] = .downloaded
        saveIndex()
    }

    // MARK: - Index

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL), let index = try? JSONDecoder().decode(Index.self, from: data) else { return }
        // A file the index lists but the disk lost is not downloaded any more.
        episodes = index.episodes.mapValues { entry in
            var entry = entry
            if let name = entry.fileName, !FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) {
                entry.fileName = nil
                entry.bytes = 0
            }
            return entry
        }
        resumeData = index.resumeData
        for entry in episodes.values { states[entry.id] = entry.isComplete ? .downloaded : .downloading(fraction: 0) }
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder().encode(Index(episodes: episodes, resumeData: resumeData)) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private static func safeName(_ key: String) -> String {
        Data(key.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    /// The file must be moved before this returns; it is done here, on the session's queue,
    /// and the index is updated on the main actor afterwards.
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let id = downloadTask.taskDescription ?? ""
        let response = downloadTask.response
        let holding = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.moveItem(at: location, to: holding)
        Task { @MainActor in
            self.tasks[id] = nil
            self.finished(id: id, file: holding, response: response)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let id = downloadTask.taskDescription ?? ""
        Task { @MainActor in
            guard let entry = self.episodes[id], !entry.isComplete else { return }
            let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : (entry.episode.audioBytes ?? 0)
            self.states[id] = .downloading(fraction: expected > 0 ? min(1, Double(totalBytesWritten) / Double(expected)) : 0)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let id = task.taskDescription ?? ""
        let resume = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        let cancelled = (error as NSError).code == NSURLErrorCancelled
        Task { @MainActor in
            self.tasks[id] = nil
            if let resume { self.resumeData[id] = resume }
            if !cancelled, self.episodes[id] != nil {
                self.states[id] = .failed(error.localizedDescription)
            }
            self.saveIndex()
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            self.backgroundCompletion?()
            self.backgroundCompletion = nil
        }
    }
}
