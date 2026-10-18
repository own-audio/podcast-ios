import Foundation

/// Every position meant for a server is written here before it is sent, and removed once the
/// server has it. A dead server, a lost network or a killed app leaves it on disk, to be sent
/// when the server is back. One entry per episode: a newer position replaces the older one, so
/// a server that was down for an hour gets one report, not hundreds. Copied from the books
/// app's `PendingProgress`, keyed by episode instead of book and play session.
public final class PendingProgress: @unchecked Sendable {
    public struct Entry: Codable, Sendable, Equatable {
        /// The episode as the app knows it: its source and key.
        public let id: String
        public var progress: ListeningProgress

        public init(id: String, progress: ListeningProgress) {
            self.id = id
            self.progress = progress
        }
    }

    private let file: URL
    private let lock = NSLock()

    public init(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appendingPathComponent("pending-progress.json")
    }

    /// Oldest first, so a server receives positions in the order they happened.
    public func all() -> [Entry] {
        lock.withLock { read().sorted { $0.progress.updatedAt < $1.progress.updatedAt } }
    }

    public func record(_ entry: Entry) {
        lock.withLock {
            var entries = read()
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                if entries[index].progress.updatedAt <= entry.progress.updatedAt { entries[index] = entry }
            } else {
                entries.append(entry)
            }
            write(entries)
        }
    }

    /// Once the server has it — unless a newer position was recorded since.
    public func sent(_ entry: Entry) {
        lock.withLock { write(read().filter { !($0.id == entry.id && $0.progress.updatedAt <= entry.progress.updatedAt) }) }
    }

    /// Everything of a source (a removed server), by the id's prefix.
    public func removeAll(prefix: String) {
        lock.withLock { write(read().filter { !$0.id.hasPrefix(prefix) }) }
    }

    private func read() -> [Entry] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private func write(_ entries: [Entry]) {
        if entries.isEmpty { try? FileManager.default.removeItem(at: file); return }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
