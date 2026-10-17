# CLAUDE.md — podcast-ios

**own.audio Podcasts**: one open-source (MPL-2.0) native iOS podcast player — plain RSS feeds
with no server, and own.audio, Audiobookshelf and gPodder-API servers when you have one —
published by own.audio. The repository is public — write everything for strangers to read.

- Work phase by phase from `IMPLEMENTATION_PLAN.md`; tick phases there.
- Every change gets a `CHANGELOG.md` entry under `[Unreleased]`.
- **No own.audio internals**: no references to closed repositories, internal hosts, team IDs or
  credentials. Comments explain why, for an outside reader.
- own.audio is one source among the others, never a funnel. The app is complete with feeds
  alone; a server adds sync, a family and downloads kept on the server.
- **Keep it small** (the plan's principles): no third-party dependencies without a strong
  reason; feed parser and server clients by hand; system decoders only — no VLC/FFmpeg; no
  cross-platform frameworks. Check the app's size on every release.
- A feature a source lacks is hidden, not broken: the screens ask the source what it can do.
- **Never lose a position.** Every position change is written to disk before it is sent;
  anything that touches progress reporting is tested offline and with a dead server.
- Code copied from `own-audio/book-ios` and `own-audio/music-ios` keeps its file names; a fix
  there is ported here by hand and noted in the changelog.
- **English and Czech, always together.** Every user-facing string is a SwiftUI literal or
  `String(localized:)` (brand names `verbatim`), and every new key gets its Czech in
  `Localizable.xcstrings` in the same commit; counts use plural variations. The catalog is
  generated — keys from `xcodebuild -exportLocalizations`, Czech from the table in
  `scripts/make-catalog.py`; edit the table, not the JSON. Czech follows the family's glossary
  (feed = kanál, show = pořad, episode = epizoda, follow = odebírat, unsubscribe = Zrušit odběr).

## Build

```bash
xcodegen generate                       # after changing project.yml; the .xcodeproj is not committed
(cd Packages/FeedKit && swift test)             # RSS/Atom parsing against fixture feeds
(cd Packages/AudiobookshelfKit && swift test)   # live tests too with AUDIOBOOKSHELF_HOST/USERNAME/PASSWORD set
(cd Packages/OwnAudioKit && swift test)         # live tests too with OWNAUDIO_HOST/EMAIL/ACCOUNT_PASSWORD set
(cd Packages/GPodderKit && swift test)          # live tests too with GPODDER_HOST/USERNAME/PASSWORD set
(cd Packages/PodcastLibrary && swift test)
(cd Packages/PlayerEngine && swift test)        # plays generated fixtures through a real AVPlayer
xcodebuild -project OwnAudioPodcasts.xcodeproj -scheme OwnAudioPodcasts \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Editor shows "no such module" on code that builds? Run
`xcode-build-server config -project OwnAudioPodcasts.xcodeproj -scheme OwnAudioPodcasts`
(`buildServer.json` is gitignored).

## Tests against real servers

Credentials live in the gitignored `test-servers.local.env` (the variables are listed at the
top of `scripts/test-servers.sh`); never commit them. `scripts/test-servers.sh` runs the live
client tests and the UI tests against each source; `ONLY_TESTING=<test>` runs one UI test. Feed
tests run against fixture feeds in the repository and, with `FEED_URLS` set, against live ones.

## Release

TestFlight: `scripts/testflight.sh` (needs `DEVELOPMENT_TEAM` in the gitignored
`release.local.env` and the account signed in to Xcode). The Team ID stays out of `project.yml`
because the repo is public. App icons must have no alpha channel.

## Layout

- `App/OwnAudioPodcasts/` — the app.
- `Packages/FeedKit/` — RSS/Atom with the iTunes and Podcasting 2.0 namespaces, Foundation only.
- `Packages/AudiobookshelfKit/` — Audiobookshelf client, Foundation only.
- `Packages/OwnAudioKit/` — own.audio's own API (`/api/v2`), Foundation only.
- `Packages/GPodderKit/` — the gPodder API (subscriptions, episode actions), Foundation only.
- `Packages/ServerSupport/` — answer cache and offline switch.
- `Packages/PodcastLibrary/` — models, `PodcastSource`, the adapters, the local feed store,
  server store, addresses, sync.
- `Packages/PlayerEngine/` — `SpokenEngine` + `PlayerCore`; knows episodes by an opaque id,
  nothing about feeds or servers.
