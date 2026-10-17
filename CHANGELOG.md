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
