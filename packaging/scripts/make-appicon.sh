#!/usr/bin/env bash
# Convert icon.svg into AppIcon.appiconset PNGs.
# Uses qlmanage (built-in to macOS) — no external deps.
set -euo pipefail

SVG="${1:-icon.svg}"
OUT="${2:-App/Assets.xcassets/AppIcon.appiconset}"

if [[ ! -f "$SVG" ]]; then
  echo "error: $SVG not found" >&2
  exit 1
fi

mkdir -p "$OUT"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

declare -a SIZES=(16 32 64 128 256 512 1024)
for s in "${SIZES[@]}"; do
  qlmanage -t -s "$s" -o "$TMP" "$SVG" >/dev/null 2>&1
  base=$(basename "$SVG")
  mv "$TMP/${base}.png" "$OUT/icon_${s}.png"
done

echo "Wrote PNGs to $OUT"
ls -1 "$OUT"
