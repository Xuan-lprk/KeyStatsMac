#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
OUTPUT="$ROOT/build/C3502/KeyStatsC3502Collector"
mkdir -p "$(dirname "$OUTPUT")"
swiftc -O -target "$(uname -m)-apple-macosx13.0" \
  "$ROOT/KeyStatsHelper/EventTapController.swift" \
  "$ROOT/KeyStatsHelper/PayloadBuilder.swift" \
  "$ROOT/KeyStatsHelper/HelperPayloadFields.swift" \
  "$ROOT/KeyStatsHelper/ButtonRoleClassifier.swift" \
  "$ROOT/KeyStatsHelper/SystemMediaKey.swift" \
  "$HERE/native/Aggregates.swift" "$HERE/native/main.swift" -o "$OUTPUT"
codesign --force --sign - --identifier com.xuanlprk.KeyStatsMac.c3502collector "$OUTPUT"
echo "$OUTPUT"
