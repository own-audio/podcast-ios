# App Store listing

Text per language (`en-US/`, `cs/`), in the store's fields, and `review_notes.txt` for App
Review. `scripts/app-store-upload.swift` sends it all (needs an App Store Connect API key, see the
script); screenshots will come from `AppStore/marketing/` once there are any.

Store details set in App Store Connect by hand:

- **Category:** Entertainment (there is no Podcasts category).
- **Age rating:** 4+ in the questionnaire (the app holds no content of its own; the listener
  chooses every show).
- **Price:** free, no in-app purchases.
- **App privacy:** Data Not Collected; see `PRIVACY.md`.
- **Privacy policy URL:** https://github.com/own-audio/podcast-ios/blob/main/PRIVACY.md
- **Support URL:** https://github.com/own-audio/podcast-ios/issues
- **Marketing URL:** https://www.own.audio

Limits: name and subtitle 30 characters, keywords 100, promotional text 170, description 4000.

Left out of the description until they ship: downloads and offline mode (P7), the queue (P8),
OPML (P9), the family and translations (P10), CarPlay and the widget (P11), transcripts.
