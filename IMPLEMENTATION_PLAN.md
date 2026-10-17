# Implementation plan

**own.audio Podcasts** — a native, open-source podcast player for iPhone and iPad. It is
complete on its own: add feeds and listen, no account, no server. With a server it keeps shows,
episodes and positions in step between devices: **own.audio**, **Audiobookshelf** podcast
libraries, and any server that speaks the **gPodder** API (podfetch, Nextcloud gPodder). Swift
6, SwiftUI, iOS 18+. MPL-2.0.

It is the third app in a family that began with own.audio Music (`own-audio/music-ios`) and
own.audio Books (`own-audio/book-ios`), built in the same shape: the same repository layout,
rules, test and release scripts. Code the books app already has — the spoken-audio player, the
own.audio API client, the Audiobookshelf client, the Keychain server store, address racing,
sign-in with Apple and Google, the Czech catalog pipeline, CarPlay, the widget and the Live
Activity — is copied here rather than shared through a package, so each app stays
self-contained and can be built from one checkout. Written 2026-10-17.

## Principles

- **No server needed.** The first screen asks for a feed, a show to search for, or an OPML
  file — not for a server. A server is an option under Settings that adds sync, a family
  library and server-side downloads. own.audio is one of those options, never a funnel.
- **An episode is not a book.** New episodes arrive every day and most are heard once: the
  app opens on what is new, keeps played and unplayed apart, has a queue, plays the inbox on
  by itself, and lets each show keep or drop its episodes by rule. Positions matter less than
  in a book but are kept with the same care.
- **Local player, server as the brain where there is one.** Feeds, episodes and artwork live on
  the phone; downloads play with no network; what you did offline — positions, played marks,
  subscriptions — is queued and sent when a server is back. Without a server, the phone *is*
  the brain, and sync is a matter of the gPodder API when the listener wants it.
- **Robust by default.** Automatic connection and quality choices, one visible setting for
  mobile data, a position saved every few seconds and never lost, feeds refreshed in the
  background and conditionally (ETag, Last-Modified) so a hundred shows cost a few kilobytes.
- **Small and native.** No third-party dependencies without a strong reason; the feed parser
  and the server clients written by hand; system decoders only (no VLC/FFmpeg); no
  cross-platform frameworks. Watch the app size on every release; the books app is 5.6 MB.

## Decisions

1. **The player is the books app's `SpokenEngine`**, copied: one `AVPlayer`, pitch-corrected
   speed, skip buttons, smart rewind, the sleep timer, chapters from the file when the feed has
   none, three minutes fetched ahead, "buffering" shown instead of gaps, a listening cache of
   what streams. An episode is a one-part book to it. Added here: a queue (decision 5) and
   per-show speed.
2. **Four sources, one `PodcastSource` protocol, capabilities per source.** *Feeds* (the phone
   fetches RSS itself; `FeedKit`), *own.audio* (`/api/v2`), *Audiobookshelf* (podcast
   libraries; the books app's kit, extended), and *gPodder* (not a catalogue but a sync layer on
   top of the feeds source: subscriptions and episode actions). The screens ask the source what
   it can do — search, downloads kept on the server, auto-download rules, a family — and hide
   the rest.
3. **Feeds are the baseline model.** Every source is mapped onto show + episodes as a feed
   would give them: title, artwork, description (HTML stripped), publication date, duration,
   enclosure (URL, type, length), GUID, season and episode numbers, chapters (Podcasting 2.0
   `podcast:chapters` JSON and PSC), transcripts (`podcast:transcript`), and `itunes:` tags.
   Servers add what feeds cannot: a position that follows you, a played state across devices,
   downloads kept server-side, a family.
4. **Opens on New Episodes**: unplayed episodes across all shows, newest first, with each show
   able to opt out ("don't show in the inbox") or in ("auto-add to the queue"). Shows is the
   second tab; Search the third. Settings behind a gear, as in the books app.
5. **A queue, kept on the phone.** Play next / play later from any episode row; the inbox plays
   on when the queue is empty, newest first; the queue survives a relaunch. No server has a
   podcast queue, so none syncs it (the gPodder API has no notion of one).
6. **Progress is written locally first, every time**, then sent: own.audio `PUT
   /me/progress/episode/{id}` or the offline batch; Audiobookshelf's episode progress and play
   sessions (`/api/items/{li}/play/{ep}` → `/sync` → `/close`, `local-all` after offline
   listening); gPodder as an episode action (`play` with `position`/`total`). Played and
   unplayed are part of the same record.
7. **Downloads with rules per show.** Manual per episode, and per show: download new episodes
   automatically (the last 1/3/5/10), delete when played, keep at most N; Wi-Fi only by
   default; a storage cap with the books app's eviction policy. On Audiobookshelf and own.audio
   the *server* can also keep episodes (auto-download / auto-store) — shown as the server's own
   setting where the source has it, not confused with the phone's downloads.
8. **Discovery without a key.** Search uses Apple's public iTunes Search API (no key, no
   account); the Podcast Index is an option for those who add their own key in Settings. A
   server with its own search (Audiobookshelf, own.audio) searches there too. OPML import and
   export from day one, because that is how people arrive from and leave for other apps.
9. **Episode translation** (hosted own.audio servers, paid from the family's credit) comes
   last, in the shape of the books app's narration: quote, start, follow the job, the
   translated episode appears as its own playable item. Its routes are still v1-shaped under
   `/api/v2`; server work may come first.
10. **Copied, not shared**, as in the books app; a fix in one app is ported by hand and the
    changelog says when. **Code from own.audio's earlier, closed podcast app** is used only
    where its author relicenses it under MPL-2.0 for this repository, and only logic independent
    of that app's server API (feed rules, inbox merging, the translation flow's shape). Nothing
    branded, nothing tied to v1.

## Lessons from the other apps

What the music and books apps learned the hard way, held here so no phase repeats it. Each
phase's review checks this list.

- **Streaming**: a long file is never decoded or fetched whole. The player keeps a few minutes
  ahead (`forwardBufferSecs`), shows "buffering" while the network catches up instead of
  playing gaps, and keeps what it streams on Wi-Fi in a capped listening cache that the engine
  asks first (`partLocator`). Copied with `SpokenEngine`; episodes use it as-is.
- **Positions**: written to disk before they are sent, merged per episode, sent oldest first
  when a server is back; the newer of phone and server wins; another device's newer position
  is asked about before playing ("Continue from …?"), never applied silently.
- **Stop lets go everywhere**: the model, the mini player, the widget and the Live Activity
  all release the episode, not only the engine.
- **The Live Activity's cover** travels in its updatable state, filled in when it has loaded;
  never fixed in the attributes at start.
- **Idempotent requests** send byte-identical bodies on retry: JSON keys sorted
  (`JSONEncoder.ownAudio`), the idempotency key kept with the queued request.
- **Tokens**: rotating refresh tokens refreshed single-flight; Audiobookshelf media links carry
  `?token=` and an item that answers 401 is recreated at the same position with a fresh one.
- **Feeds and servers send bad text**: Mojibake repaired at display, HTML stripped, durations
  read from the file when the source has none.
- **Downloads** have a file extension AVPlayer can read (from the bytes, not the URL), run on a
  background `URLSession` that survives a kill, and are kept apart from the listening cache.
- **Discovery is asked again** whenever clients are rebuilt — a server added or re-addressed
  after launch shows its modules (narration then, translation here) without a relaunch.
- **UI tests**: dismiss iOS's late "Save Password?" sheet before tapping; reach tabs through the
  hittable button (iOS 26 duplicates labels, iPad puts tabs on top); no endless animations under
  `-uiTestReset`; only one simulator run at a time; a simulator whose audio stops answering
  (`AQME … timed out`) needs CoreAudio restarted, not a code fix.
- **Czech with every string**, plurals as variations, the shared glossary's words; the check
  that every key has Czech runs before each commit.
- **Commits** carry no AI attribution lines.

## Layout

- `App/OwnAudioPodcasts/` — the app (bundle `audio.own.podcastplayer`, home screen
  "own.podcast", App Store name "own.audio Podcasts").
- `Packages/FeedKit/` — RSS 2.0 and Atom, `itunes:` and `podcast:` namespaces, conditional
  fetching, HTML to text, chapter and transcript documents. Foundation only; `XMLParser`.
- `Packages/AudiobookshelfKit/` — from the books app, with podcasts: libraries of
  `mediaType == "podcast"`, items, episodes, per-episode progress and sessions, subscribe by
  feed URL, the server's own search and auto-download settings.
- `Packages/OwnAudioKit/` — from the books app; podcasts, episodes, episode progress, the
  change feed's `podcast`/`episode` kinds, and the follow/add/refresh routes as v2 grows them.
- `Packages/GPodderKit/` — the gPodder API: login, devices, subscription changes, episode
  actions, with the timestamp bookkeeping sync needs.
- `Packages/ServerSupport/` — from the books app.
- `Packages/PodcastLibrary/` — models (show, episode, chapter, times in ms), `PodcastSource`
  and `Capabilities`, the four adapters, the local feed store, the inbox and queue logic, the
  sync queue, server store, addresses.
- `Packages/PlayerEngine/` — `SpokenEngine` + `PlayerCore`, from the books app.
- `Shared/` — the widget snapshot and the Live Activity attributes, from the books app.
- `Widgets/` — the widget extension, from the books app.
- `scripts/` — `test-servers.sh`, `testflight.sh`, `make-catalog.py`, `render-icons.mjs`,
  `app-store-upload.swift`, from the books app.

## The sources, side by side

| | Feeds (no server) | own.audio v2 | Audiobookshelf 2.x | gPodder API |
|---|---|---|---|---|
| Shows & episodes | the feed, fetched by the phone | `/podcasts`, `/podcasts/{id}/episodes`, `/episodes/{id}` | library items of a podcast library, `media.episodes` | subscriptions only; episodes from the feed |
| Follow / add by URL | local | **not in v2 yet** (v1 had it) | `POST /api/podcasts` with the feed URL | subscription change (`add`) |
| Search for shows | iTunes Search, Podcast Index (key) | **not in v2 yet** | `/api/search/podcast?term=` (iTunes through the server) | — |
| Refresh | conditional GET | server polls | `/api/podcasts/{id}/checknew` | — |
| Position & played | local | `/me/progress/episode/{id}`, offline batch | `/api/me/progress/{li}/{ep}`, play sessions | episode actions `play`, `position` |
| New-episodes inbox | from feeds, local | from the change feed | from items' episodes | — |
| Downloads | phone | phone; the server keeps files anyway | phone; server auto-download per show | — |
| Chapters | `podcast:chapters`, PSC, the file | the server's, else the file | the server's, else the file | — |
| Family / sharing | — | household, visibility | per-user libraries | — |
| Translation | — | hosted servers with the module | — | — |
| Sign-in | — | password, Apple, Google, two-factor | user/password, OIDC off | basic auth |

## What this app needs from the own.audio server

Worked out while writing the plan; each becomes a server issue when its phase starts.

- `/api/v2`: follow and unfollow a podcast, add one by feed URL, refresh now, the inbox or at
  least `episodes?since=`, per-show rules (auto-store, keep), episode search, discovery through
  the server. v1 had most of these; v2 stops at the catalogue, progress and the change feed.
- Translation routes in v2 shape (`/api/v2/translation/…`, bodies as v2 writes them).
- `playback-info` for an episode's file, as for a book file.

## Test servers

Nothing here names a host; the addresses and accounts live in the gitignored
`test-servers.local.env` (the variables are listed at the top of `scripts/test-servers.sh`).

- **Feeds**: a handful of real public feeds as fixtures in `Packages/FeedKit/Tests/Fixtures`
  (RSS with `itunes:` only; one with Podcasting 2.0 chapters and transcripts; one Atom; one
  with mis-encoded text; one with a `<![CDATA[` HTML description), refreshed by a script, and
  the live URLs behind `FEED_URLS` for an occasional check.
- **Audiobookshelf 2.37** with a podcast library of a few hundred shows (`AUDIOBOOKSHELF_*`),
  a throwaway user, since the tests play and write progress.
- **own.audio**: the public demo server (`OWNAUDIO_*`), once it carries podcasts; a hosted
  server with credit for translation (`TRANSLATION_*`), quoting only.
- **gPodder**: podfetch with `GPODDER_INTEGRATION_ENABLED` (`GPODDER_*`), basic auth.

## Phases

Each phase ends green: unit tests, the live tests against every source it touches, the UI
tests, a build of the app, `CHANGELOG.md`, then one commit and push.

- [x] **P0: Skeleton** (2026-10-17). The repository as the books app has it: `project.yml`
  (XcodeGen, Swift 6, iOS 18, the app, the UI tests; the widget extension and its App Group
  wait for P11, since they need the group registered with Apple), `Packages/ServerSupport`,
  `OwnAudioKit`, `PlayerEngine` (`SpokenEngine` + `PlayerCore`) copied, `AudiobookshelfKit`
  copied, the design tokens and brand (`OwnAudioMark`, wordmark, hero), the icon from the same
  construction with the podcast colour and a microphone, the Czech catalog pipeline, the
  scripts, `PRIVACY.md`. Builds and launches to a placeholder first screen; the launch test
  in English and Czech. The book-only parts of `OwnAudioKit` (uploads, narration) were left
  behind; `test-servers.sh` starts small and grows with the live tests.
- [x] **P1: FeedKit** (2026-10-17). `XMLParser`-based parsing of RSS 2.0 and Atom into `FeedDocument`
  (show + episodes), with `itunes:` (author, image, duration in every form, explicit, season,
  episode, type), `podcast:` (chapters, transcript, person, funding, guid), enclosure, GUID,
  `pubDate` in every form seen in the wild, HTML descriptions to text with paragraphs kept, and
  the lenient parts: bad dates, missing durations, mis-encoded text (the books app's Mojibake
  repair). Conditional fetching with ETag / Last-Modified and a cap on size. Chapter documents
  (`application/json+chapters`) and PSC parsed. Tests against the fixture feeds, byte for byte.
  Done with synthetic fixtures for every form (iTunes RSS, Podcasting 2.0, Atom, a messy feed,
  non-feeds) and a live test over six real feeds — a Czech one, 3 000 episodes, the Podcasting 2.0
  feed's chapter documents — all parsing. A bare `&` is repaired and the feed read again.
- [x] **P2: PodcastLibrary core** (2026-10-17). Models in episode-time milliseconds: `Show`, `Episode`,
  `Chapter`, `ListeningProgress` (position, played, updated), `PodcastSource` protocol with
  `Capabilities` (`search`, `addByURL`, `serverDownloads`, `familySharing`, `liveUpdates`,
  `changeFeed`, `translation`). The **feeds source**: a store on disk (JSON per show, episodes
  indexed, artwork cached), background refresh (`BGAppRefreshTask`, conditional, batched),
  the inbox query (unplayed, newest first, per-show opt-out), the queue (ordered episode ids,
  persisted), local progress. Unit tests for the inbox and queue rules; a live test fetching a
  real feed. Done as `FeedLibrary` (an actor; every change on disk before it returns). The inbox
  rule: unplayed, not dismissed, from shows that want it, and first seen after the follow — plus
  the one episode that was newest at the follow. A refresh keeps first-seen times, follows moved
  feeds, and keeps an episode the feed dropped only while it is half heard or queued. The newer
  position always wins; the last 30 s (or 2%) count as heard. Background refresh scheduling
  (`BGAppRefreshTask`) is the app's, in P6.
- [ ] **P3: Audiobookshelf podcasts.** Verify on a live 2.37 first: podcast libraries, items
  and `media.episodes` (ino, audio file, duration, publishedAt), per-episode progress
  (`/api/me/progress/{li}/{ep}`), sessions per episode, the file link with `?token=`,
  `POST /api/podcasts` (subscribe by feed URL, folder choice), `/api/search/podcast`,
  `checknew`, auto-download settings, and how deleted episodes look. Then the adapter, the
  live tests, and the books app's token refresh and Mojibake handling.
- [ ] **P4: own.audio v2.** The catalogue (`podcasts`, `episodes`), episode progress and the
  offline batch, playback-info for an episode file, the change feed with `podcast`,
  `episode`, `progress.episode` kinds and the catalogue on the phone, sign-in with password,
  Apple and Google and two-factor (copied). Follow / add / refresh / inbox as the server grows
  them — each hidden until discovery says it is there; the server list above becomes issues.
- [ ] **P5: gPodder sync.** `GPodderKit`: `POST /api/2/auth/{user}/login.json`, devices,
  `GET/POST /api/2/subscriptions/{user}/{device}.json` with `since`, `GET/POST
  /api/2/episodes/{user}.json` (actions `download`, `play` with `position`/`started`/`total`,
  `delete`, `new`), the timestamps kept per device. The sync layer applies subscriptions to the
  feeds source both ways and sends positions and played marks as actions; conflicts resolved by
  time. Live tests against podfetch; a UI test that a show added on the phone shows up on the
  server and one added on the server on the phone.
- [ ] **P6: The app.** Onboarding (add a feed, search a show, import OPML — or add a server),
  tabs New Episodes / Shows / Search, a show's page (episodes, rules, settings), the episode
  page (notes with links, chapters, transcript where there is one), the player (the books
  app's, with chapter and transcript sheets), the mini player, Now Playing, Settings
  (servers, downloads, playback, mobile data, about). Czech from the first screen. UI tests
  per source kind: add, play, seek, speed, chapters, sleep timer; the misuse suite and the
  large-text pass copied from the books app.
- [ ] **P7: Downloads and offline.** Per-episode downloads on the books app's background
  `URLSession`, the per-show rules of decision 7, delete-when-played, the storage cap and
  eviction, Offline Mode and the offline banner, the listening cache, the server's own
  auto-download setting surfaced where a source has it. Tests: a download survives a kill; the
  rules do what they say; offline shows and plays only what is on the phone.
- [ ] **P8: Queue and continuous play.** Play next / play later, the queue sheet with reorder
  and remove, the inbox playing on, "mark played" as episodes finish, skip-the-intro per show
  (a start offset), per-show speed. UI tests.
- [ ] **P9: Discovery and OPML.** iTunes Search (shows, by name; the feed URL from the lookup),
  the Podcast Index with the listener's own key, the server's search where there is one,
  trending/categories only where a source offers them. OPML import (Files app, share sheet)
  and export; subscribing to a feed URL typed or pasted; `podcast://`, `feed://` and
  `ownpodcast://` links.
- [ ] **P10: own.audio extras.** The family (shows shared with the household, members,
  invites — copied from the books app), server-side storing of episodes, and **translation**:
  on hosted servers with the module, quote an episode in a language, start, follow the job,
  play the translated episode (decision 9). Live tests against a hosted server, quoting only.
- [ ] **P11: Platform.** CarPlay (New Episodes, Queue, Shows, Now Playing with chapters), the
  widget (new episodes / up next), the Live Activity, Siri ("Play *show* in own.podcast",
  "What's new in own.podcast"), iPad split view — each copied from the books app and adapted.
- [ ] **P12: Polish, accessibility, tests, release.** Dynamic Type, VoiceOver labels, Reduce
  Motion, both colour schemes, the Czech re-read, performance with 300 shows and 20 000
  episodes, app size measured, screenshots from the UI test pipeline, App Store texts in
  English and Czech, TestFlight under `audio.own.podcastplayer`, then the App Store.

Later: Jellyfin and Plex podcast libraries, Podcasting 2.0 value and live items, a watchOS
companion.
