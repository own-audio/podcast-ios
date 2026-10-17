# Changelog

All notable changes to own.audio Podcasts. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

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
