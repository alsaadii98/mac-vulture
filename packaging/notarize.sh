#!/usr/bin/env bash
# Sign and notarize Mac Vulture.
# Usage: ./packaging/notarize.sh [--dry-run]
#
# Required env (or .env file):
#   DEVELOPER_ID      "Developer ID Application: Name (TEAMID)"
#   APPLE_ID          Apple ID email
#   APPLE_TEAM_ID     Apple Team ID
#   APP_PASSWORD      App-specific password
set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Mac Vulture.app"
DMG="$ROOT/build/MacVulture-$(git -C "$ROOT" describe --tags --always 2>/dev/null || echo dev).dmg"

if [[ ! -d "$APP" ]]; then
  echo "error: $APP not found. Build first." >&2
  exit 1
fi

if $DRY_RUN; then
  echo "[dry-run] codesign --deep --force -s - --entitlements packaging/entitlements.plist \"$APP\""
  echo "[dry-run] hdiutil create -volname 'Mac Vulture' -srcfolder \"$APP\" -ov -format UDZO \"$DMG\""
  exit 0
fi

: "${DEVELOPER_ID:?set DEVELOPER_ID}"
: "${APPLE_ID:?set APPLE_ID}"
: "${APPLE_TEAM_ID:?set APPLE_TEAM_ID}"
: "${APP_PASSWORD:?set APP_PASSWORD}"

echo "==> Signing"
codesign --deep --force --options runtime --timestamp \
  --sign "$DEVELOPER_ID" \
  --entitlements "$ROOT/packaging/entitlements.plist" \
  "$APP"

echo "==> Building DMG"
mkdir -p "$ROOT/build"
hdiutil create -volname "Mac Vulture" -srcfolder "$APP" -ov -format UDZO "$DMG"

echo "==> Notarizing"
xcrun notarytool submit "$DMG" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APP_PASSWORD" \
  --wait

echo "==> Stapling"
xcrun stapler staple "$DMG"

shasum -a 256 "$DMG"
echo "==> Done: $DMG"
