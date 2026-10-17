import Foundation

/// Podcasting 2.0 chapter documents (`application/json+chapters`) and the closing of chapter
/// lists that give only start times.
public enum Chapters {
    /// Parses a chapters document. Chapters with `toc: false` are kept but marked, since they
    /// change only the image or link; the list comes back sorted and closed.
    public static func parse(_ data: Data) throws -> [FeedChapter] {
        struct Document: Decodable {
            struct Chapter: Decodable {
                let startTime: Double
                let endTime: Double?
                let title: String?
                let img: String?
                let url: String?
                let toc: Bool?
            }
            let chapters: [Chapter]
        }
        let document = try JSONDecoder().decode(Document.self, from: data)
        let chapters = document.chapters.map { chapter in
            FeedChapter(
                startMs: Int64((chapter.startTime * 1000).rounded()), endMs: chapter.endTime.map { Int64(($0 * 1000).rounded()) },
                title: Mojibake.repair(chapter.title ?? ""), url: FeedValues.url(chapter.url), imageURL: FeedValues.url(chapter.img),
                isInTableOfContents: chapter.toc ?? true
            )
        }
        return closed(chapters)
    }

    /// Sorted by start, each ending where the next begins unless it says otherwise; the last
    /// stays open (the episode's length closes it, which the feed may not know).
    public static func closed(_ chapters: [FeedChapter]) -> [FeedChapter] {
        var sorted = chapters.sorted { $0.startMs < $1.startMs }
        for index in sorted.indices where sorted[index].endMs == nil && index + 1 < sorted.count {
            sorted[index].endMs = sorted[index + 1].startMs
        }
        return sorted
    }
}
