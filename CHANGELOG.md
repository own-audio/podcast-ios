# Changelog

All notable changes to own.audio Podcasts. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed on iOS 27

- The Discover tab had no search field on iOS 27: iOS no longer put the field into the tab by
  itself, so there was nothing to type into. Selecting the tab now opens the field, with the
  keyboard (`tabViewSearchActivation(.searchTabSelection)`), on iOS 26 as well.

- UI test fix: the rename alert's Save could be missed right after typing on iOS 27; the test
  waits for it.

### Settings the same in all three apps

- Settings matches the books and music apps: On Mobile Data under Streaming; About with
  Version, Source Code and Licence, Privacy and Logs (in the links' colour) and the same footer;
  a large title.
- Czech: "Odebrat" for Remove, "Odebrat ‹name›?" for removing a server, "Přihlásit se znovu"
  for Sign In Again, as in the other apps.

### Added

- Discover (the Search tab, renamed): following by address, "More Like Your Shows", and categories
  to browse. With an own.audio server that has the podcast catalogue (a self-hosted Podcast Index
  mirror behind its metadata service), the categories carry how many shows still publish in each,
  a category lists its shows a page at a time, search asks the server, and suggestions come from
  shows like the ones you follow — each saying which one brought it up, from what you follow and
  never from what you play; nothing typed leaves the server, and what the household follows is left
  out. Without such a server (none at all, or one without the metadata service), the categories are
  Apple's podcast genres, each opening Apple's top shows in your country, and search is Apple's;
  there are no suggestions, since Apple doesn't publish which shows are alike.
- Similar Shows under a show's page and a found show's page, where the catalogue knows them.
- Category tiles carry no list chevron; Add a Show points to Discover for finding a show by name.
- `ShowCatalogue` in PodcastLibrary with two catalogues, `OwnAudioShowCatalogue`
  (`/api/v1/podcasts/discover/*`, `/podcasts/search` in OwnAudioKit) and `AppleShowCatalogue`
  (genre charts, one lookup per page for the feed addresses), with tests; a live test against a
  server with the catalogue (`CATALOGUE_*`).
- UI tests (`DiscoveryTests`): Apple's genres, a chart and a show to follow with no server; counted
  categories, suggestions, a category's shows and the server's search with the catalogue.

- Settings → Logs: what the app logged since it started (failed requests, playback trouble,
  sync), to read and to share as a text file with a bug report. Read on the phone from the
  system's log store; nothing is sent anywhere unless shared. UI test.
- Background refresh: iOS may wake the app about once an hour to ask feeds and servers for new
  episodes, so New Episodes is current when it opens and a show's download rule can fetch the
  newest on Wi-Fi. iOS decides whether it runs; it can't be started from a test.

### Fixed

- The player's tools share the row's width: with chapters there are five, and at fixed gaps they
  were wider than an iPhone.

- The app no longer registers the `pcast://` scheme, which App Store Connect refuses as reserved;
  `feed://` and `podcast://` links still open Add a Feed.

- Show pictures from an own.audio server were missing in the Shows grid. Pictures now load through
  `ArtworkLoader` (memory and disk, at the size drawn, keyed without own.audio's weekly-changing
  signature) instead of SwiftUI's `AsyncImage`, which inside a resizing grid could cancel its own
  load and never try again, and kept nothing for offline. Pictures seen once show offline too.
- The Shows grid lines up at the top of each row: a one-line title no longer pushes its tile down.

- The README lists the queue, CarPlay, the widget, the Live Activity and Siri, which now ship.
- The Audiobookshelf and own.audio clients logged under the books app's name
  (`audio.own.bookplayer`, from the copy); they log as this app now.

- Up Next (P8): one queue across every source, kept on the phone with each episode and its show,
  so it lists and plays offline (`UpNext`, with tests). Play Next and Play Later from an episode's
  menu and its page; a mark on queued rows; the Up Next sheet from the player to play one now,
  reorder, swipe away or clear. When an episode ends the next in Up Next plays, then the newest new
  episode (Settings → Play New Episodes After Up Next, on by default). A show can add its new
  episodes to Up Next as they arrive (Show Settings); the back catalogue never floods in.
- Search finds your own shows and episodes too — New Episodes, downloads and Up Next — before
  Apple's directory, and with no network.
- The Shows tab sorts by title, new episodes first, or recently followed (remembered); a show's
  episodes filter to all, unplayed or downloaded.
- On iPad the tabs are a sidebar that can be shown or hidden; the iPhone keeps its tab bar.
- UI tests (`LibraryFlowTests`, `IPadTests`): Up Next on a local fixture feed of three 12-second
  episodes (served with byte ranges by `UITests/Fixtures/serve.py` from `scripts/test-servers.sh`,
  so playing to the end takes seconds and asks no publisher); own shows found offline; sort and
  filter; the iPad sidebar with the mini player.

### Fixed

- UI tests launch through `launchChecked()`, which makes sure the app got its arguments: iOS can
  hand a test a prewarmed copy of the app, started without them — in the device's language and
  without `-uiTestReset`. Playback, download and Up Next settings are reset on `-uiTestReset` too,
  so one test's Offline Mode no longer leaks into the next.

- The Up Next widget (small: one episode; medium: three): the episode in the player, then the
  ones under way, then the newest new episodes, with pictures and time left. It reads a snapshot
  the app writes into the App Group `group.audio.own.podcastplayer`; a tap plays the episode.
  Copied from the books app's Continue Listening widget.
- The Live Activity on the lock screen and in the Dynamic Island while an episode plays: picture,
  title, chapter, progress, time left, and back / play-pause / forward buttons that work without
  opening the app. Unlike the books app's, the skip icons follow the chosen intervals.
- Siri and Shortcuts: "Continue listening in own.podcast" (the episode in the player, else the last
  one, else one under way, else the newest) and "Play ‹show› in own.podcast", in English and Czech.
- Links into the app: `ownpodcast://play/<episode>` from the widget and the Live Activity;
  `feed://`, `podcast://` and `pcast://` from web pages and other apps open Add a Feed with the
  address filled in.
- CarPlay: New Episodes, Downloads and Shows, with pictures and progress; the system's Now Playing
  with a speed button and the chapters behind Up Next. Copied from the books app. The CarPlay
  entitlement is set for simulator builds only until Apple grants it for this app; device and
  TestFlight builds sign without it.
- UI tests (`PlatformTests`): a `feed://` link opens Add a Feed filled in and follows; a play link
  reaches the app. The widget, the Live Activity, Siri and CarPlay need a device to try.

- Family and Devices on an own.audio server's page, copied from the books app: the household's
  members (you first), its storage by kind and its prepaid credit; admins invite with a code, a QR
  code or the share sheet and can withdraw an invitation; Join Another Family with a code. Devices
  lists every device signed in to the account, this iPhone first; swipe to sign one out, or Sign
  Out Everywhere. `HouseholdSource` in PodcastLibrary, with live tests.
- Live updates from own.audio: while the app is on screen and online, each own.audio server's
  `/events` stream is followed and a change reads the lists again, so a position or a show changed
  on another device shows here without pulling to refresh. Reopened with a growing wait when the
  connection ends; stopped in the background, in Offline Mode and in Low Data Mode. Live test: a
  change on the server comes through the stream within seconds.
- UI test: the server page leads to Family (you among the members) and Devices (this device marked).

- The last episode comes back after a relaunch: in the mini player, paused where it was, also when
  iOS ended the app in the background. Stop and the end of an episode clear it; offline, an episode
  that isn't downloaded is left out quietly. UI test: played, paused, killed, started again.
- An AirPlay button among the player's tools (`AirPlayRouteButton`, copied from the music app,
  coloured for a player that follows light and dark).
- Chapters read from the audio file itself (an MP3's ID3 chapter frames, an M4A's chapter track)
  when the feed has none, as the books app does — from a download at once, from a stream within
  six seconds or not at all.

- Positions meant for a server wait on disk until the server has them (`PendingProgress`, copied
  from the books app, with tests): listening offline, a dead server or a killed app no longer loses
  where you got to. They are sent oldest first on every refresh — at launch, when the network comes
  back, when Offline Mode is turned off. Marking a server's episode played or unplayed goes the same
  way, so it works offline too instead of showing an error. UI test: an own.audio episode played
  offline from its download is resumed at that position on a fresh install.

- Downloads (P7), on the books app's `DownloadManager`: an episode downloads from its page (the
  arrow beside Play: a ring while it comes, a check when it is here) or from a row's menu, on a
  background `URLSession` that goes on when the app is in the background or killed. Files live in
  Application Support, out of iCloud backup, with an extension read from their bytes.
- The Downloads tab lists every downloaded episode, newest first, grouped by source when there is
  more than one, each row saying where it came from ("Removed server" once the server is gone);
  play, open or swipe to remove; Retry N Failed; Remove All with the total size.
- Rules per show (Show Settings → Downloads): Download New Episodes (the newest 1, 3, 5 or 10,
  unplayed only — never the back catalogue), Delete When Played, Keep at Most N. They run after
  every refresh, after a show's settings change and when an episode is played; new downloads count
  against the limit, and the episode playing is never removed (`DownloadRules`, with tests).
- Settings → Downloads (with the total size), Offline Mode, Download on Wi-Fi Only (on by default)
  and Keep at Most (no limit, 1, 2, 5, 10 GB): over the limit, played episodes go first, then the
  ones not played for longest, never the one playing (`EvictionPolicy`, copied from the books app).
- On Mobile Data: Stream or Downloaded Only. The books app's third choice, Saver, needs a server that
  makes a smaller stream; a feed has one file per episode.
- Offline, episodes that aren't on the phone are greyed out and say so when played; downloaded
  ones play from the phone, from any source.
- The listening cache: an episode streamed on Wi-Fi is fetched into a 1 GB cache 45 seconds after
  it starts, so seeking back and listening again read the disk. Not on mobile data or in Low Data
  Mode, and never a transcode.
- Unfollowing a show or removing a server removes its downloads.
- UI tests (`DownloadFlowTests`): download, list with its source, play in Offline Mode and remove;
  a show's rule downloads only its newest episode; a download finishes after the app is killed;
  the downloads settings are there, Wi-Fi Only on by default.

- The "own.audio canary (testing)" button in Add a Server, under the address, in TestFlight and
  development builds only (`TestServers.swift`, copied from the books app).

### Changed

- Speed presets are those of the books app: 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3 in the player, and
  0.75–2× in Settings and Show Settings.
- Unfollow is offered only for this iPhone's shows. own.audio has no unfollow for players yet,
  and on Audiobookshelf it would delete the show for everyone, so the menu no longer shows an
  action that ends in an error.
- The README lists what the app does today; downloads, the queue, OPML, CarPlay, the widget and
  the family library are listed as coming.
- UI tests: the player offers the books app's presets; Add a Server shows the canary button in a
  development build; a server's show has no Unfollow while this iPhone's has.

- Your questions about an episode and their answers are kept on the own.audio server, for you alone,
  and come back when you open the episode again; Clear Questions deletes them.
- Summaries in three lengths (short, medium, long), and the price under each summary and answer.
  Questions can be asked before any summary is made.
- Summarize this episode, and ask questions about it, on an own.audio server that offers summaries
  (`features.summaries`, `/api/v2/summaries`). Shown on an episode with a transcript; paid from the
  family's credit, and a summary once made is kept for the whole family.
- A refused Apple or Google sign-in says the server didn't accept it, not that a password is wrong.
- An own.audio console address (`app-canary.own.audio`) typed into Add a Server reaches its server
  (`api-canary.own.audio`), so sign-in and the Apple and Google buttons work with it.
- Sign in with Apple and Google to an own.audio server, copied from the books app: the buttons show
  under the address when the server takes them (`/api/v1/server` → `features.auth`), the provider's
  token goes to the server, a second factor asks for the code as with a password, and the account's
  email is read back for the server list. Google through the system's web sign-in sheet with PKCE
  and this app's own iOS client; no Google SDK. UI test: canary shows both, a non-own.audio address
  neither.
- The App Store listing in English and Czech (`AppStore/`), review notes, and `scripts/app-store-upload.swift`
  to send it, ported from the books app; the review-notes update is skipped, not fatal, until the review
  contact is filled in. First TestFlight build (22) under `audio.own.podcastplayer`.

- The repository: licence, the plan (`IMPLEMENTATION_PLAN.md`), the agent contract (`CLAUDE.md`).
- The skeleton (P0): the app (`audio.own.podcastplayer`, "own.podcast") launching to a first
  screen in English and Czech; the podcast blue as the accent; the icon (the own.audio family
  ring with a microphone); the player engine, the own.audio and Audiobookshelf clients and the
  answer cache copied from own.audio Books, with their tests; the catalog, icon, test and
  TestFlight scripts; `PRIVACY.md`.
- FeedKit (P1): RSS 2.0, RSS 1.0 and Atom feeds with the iTunes and Podcasting 2.0 namespaces —
  show and episodes, enclosures, durations and dates in the forms found in the wild, HTML notes
  as text, inline (Podlove) and linked (JSON) chapters, transcripts, people, funding; mis-decoded
  text repaired, bare ampersands tolerated; conditional fetching with ETag and Last-Modified.
- PodcastLibrary (P2): shows, episodes, positions and the source protocol; the phone's own feed
  library — follow by URL, refresh four feeds at a time and conditionally, New Episodes, a queue
  with play next / play later that falls back to the inbox, auto-queue per show, positions where
  the newer wins and the end counts as heard — all kept on disk as it changes.
- Audiobookshelf podcast libraries (P3): shows, their episodes on the server plus the feed's
  others, New Episodes from the server's recent episodes, the server's files with a token,
  positions where the newer of phone and server wins, search through the server, and
  subscribing for accounts that may upload.
- own.audio servers (P4): the household's podcasts and episodes through `/api/v2`, New
  Episodes, positions that follow you between devices (the newer wins on the server too), and
  the server's signed streams.
- The plan's "Lessons from the other apps": what the music and books apps learned, checked in
  every phase.
- gPodder sync (P5): a client for the gPodder API as podfetch, gpodder.net and own.audio
  serve it, and a sync that keeps the phone's feeds and the account's subscriptions in step both
  ways and exchanges positions and played marks as episode actions, the newer one winning.
- The app (P6, first part): New Episodes, Shows, Downloads and Search tabs; onboarding with
  show search (Apple's podcast directory), a feed address, or a server; show and episode pages;
  the player with speed, sleep timer and chapters; Settings; own.audio, Audiobookshelf and
  gPodder accounts; Czech throughout. The player takes an episode's length from the file when
  the feed has none.
- own.audio episodes play: the server streams them from an address with no extension as
  `application/octet-stream`, so the player now tells AVPlayer the episode's type.
- The misuse suite and the large-text pass; at accessibility text sizes episode rows stack
  their words under the picture and the player's picture shrinks so the controls stay on screen.
- gPodder sync tested against the open-source own.audio server's new gPodder API: a show
  unfollowed on the phone stays unfollowed when a server repeats its earlier "add", and live tests
  cover subscriptions and positions both ways and the app's own sync end to end.
- Adding a server finds out what it is: own.audio, Audiobookshelf, or a gPodder sync server
  such as podfetch, from the address alone (*Automatic*, the new default; the kind can still be
  chosen). podfetch's refusal of its admin account says what to do.
- gPodder sync works with podfetch: the account's subscriptions from every device arrive (podfetch
  keeps lists per device), a wrong password is refused even after a right one (no session cookie
  is kept), a position another app wrote into a row this phone created is taken, and a
  read-only account still syncs down.
- Titles from Audiobookshelf and own.audio show HTML entities decoded ("I'm", not "I&#39;m").
- A source switch on New Episodes, as the books and music apps switch servers on Home: all
  sources together, this iPhone's shows, or one server's; Shows follows it, and new shows go to
  the source on the switch when it takes them.
- A page for each server in Settings, as in the music app: whether it answers and accepts the
  sign-in (Check Now), signing in again, its kind, version and name, Sync Now for a gPodder
  account, and its addresses — the one it was added with, those an own.audio server names, and
  any added by hand — used automatically (the fastest that answers on each network) or fixed.
- Server logos, as in the music app: the source switch on New Episodes lists each source with its
  logo and name, and Settings and each server's page show them too. own.audio's mark (the violet
  core with the family) ships with the app; every other server shows the icon it serves itself,
  loaded from the listener's own server and kept for offline use, so the app carries no other
  project's artwork (Audiobookshelf's and gPodder's are GPL, podfetch's Apache).
- own.audio servers come first, in the switch, in Settings and in Shows.
- Audiobookshelf episodes in a format the phone can't play (WebM/Opus from YouTube downloads,
  Ogg) play through the server's transcoder (an HLS play session) instead of failing with
  "Cannot Open"; a failed open logs what the server answered.
- gPodder accounts (podfetch) are in the source switch too: choosing one shows this iPhone's shows
  that are on the account.
- Audiobookshelf libraries: with more than one podcast library, each is in the source switch on its
  own after the server; the server page lists them with a switch each, and one turned off leaves
  New Episodes, Shows and the switch; a show added to the server goes into the library chosen.
- Transcoded Audiobookshelf streams wait until the server has written the playlist and its first
  segment, instead of failing on the 404 the server answers at first.
