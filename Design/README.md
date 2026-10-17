# Design

`AppIcon.svg` and `AppIcon-dark.svg` are the app icon: the own.audio family ring (the same five
dancers as the other apps) with a microphone in the podcast blue (`#0A6E9C` light, `#29ABE2`
dark — the `AccentColor` and the podcast dancer of the own.audio mark). `node
scripts/render-icons.mjs` renders them into the asset catalog without alpha; it needs `sharp`.

The own.audio name, mark and hero artwork are own.audio's; a fork uses its own.
