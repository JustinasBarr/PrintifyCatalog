#!/bin/bash
# Formats or checks every Swift file with the swift-format that ships with Xcode (no install).
#   scripts/format.sh          rewrite files in place
#   scripts/format.sh --check  fail on any difference (run before each commit)
set -euo pipefail
cd "$(dirname "$0")/.."
paths=(Packages/CatalogKit/Sources Packages/CatalogKit/Tests CatalogApp CatalogUITests)
if [[ "${1:-}" == "--check" ]]; then
    xcrun swift-format lint --strict --recursive --parallel "${paths[@]}"
else
    xcrun swift-format format --in-place --recursive --parallel "${paths[@]}"
fi
