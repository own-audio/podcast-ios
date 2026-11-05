# App Store listing

Text per language (`en-US/`, `cs/`), in the store's fields; screenshots taken by
`scripts/app-store-screenshots.sh` from a server whose shows may be shown publicly, framed with
their captions (`captions.json`) by `scripts/marketing-screenshots.swift`.
`scripts/app-store-upload.swift` sends it all. The three apps' listings are made the same way,
so they read as one family: own.audio Music's is the model.

Store details that live in App Store Connect:

- **Category:** Entertainment (there is no Podcasts category).
- **Age rating:** 4+ in the questionnaire (the app holds no content of its own; the listener
  chooses every show).
- **Price:** free, no in-app purchases.
- **App privacy:** Data Not Collected; see `PRIVACY.md`.
- **Privacy policy URL:** https://github.com/own-audio/podcast-ios/blob/main/PRIVACY.md
- **Support URL:** https://github.com/own-audio/podcast-ios/issues
- **Marketing URL:** https://www.own.audio
- **Review notes:** `review_notes.txt`. Demo account: guest@demo.own.audio (the add-server
  form's "Try the Demo Library" signs in to it by itself).

Limits: name and subtitle 30 characters, keywords 100, promotional text 170, description 4000.

Left out of the description until they ship or have been tried: OPML, translations,
transcripts, and CarPlay (the entitlement is not granted for this app yet). Summaries are left
out too: they appear only on a server that offers them.
