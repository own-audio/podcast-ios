# own.audio Podcasts

A native iPhone and iPad podcast player that needs no account and no server: add feeds and
listen. When you do run a server — **own.audio**, **Audiobookshelf** or anything that speaks
the **gPodder** API (podfetch, gpodder.net, own.audio) — your shows, episodes and positions follow you
between devices. Swift and SwiftUI, no web views, no third-party dependencies — a few
megabytes.

In development; the plan is in [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md).

- Opens on what is new: unplayed episodes across your shows, newest first
- Speed with pitch correction, chapters, skip buttons, smart rewind, sleep timer
- Downloads with rules per show (keep the last few, delete when played), and an offline mode
- A queue: play next, play later, and the inbox played on
- Search and add shows, import and export OPML
- Several servers at once; iPad; CarPlay; a widget; the player on the lock screen
- With own.audio: a family library, and episodes translated into your language
- English and Czech

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
