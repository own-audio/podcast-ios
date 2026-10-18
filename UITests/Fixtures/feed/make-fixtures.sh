#!/usr/bin/env bash
# Makes the three short test episodes with macOS's speech synthesizer. Run in this folder.
set -euo pipefail
for i in 1 2 3; do
  say -o "ep$i.aiff" "This is test episode $i of the own audio podcast fixtures. It is short on purpose, so a test can play it to the end and see what plays next. One, two, three, four, five."
  afconvert -f m4af -d aac -b 32000 "ep$i.aiff" "ep$i.m4a"
  rm "ep$i.aiff"
done
