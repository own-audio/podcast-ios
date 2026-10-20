#!/usr/bin/env bash
# Takes the App Store screenshots on the store's required sizes, in English and Czech, from the
# public own.audio demo (the app's "Try the Demo Library" button; nothing private is shown).
#
# Usage: scripts/app-store-screenshots.sh   → AppStore/screenshots/<language>/<device>/
#        ONLY_DEVICE="iPhone 17 Pro Max" LANGUAGES=en scripts/app-store-screenshots.sh
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICES=("iPhone 17 Pro Max" "iPad Pro 13-inch (M5)")
[[ -n "${ONLY_DEVICE:-}" ]] && DEVICES=("$ONLY_DEVICE")
DERIVED="${TEST_OUTPUT:-/tmp/podcast-ios-tests}/DerivedData"

xcodegen generate >/dev/null
for device in "${DEVICES[@]}"; do
  id=$(xcrun simctl list devices available | grep -F "$device (" | head -1 | grep -oE '[0-9A-F-]{36}')
  xcrun simctl boot "$id" 2>/dev/null || true
  xcrun simctl status_bar "$id" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
  for language in ${LANGUAGES:-en cs}; do
    out="AppStore/screenshots/$language/$device"
    mkdir -p "$out"
    echo "== $device, $language"
    TEST_RUNNER_SCREENSHOT_DIR="$PWD/$out" TEST_RUNNER_SCREENSHOT_LANGUAGE="$language" \
      xcodebuild test -project OwnAudioPodcasts.xcodeproj -scheme OwnAudioPodcasts -destination "id=$id" \
        -derivedDataPath "$DERIVED" -only-testing:OwnAudioPodcastsUITests/AppStoreScreenshots \
        -test-timeouts-enabled YES -default-test-execution-time-allowance 600 2>&1 \
      | grep -E "Test Case.*(passed|failed)|\*\* TEST|error:"
  done
  xcrun simctl status_bar "$id" clear
done
