# own.audio Podcasts

A native iPhone and iPad podcast player that needs no account and no server: add feeds and
listen. When you do run a server — **own.audio**, **Audiobookshelf** or anything that speaks
the **gPodder** API (podfetch, gpodder.net, own.audio) — your shows, episodes and positions follow you
between devices. Swift and SwiftUI, no web views, no third-party dependencies — a few
megabytes.

In development; the plan is in [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md).

- Opens on what is new: unplayed episodes across your shows, newest first
- Speed with pitch correction (per show too), chapters, skip buttons, smart rewind, skip the
  intro, sleep timer
- Downloads with rules per show (the newest few, delete when played, keep at most), a storage
  limit, and an Offline Mode; the player on the lock screen
- Search Apple's podcast directory and follow by feed address
- Several servers at once, each reached at the fastest of its addresses; iPad
- With own.audio: summaries of an episode, and questions about it
- English and Czech

Coming, in the order of the plan: a queue, OPML import and
export, CarPlay, a widget, and with own.audio a family library and translated episodes.

Made by [own.audio](https://www.own.audio). Free, no account needed, no tracking.

## Build

Developed with Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen); runs on iOS 18
and later.

```bash
brew install xcodegen
xcodegen generate
open OwnAudioPodcasts.xcodeproj
```

## Licence

[MPL-2.0](LICENSE). own.audio's name and logo are own.audio's; a fork uses its own.

Other servers are marked with the icon each one serves itself, loaded from the listener's own
server while the app runs, as a browser shows a site's icon; the app ships no other project's
artwork. Audiobookshelf's and gPodder's logos are GPL-licensed and podfetch's Apache-licensed,
and their names are their projects' own.
