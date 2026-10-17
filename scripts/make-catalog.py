# Generates App/OwnAudioPodcasts/Localizable.xcstrings and InfoPlist.xcstrings from the table below:
# English keys (as the code has them; list them with `xcodebuild -exportLocalizations`) and their
# Czech. Run from the repository root: python3 scripts/make-catalog.py

import json
cs = {
 "Adding shows comes next.": "Přidávání pořadů přijde vzápětí.",
 "Free and open source · MPL-2.0": "Svobodný software s otevřeným kódem · MPL-2.0",
 "Your podcasts. No account, no server needed.": "Vaše podcasty. Bez účtu, bez serveru.",
}
# Plural keys: en variations (one/other) and cs (one/few/many/other).
plurals = {
}
def unit(v): return {"stringUnit": {"state": "translated", "value": v}}
strings = {}
for key, value in cs.items():
    strings[key] = {"localizations": {"cs": unit(value)}}
    if key in ("own.audio", "Audiobookshelf"): strings[key]["shouldTranslate"] = False
for key, forms in plurals.items():
    strings[key] = {"localizations": {lang: {"variations": {"plural": {k: unit(v) for k, v in f.items()}}} for lang, f in forms.items()}}
catalog = {"sourceLanguage": "en", "strings": dict(sorted(strings.items())), "version": "1.0"}
json.dump(catalog, open("App/OwnAudioPodcasts/Localizable.xcstrings", "w"), ensure_ascii=False, indent=2)
info = {"sourceLanguage": "en", "version": "1.0", "strings": {
    "CFBundleDisplayName": {"localizations": {"en": unit("own.podcast"), "cs": unit("own.podcast")}},
    "CFBundleName": {"localizations": {"en": unit("own.podcast"), "cs": unit("own.podcast")}},
    "NSLocalNetworkUsageDescription": {"localizations": {"en": unit("Connects to the podcast server on your local network."), "cs": unit("Připojuje se k podcastovému serveru ve vaší místní síti.")}},
}}
json.dump(info, open("App/OwnAudioPodcasts/InfoPlist.xcstrings", "w"), ensure_ascii=False, indent=2)
print(len(strings), "keys")
