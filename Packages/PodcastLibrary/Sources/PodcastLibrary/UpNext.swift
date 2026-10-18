import Foundation

/// The listener's queue across every source: what plays after the episode in the player, in
/// order. Kept on the phone — no server has a podcast queue (decision 5) — with each episode and
/// its show as they were, so it lists and plays offline. The sources' own `queue()` stays for a
/// server that may one day keep one.
public final class UpNext: @unchecked Sendable {
    public struct Entry: Codable, Sendable, Equatable, Identifiable {
        /// The episode as the app knows it: its source and key.
        public let id: String
        /// The source, as the app names it.
        public let source: String
        public var episode: Episode
        public var show: Show?

        public init(id: String, source: String, episode: Episode, show: Show?) {
            self.id = id
            self.source = source
            self.episode = episode
            self.show = show
        }
    }

    private let file: URL
    private let lock = NSLock()
    private var entries: [Entry]

    public init(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appendingPathComponent("up-next.json")
        entries = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }

    public var all: [Entry] { lock.withLock { entries } }

    public func contains(_ id: String) -> Bool { lock.withLock { entries.contains { $0.id == id } } }

    /// First in line.
    public func playNext(_ entry: Entry) {
        change { $0.removeAll { $0.id == entry.id }; $0.insert(entry, at: 0) }
    }

    /// Last in line; an episode already queued stays where it is.
    public func playLater(_ entry: Entry) {
        change { if !$0.contains(where: { $0.id == entry.id }) { $0.append(entry) } }
    }

    public func remove(_ id: String) {
        change { $0.removeAll { $0.id == id } }
    }

    /// Everything of a source (a removed server, an unfollowed show), by the id's prefix.
    public func removeAll(where matches: (Entry) -> Bool) {
        change { $0.removeAll(where: matches) }
    }

    public func move(from offsets: IndexSet, to destination: Int) {
        change { list in
            let moving = offsets.sorted().map { list[$0] }
            var rest = list.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
            let before = offsets.filter { $0 < destination }.count
            rest.insert(contentsOf: moving, at: max(0, min(rest.count, destination - before)))
            list = rest
        }
    }

    /// The next to play after `current` (which leaves the queue if it was in it), taken out.
    public func takeNext(after current: String?) -> Entry? {
        var next: Entry?
        change { list in
            if let current { list.removeAll { $0.id == current } }
            if !list.isEmpty { next = list.removeFirst() }
        }
        return next
    }

    public func clear() { change { $0 = [] } }

    private func change(_ work: (inout [Entry]) -> Void) {
        lock.withLock {
            work(&entries)
            if entries.isEmpty {
                try? FileManager.default.removeItem(at: file)
            } else if let data = try? JSONEncoder().encode(entries) {
                try? data.write(to: file, options: .atomic)
            }
        }
    }
}
