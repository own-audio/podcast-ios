import Foundation
import Testing

@testable import FeedKit

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

@Suite("FeedParser")
struct FeedParserTests {
    @Test("an iTunes RSS feed: the show with its tags, episodes with HTML notes made text")
    func itunes() throws {
        let feed = try FeedParser.parse(try fixture("itunes.xml"))
        let show = feed.show
        #expect(show.title == "The Workshop Hour")
        #expect(show.author == "Jane Maker & Friends")
        #expect(show.description == "Weekly talks about making things.\n\nTools & techniques.")
        #expect(show.imageURL == URL(string: "https://example.com/workshop/cover.jpg"), "itunes:image wins over the RSS image")
        #expect(show.categories == ["Leisure", "Hobbies", "Arts & Design"])
        #expect(show.isSerial && !show.isExplicit && show.language == "en-us")
        #expect(show.newFeedURL == URL(string: "https://feeds.example.org/workshop"))
        #expect(show.link == URL(string: "https://example.com/workshop"))
        #expect(show.lastBuildDate == date("2026-10-16T08:30:00Z"))

        #expect(feed.episodes.map(\.id) == ["workshop-0003", "https://example.com/workshop/2", "workshop-trailer"])
        let first = feed.episodes[0]
        #expect(first.title == "Episode 3: Chisels")
        #expect(first.description == "We sharpen chisels.\n\n• Waterstones\n• Honing guide\n\nLinks: stones — enjoy", "content:encoded wins, lists keep their bullets")
        #expect(first.durationMs == 3_723_000)
        #expect(first.enclosure == FeedEnclosure(url: URL(string: "https://cdn.example.com/workshop/003.mp3")!, type: "audio/mpeg", length: 58_123_456))
        #expect(first.season == 1 && first.episode == 3 && first.episodeType == "full" && first.isExplicit)
        #expect(first.imageURL == URL(string: "https://example.com/workshop/3.jpg"))
        #expect(first.publishedAt == date("2026-10-16T08:00:00Z"))
        #expect(feed.episodes[1].durationMs == 2_710_000)
        #expect(feed.episodes[1].description == "Saws, mostly Japanese.", "an escaped HTML summary")
        #expect(feed.episodes[1].publishedAt == date("2026-10-09T06:00:00Z"), "a numeric zone, a one-digit day")
        #expect(feed.episodes[2].durationMs == 3_723_000 && feed.episodes[2].episodeType == "trailer")
        #expect(feed.episodes[2].publishedAt == date("2026-10-01T11:00:00Z"), "no seconds, a named US zone")
    }

    @Test("Podcasting 2.0: guid, funding, chapters, transcripts, people, inline chapters, media:content")
    func podcasting20() throws {
        let feed = try FeedParser.parse(try fixture("podcasting20.xml"))
        #expect(feed.show.podcastGUID == "917393e3-1b1e-5cef-ace4-edaa54e1f810")
        #expect(feed.show.funding == [FeedLink(url: URL(string: "https://openair.example.net/support")!, title: "Support the show")])
        let rain = feed.episodes[0]
        #expect(rain.chaptersURL == URL(string: "https://openair.example.net/rain.chapters.json"))
        #expect(rain.transcripts.map(\.type) == ["text/vtt", "application/x-subrip"] && rain.transcripts[0].language == "en")
        #expect(rain.persons == [
            FeedPerson(name: "Ana Rivers", role: "guest", imageURL: URL(string: "https://openair.example.net/ana.jpg"), link: URL(string: "https://ana.example.net")),
            FeedPerson(name: "Sam Host", role: "host", imageURL: nil, link: nil),
        ])
        #expect(rain.inlineChapters.map(\.title) == ["Intro & drizzle", "Thunder", "Puddles"], "sorted by start")
        #expect(rain.inlineChapters.map(\.startMs) == [0, 600_000, 1_530_000])
        #expect(rain.inlineChapters.map(\.endMs) == [600_000, 1_530_000, nil], "closed by the next; the last stays open")
        #expect(rain.inlineChapters[0].url == URL(string: "https://openair.example.net/drizzle"))
        let wind = feed.episodes[1]
        #expect(wind.enclosure?.url == URL(string: "https://openair.example.net/wind.m4a"), "media:content stands in for a missing enclosure")
        #expect(wind.id == "https://openair.example.net/wind.m4a", "no guid: the enclosure URL identifies it")
    }

    @Test("Atom: the feed and an entry with an enclosure link")
    func atom() throws {
        let feed = try FeedParser.parse(try fixture("atom.xml"))
        #expect(feed.show.title == "Atom Talk" && feed.show.author == "Ada Atom" && feed.show.description == "A feed in Atom.")
        #expect(feed.show.link == URL(string: "https://atom.example.org/") && feed.show.imageURL == URL(string: "https://atom.example.org/logo.png"))
        let entry = try #require(feed.episodes.first)
        #expect(entry.id == "tag:atom.example.org,2026:1" && entry.title == "First")
        #expect(entry.enclosure == FeedEnclosure(url: URL(string: "https://atom.example.org/1.mp3")!, type: "audio/mpeg", length: 4321))
        #expect(entry.link == URL(string: "https://atom.example.org/1"))
        #expect(entry.description == "Hello Atom")
        #expect(entry.publishedAt == date("2026-10-15T07:30:00Z").addingTimeInterval(0.5))
    }

    @Test("a messy feed: bare ampersands, mis-decoded text, bad dates and durations, odd URLs, a post without audio")
    func messy() throws {
        let feed = try FeedParser.parse(try fixture("messy.xml"))
        #expect(feed.show.title == "Tom & Jerry Talk")
        #expect(feed.episodes.count == 4)
        #expect(feed.episodes[0].title == "Příběh první", "UTF-8 read as Latin-1 upstream, repaired")
        #expect(feed.episodes[0].publishedAt == date("2026-10-06T05:00:00Z"))
        #expect(feed.episodes[0].durationMs == nil, "a zero duration is no duration")
        #expect(feed.episodes[0].enclosure?.url.absoluteString == "https://messy.example.com/a%20b.mp3")
        #expect(feed.episodes[1].publishedAt == nil && feed.episodes[1].durationMs == nil)
        #expect(feed.episodes[1].enclosure?.url.absoluteString == "https://messy.example.com/2.mp3" && feed.episodes[1].enclosure?.length == 77)
        #expect(feed.episodes[2].publishedAt == date("2026-10-01T00:00:00Z") && feed.episodes[2].durationMs == 90_500)
        #expect(feed.episodes[2].id == "https://messy.example.com/3.mp3")
        #expect(feed.episodes[3].enclosure == nil && feed.episodes[3].id == "https://messy.example.com/post")
    }

    @Test("an HTML page or an OPML file is not a feed")
    func notFeeds() throws {
        #expect(throws: FeedError.notAFeed) { try FeedParser.parse(try fixture("notafeed.html")) }
        #expect(throws: FeedError.notAFeed) { try FeedParser.parse(try fixture("opml-not-feed.xml")) }
        #expect(throws: (any Error).self) { try FeedParser.parse(Data("not xml at all".utf8)) }
    }
}

@Suite("Feed values")
struct FeedValuesTests {
    @Test("durations in every form; junk is nil", arguments: [
        ("1:02:03", Int64(3_723_000)), ("62:03", 3_723_000), ("3723", 3_723_000), ("3723.5", 3_723_500), ("1:2:3", 3_723_000), ("00:45", 45_000),
    ])
    func durations(text: String, ms: Int64) {
        #expect(FeedValues.durationMs(text) == ms)
    }

    @Test("not durations")
    func notDurations() {
        for text in ["", "0", "abc", "-5", "1:2:3:4", "9999999"] { #expect(FeedValues.durationMs(text) == nil, "\(text)") }
    }

    @Test("dates as feeds write them", arguments: [
        ("Fri, 16 Oct 2026 08:00:00 GMT", "2026-10-16T08:00:00Z"),
        ("16 Oct 2026 08:00:00 +0000", "2026-10-16T08:00:00Z"),
        ("Fri, 16 Oct 2026 08:00:00 UT", "2026-10-16T08:00:00Z"),
        ("Fri, 16 Oct 2026 10:00:00 CEST", "2026-10-16T08:00:00Z"),
        ("Friday, 16 October 2026 08:00:00 +0000", "2026-10-16T08:00:00Z"),
        ("2026-10-16T08:00:00Z", "2026-10-16T08:00:00Z"),
        ("2026-10-16 08:00:00 +0000", "2026-10-16T08:00:00Z"),
    ])
    func dates(text: String, iso: String) {
        #expect(FeedValues.date(text) == date(iso), "\(text)")
    }

    @Test("HTML notes become text with paragraphs and entities decoded")
    func html() {
        #expect(HTMLText.plain("<p>One</p><p>Two<br/>three</p>") == "One\n\nTwo\nthree")
        #expect(HTMLText.plain("A &amp; B &#x2014; C &#8211; D&nbsp;E") == "A & B — C – D E")
        #expect(HTMLText.plain("<script>x()</script><style>p{}</style>Only this") == "Only this")
        #expect(HTMLText.plain("no markup,   just   spaces") == "no markup, just spaces")
        #expect(HTMLText.decodeEntities("AT&T &unknown; &") == "AT&T &unknown; &")
    }
}

@Suite("Chapters")
struct ChaptersTests {
    @Test("a Podcasting 2.0 chapters document, sorted and closed, toc kept")
    func document() throws {
        let chapters = try Chapters.parse(try fixture("chapters.json"))
        #expect(chapters.map(\.title) == ["Cold open", "Sponsor", "Main", "Outro"])
        #expect(chapters.map(\.startMs) == [0, 95_500, 120_000, 900_000])
        #expect(chapters.map(\.endMs) == [95_500, 120_000, 900_000, nil])
        #expect(!chapters[1].isInTableOfContents && chapters[1].imageURL != nil)
        #expect(chapters[2].url == URL(string: "https://openair.example.net/main"))
    }
}

