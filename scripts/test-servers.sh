#!/usr/bin/env bash
# Builds the app and runs the UI tests on a simulator, then each package's tests. The live
# tests against real servers join as their phases arrive; their variables will be listed here
# and read from the gitignored test-servers.local.env.
#
# Usage: scripts/test-servers.sh            (SIMULATOR_ID=<udid> to pick a simulator)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${TEST_OUTPUT:-/tmp/podcast-ios-tests}"
mkdir -p "$OUT"
[[ -f test-servers.local.env ]] && source ./test-servers.local.env
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
