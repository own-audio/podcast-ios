import Foundation

/// What a show's download rules ask for: which episodes to download and which to let go.
/// Pure, so the app runs it whenever a show's episodes, its settings or a played state change.
public enum DownloadRules {
    public struct Item: Sendable, Equatable {
        public let id: String
        public let publishedAt: Date?
        public let isPlayed: Bool
        public let isDownloaded: Bool

        public init(id: String, publishedAt: Date?, isPlayed: Bool, isDownloaded: Bool) {
            self.id = id
            self.publishedAt = publishedAt
            self.isPlayed = isPlayed
            self.isDownloaded = isDownloaded
        }
    }

    public struct Plan: Sendable, Equatable {
        public var download: [String] = []
        public var remove: [String] = []

        public init(download: [String] = [], remove: [String] = []) {
            self.download = download
            self.remove = remove
        }
    }

    /// `items` are one show's episodes; `protected` (the episode playing) is never removed.
    /// Only the newest `autoDownload` episodes are ever downloaded by a rule — never the back
    /// catalogue — and only unplayed ones; a manual download is kept unless a rule removes it.
    public static func plan(for items: [Item], settings: ShowSettings, protected: String?) -> Plan {
        let newestFirst = items.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
        var plan = Plan()
        var removed = Set<String>()
        if settings.deleteWhenPlayed {
            for item in newestFirst where item.isDownloaded && item.isPlayed && item.id != protected {
                plan.remove.append(item.id)
                removed.insert(item.id)
            }
        }
        var kept = newestFirst.filter { $0.isDownloaded && !removed.contains($0.id) }.map(\.id)
        if settings.autoDownload > 0 {
            for item in newestFirst.prefix(settings.autoDownload) where !item.isDownloaded && !item.isPlayed {
                plan.download.append(item.id)
            }
        }
        if let limit = settings.keepAtMost {
            // The new downloads count against the limit; the newest stay.
            let order = newestFirst.map(\.id)
            kept = (kept + plan.download).sorted { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! }
            for id in kept.dropFirst(limit).reversed() where id != protected {
                if let index = plan.download.firstIndex(of: id) {
                    plan.download.remove(at: index)
                } else {
                    plan.remove.append(id)
                }
            }
        }
        return plan
    }
}
