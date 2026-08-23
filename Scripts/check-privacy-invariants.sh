#!/bin/bash
set -euo pipefail

models="Packages/WatchioCore/Sources/WatchioModels/WatchioModels.swift"
persisted_shape="$(sed -n '/public struct DetectedService:/,/public enum InventorySource:/p' "$models")"

if rg -i 'environment|command(line)?|arguments|executablePath|rootPath|prompt|response|conversation|transcript|session(title|name)|task(title|name)' <<<"$persisted_shape"; then
  echo "error: a sensitive field entered a persisted snapshot model" >&2
  exit 1
fi

if rg -n 'URLSession|NSURLConnection|NWConnection' WatchioApp WatchioWidget WatchioSharedUI Packages/WatchioCore/Sources; then
  echo "error: outbound networking API found in Watchio production sources" >&2
  exit 1
fi

if rg -n 'ProcessInfo\.processInfo\.environment' Packages/WatchioCore/Sources/WatchioModels Packages/WatchioCore/Sources/WatchioStorage; then
  echo "error: persisted layers must never read environment values" >&2
  exit 1
fi

echo "Privacy invariants passed."
