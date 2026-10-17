#!/usr/bin/env bash
# Runs each package's tests (the live ones too where their variables are set), then the UI
# tests on a simulator. Variables come from the gitignored test-servers.local.env:
#
#   FEED_URLS="https://… https://…"     # real feeds FeedKit's live test fetches and parses
#   AUDIOBOOKSHELF_HOST=http://…:13378   # an Audiobookshelf with a podcast library, and a
#   AUDIOBOOKSHELF_USERNAME=…            # throwaway user: the tests play episodes and write
#   AUDIOBOOKSHELF_PASSWORD=…            # positions, then put them back
#   OWNAUDIO_HOST=https://…              # an own.audio server with podcasts (the public demo
#   OWNAUDIO_EMAIL=…                     # has some); positions are written and put back
#   OWNAUDIO_ACCOUNT_PASSWORD=…
#
# The servers' variables join as their phases arrive.
#
# Usage: scripts/test-servers.sh            (SIMULATOR_ID=<udid> to pick a simulator)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${TEST_OUTPUT:-/tmp/podcast-ios-tests}"
mkdir -p "$OUT"
[[ -f test-servers.local.env ]] && { set -a; source ./test-servers.local.env; set +a; }
SIM="${SIMULATOR_ID:-$(xcrun simctl list devices booted | grep -m1 -oE '[0-9A-F-]{36}' || true)}"
if [[ -z "$SIM" ]]; then
  SIM=$(xcrun simctl list devices available | grep -m1 "iPhone" | grep -oE '[0-9A-F-]{36}')
  xcrun simctl boot "$SIM" >/dev/null 2>&1 || true
  sleep 10
fi
xcodegen generate >/dev/null
for package in Packages/*/; do
  echo "== $(basename "$package")"
  (cd "$package" && swift test 2>&1 | grep -E "✘|Test run" || true)
done
echo "== UI tests"
xcodebuild test -project OwnAudioPodcasts.xcodeproj -scheme OwnAudioPodcasts -destination "id=$SIM" \
  -derivedDataPath "$OUT/DerivedData" -resultBundlePath "$OUT/$(date +%Y%m%d-%H%M%S).xcresult" \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 420 2>&1 \
  | tee "$OUT/xcodebuild.log" | grep --line-buffered -E "Test Case .*(passed|failed)|: error: |\*\* TEST" || true
