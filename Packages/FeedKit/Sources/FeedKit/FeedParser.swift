import Foundation

public enum FeedError: Error, Sendable, Equatable {
    /// The document is XML but neither RSS nor Atom: an HTML page, an OPML file, an error.
    case notAFeed
    /// The XML could not be read, even after the usual repair.
    case malformed(String)
    case tooLarge
    case http(Int)
    case network
}

/// Reads RSS 2.0 (and RSS 1.0) and Atom into a `FeedDocument`. Lenient where real feeds are
/// sloppy: unescaped ampersands, missing GUIDs, dates and durations in odd forms, HTML in every
/// text field, text that was decoded with the wrong encoding somewhere upstream.
public enum FeedParser {
    public static func parse(_ data: Data) throws -> FeedDocument {
        do {
            return try parseOnce(data)
        } catch FeedError.malformed(let reason) {
            // The common breakage: a bare "&" in a title. Escape those and try once more.
            guard let repaired = escapeBareAmpersands(data), repaired != data else { throw FeedError.malformed(reason) }
            return try parseOnce(repaired)
        }
    }

    private static func parseOnce(_ data: Data) throws -> FeedDocument {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        let ok = parser.parse()
        if delegate.rejectedRoot { throw FeedError.notAFeed }
        if delegate.kind == nil { throw ok ? FeedError.notAFeed : FeedError.malformed(parser.parserError?.localizedDescription ?? "unreadable XML") }
        // A feed that broke off after the show came through is still worth its episodes so far.
        if !ok, delegate.episodes.isEmpty, delegate.show.title.isEmpty {
            throw FeedError.malformed(parser.parserError?.localizedDescription ?? "unreadable XML")
        }
        return delegate.document()
    }

    static func escapeBareAmpersands(_ data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let fixed = text.replacingOccurrences(of: "&(?!(?:[A-Za-z][A-Za-z0-9]{1,8}|#[0-9]{1,7}|#x[0-9A-Fa-f]{1,6});)", with: "&amp;", options: .regularExpression)
        return Data(fixed.utf8)
    }
}

private enum Namespace {
    static func isITunes(_ uri: String?) -> Bool { uri?.lowercased() == "http://www.itunes.com/dtds/podcast-1.0.dtd" }
    static func isPodcast(_ uri: String?) -> Bool {
        guard let uri = uri?.lowercased() else { return false }
        return uri.contains("podcastindex.org/namespace") || uri.contains("podcast-namespace")
    }
    static func isContent(_ uri: String?) -> Bool { uri == "http://purl.org/rss/1.0/modules/content/" }
    static func isAtom(_ uri: String?) -> Bool { uri == "http://www.w3.org/2005/Atom" }
    static func isPSC(_ uri: String?) -> Bool { uri?.hasPrefix("http://podlove.org/simple-chapters") == true }
    static func isMedia(_ uri: String?) -> Bool { uri == "http://search.yahoo.com/mrss/" }
    static func isPlain(_ uri: String?) -> Bool { uri == nil || uri == "" || uri == "http://purl.org/rss/1.0/" }
}

/// Element by element. Text is gathered per element (characters and CDATA alike) and read when
/// the element ends; what it means depends on where we are — the channel, an item, the RSS
/// `<image>`, an Atom `<author>`.
private final class Delegate: NSObject, XMLParserDelegate {
    enum Kind { case rss, atom }

    var kind: Kind?
    /// The root was some other XML (HTML, OPML): not a feed, whatever else is wrong with it.
    var rejectedRoot = false
    var show = FeedShow(title: "")
    var episodes: [FeedEpisode] = []

    private var item: ItemDraft?
    private var text = ""
    private var stack: [String] = []
    private var inImage = false
    private var inAuthor = false
    private var showSummary: String?
    private var showContent: String?
    private var showAuthorFallback: String?
    private var categories: [String] = []

    /// An item while it is read; the first of `guid`, enclosure URL, link, title + date wins as
    /// its id.
    struct ItemDraft {
        var guid: String?
        var title = ""
        var link: URL?
        var description: String?
        var content: String?
        var summary: String?
        var publishedAt: Date?
        var updatedAt: Date?
        var durationMs: Int64?
        var enclosure: FeedEnclosure?
        var mediaContent: FeedEnclosure?
        var imageURL: URL?
        var season: Int?
        var episode: Int?
        var episodeType: String?
        var isExplicit = false
        var chaptersURL: URL?
        var chapters: [FeedChapter] = []
        var transcripts: [FeedTranscript] = []
        var persons: [FeedPerson] = []
        var personAttributes: [String: String] = [:]
    }

    func document() -> FeedDocument {
        var show = self.show
        if show.title.isEmpty { show.title = show.link?.host() ?? "" }
        let html = showContent ?? show.descriptionHTML ?? showSummary
        show.descriptionHTML = html
        show.description = html.map(HTMLText.plain).map(Mojibake.repair).flatMap { $0.isEmpty ? nil : $0 }
        if show.author == nil { show.author = showAuthorFallback }
        show.categories = categories
        return FeedDocument(show: show, episodes: episodes)
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI uri: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        stack.append(name)
        if kind == nil {
            switch name {
            case "rss", "RDF": kind = .rss
            case "feed" where Namespace.isAtom(uri): kind = .atom
            default:
                rejectedRoot = true
                parser.abortParsing()
            }
            return
        }
        let attribute = { (key: String) in attributes[key] }

        if (name == "item" && Namespace.isPlain(uri)) || (name == "entry" && Namespace.isAtom(uri)) {
            item = ItemDraft()
            return
        }
        if name == "image", Namespace.isPlain(uri), item == nil { inImage = true }
        if name == "author", Namespace.isAtom(uri) { inAuthor = true }

        if Namespace.isITunes(uri) {
            switch name {
            case "image":
                if let url = FeedValues.url(attribute("href")) {
                    if item != nil { item?.imageURL = url } else { show.imageURL = url }
                }
            case "category" where item == nil:
                if let text = attribute("text"), !text.isEmpty, !categories.contains(text) { categories.append(HTMLText.decodeEntities(text)) }
            default: break
            }
        } else if Namespace.isPodcast(uri) {
            switch name {
            case "chapters":
                item?.chaptersURL = FeedValues.url(attribute("url"))
            case "transcript":
                if let url = FeedValues.url(attribute("url")) {
                    item?.transcripts.append(FeedTranscript(url: url, type: attribute("type") ?? "text/plain", language: attribute("language")))
                }
            case "person":
                item?.personAttributes = attributes
            case "funding" where item == nil:
                if let url = FeedValues.url(attribute("url")) { show.funding.append(FeedLink(url: url, title: nil)) }
            default: break
            }
        } else if Namespace.isPSC(uri), name == "chapter" {
            if let start = FeedValues.timeMs(attribute("start")) {
                item?.chapters.append(FeedChapter(
                    startMs: start, title: Mojibake.repair(HTMLText.decodeEntities(attribute("title") ?? "")),
                    url: FeedValues.url(attribute("href")), imageURL: FeedValues.url(attribute("image"))
                ))
            }
        } else if Namespace.isMedia(uri), name == "content", item != nil {
            if let url = FeedValues.url(attribute("url")), item?.mediaContent == nil {
                item?.mediaContent = FeedEnclosure(url: url, type: attribute("type"), length: attribute("fileSize").flatMap { Int64($0) })
            }
        } else if Namespace.isPlain(uri), name == "enclosure", item != nil {
            if let url = FeedValues.url(attribute("url")), item?.enclosure == nil {
                item?.enclosure = FeedEnclosure(url: url, type: attribute("type"), length: attribute("length").flatMap { Int64($0.trimmingCharacters(in: .whitespaces)) })
            }
        } else if Namespace.isAtom(uri), name == "link" {
            let rel = attribute("rel") ?? "alternate"
            let href = FeedValues.url(attribute("href"))
            if item != nil {
                if rel == "enclosure", let href, item?.enclosure == nil {
                    item?.enclosure = FeedEnclosure(url: href, type: attribute("type"), length: attribute("length").flatMap { Int64($0) })
                } else if rel == "alternate", item?.link == nil {
                    item?.link = href
                }
            } else if kind == .atom, rel == "alternate", show.link == nil {
                show.link = href
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA data: Data) {
        text += String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI uri: String?, qualifiedName: String?) {
        defer {
            stack.removeLast()
            text = ""
        }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if (name == "item" && Namespace.isPlain(uri)) || (name == "entry" && Namespace.isAtom(uri)) {
            if let draft = item { episodes.append(finish(draft)) }
            item = nil
            return
        }
        if name == "image", Namespace.isPlain(uri), item == nil { inImage = false; return }
        if name == "author", Namespace.isAtom(uri) { inAuthor = false; return }

        if item != nil {
            endItemElement(name, uri: uri, value: value)
        } else {
            endShowElement(name, uri: uri, value: value)
        }
    }

    private func endShowElement(_ name: String, uri: String?, value: String) {
        if inImage {
            if name == "url", show.imageURL == nil { show.imageURL = FeedValues.url(value) }
            return
        }
        if inAuthor {
            if name == "name", show.author == nil { show.author = clean(value) }
            return
        }
        if Namespace.isITunes(uri) {
            switch name {
            case "author": show.author = clean(value)
            case "summary": showSummary = value
            case "explicit": show.isExplicit = FeedValues.flag(value)
            case "type": show.isSerial = value.lowercased() == "serial"
            case "new-feed-url": show.newFeedURL = FeedValues.url(value)
            case "complete": show.isComplete = FeedValues.flag(value)
            case "name" where stack.dropLast().last == "owner": showAuthorFallback = showAuthorFallback ?? clean(value)
            default: break
            }
        } else if Namespace.isPodcast(uri) {
            switch name {
            case "guid": show.podcastGUID = value.isEmpty ? nil : value
            case "funding":
                if !value.isEmpty, let last = show.funding.indices.last { show.funding[last].title = clean(value) }
            default: break
            }
        } else if Namespace.isContent(uri), name == "encoded" {
            showContent = value
        } else if Namespace.isPlain(uri) || Namespace.isAtom(uri) {
            // Only the channel's (or Atom feed's) own children, not those of nested elements.
            let parent = stack.dropLast().last
            guard parent == "channel" || parent == "feed" else { return }
            switch name {
            case "title": show.title = clean(value) ?? ""
            case "link" where Namespace.isPlain(uri): show.link = FeedValues.url(value)
            case "description", "subtitle": show.descriptionHTML = value.isEmpty ? nil : value
            case "language": show.language = value.isEmpty ? nil : value
            case "lastBuildDate", "updated": show.lastBuildDate = FeedValues.date(value) ?? show.lastBuildDate
            case "pubDate": show.lastBuildDate = show.lastBuildDate ?? FeedValues.date(value)
            case "author", "managingEditor": showAuthorFallback = showAuthorFallback ?? clean(value)
            case "icon", "logo": show.imageURL = show.imageURL ?? FeedValues.url(value)
            default: break
            }
        }
    }

    private func endItemElement(_ name: String, uri: String?, value: String) {
        if Namespace.isITunes(uri) {
            switch name {
            case "duration": item?.durationMs = FeedValues.durationMs(value)
            case "summary": item?.summary = value
            case "season": item?.season = FeedValues.int(value)
            case "episode": item?.episode = FeedValues.int(value)
            case "episodeType": item?.episodeType = value.lowercased()
            case "explicit": item?.isExplicit = FeedValues.flag(value)
            case "title" where item?.title.isEmpty ?? true: item?.title = clean(value) ?? ""
            default: break
            }
        } else if Namespace.isPodcast(uri) {
            if name == "person", !value.isEmpty, let attributes = item?.personAttributes {
                item?.persons.append(FeedPerson(
                    name: clean(value) ?? value, role: attributes["role"]?.lowercased() ?? "host",
                    imageURL: FeedValues.url(attributes["img"]), link: FeedValues.url(attributes["href"])
                ))
                item?.personAttributes = [:]
            }
        } else if Namespace.isContent(uri), name == "encoded" {
            item?.content = value
        } else if Namespace.isPlain(uri) || Namespace.isAtom(uri) {
            switch name {
            case "title": item?.title = clean(value) ?? ""
            case "link" where Namespace.isPlain(uri): item?.link = FeedValues.url(value)
            case "guid", "id": item?.guid = value.isEmpty ? nil : value
            case "description", "summary": item?.description = value
            case "content" where Namespace.isAtom(uri): item?.content = value
            case "pubDate", "published", "date": item?.publishedAt = FeedValues.date(value)
            case "updated": item?.updatedAt = FeedValues.date(value)
            default: break
            }
        }
    }

    private func finish(_ draft: ItemDraft) -> FeedEpisode {
        let enclosure = draft.enclosure ?? draft.mediaContent
        let id = draft.guid ?? enclosure?.url.absoluteString ?? draft.link?.absoluteString
            ?? "\(draft.title)|\(draft.publishedAt?.timeIntervalSince1970 ?? 0)"
        var episode = FeedEpisode(id: id, title: draft.title)
        let html = draft.content ?? draft.description ?? draft.summary
        episode.descriptionHTML = html
        episode.description = html.map(HTMLText.plain).map(Mojibake.repair).flatMap { $0.isEmpty ? nil : $0 }
        episode.publishedAt = draft.publishedAt ?? draft.updatedAt
        episode.durationMs = draft.durationMs
        episode.enclosure = enclosure
        episode.link = draft.link
        episode.imageURL = draft.imageURL
        episode.season = draft.season
        episode.episode = draft.episode
        episode.episodeType = draft.episodeType
        episode.isExplicit = draft.isExplicit
        episode.chaptersURL = draft.chaptersURL
        episode.inlineChapters = Chapters.closed(draft.chapters)
        episode.transcripts = draft.transcripts
        episode.persons = draft.persons
        return episode
    }

    /// Entities decoded, tags dropped, mis-decoded UTF-8 repaired; empty is nil.
    private func clean(_ value: String) -> String? {
        let plain = value.contains("<") ? HTMLText.plain(value) : HTMLText.decodeEntities(value)
        let text = Mojibake.repair(plain.trimmingCharacters(in: .whitespacesAndNewlines))
        return text.isEmpty ? nil : text
    }
}
