#!/bin/bash
set -euo pipefail

package="Packages/WatchioCore"
swift test --package-path "$package" --enable-code-coverage
binary="$(find "$package/.build" -path '*WatchioCorePackageTests.xctest/Contents/MacOS/WatchioCorePackageTests' -type f | head -1)"
profile="$(find "$package/.build" -name default.profdata -type f | head -1)"

if [[ -z "$binary" || -z "$profile" ]]; then
  echo "error: SwiftPM coverage artifacts were not produced" >&2
  exit 1
fi

report="$(xcrun llvm-cov report "$binary" -instr-profile "$profile" -ignore-filename-regex='Tests|\.build')"
printf '%s\n' "$report"

line_coverage="$(awk '/^TOTAL/ { value = $10; sub(/%/, "", value); print value }' <<<"$report")"
if [[ -z "$line_coverage" ]] || ! awk "BEGIN { exit !($line_coverage >= 70) }"; then
  echo "error: line coverage ${line_coverage:-unknown}% is below the 70% floor" >&2
  exit 1
fi
