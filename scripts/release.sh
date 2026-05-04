#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
#  scripts/release.sh
#  Build, sign, notarize and copy Wired 3 (macOS client) to ~/Downloads.
#
#  Usage:
#    bash scripts/release.sh
#
#  Optional environment variables:
#    WIRED_MARKETING_VERSION  override marketing version  (default: from Xcode project)
#    WIRED_BUILD_NUMBER       override build number       (default: from Xcode project)
#    APPLE_SIGN_IDENTITY      codesign identity           (default: auto from keychain)
#    NOTARY_PROFILE           notarytool keychain profile (enables notarization)
#    NOTARIZE                 force notarization (1/true/yes; auto if NOTARY_PROFILE set)
# ─────────────────────────────────────────────────────────────────────────────

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCODEPROJ="$PROJECT_DIR/Wired-macOS.xcodeproj"
SCHEME="Wired 3"
BUILD_CONFIGURATION="Release"
BUNDLE_ID="fr.read-write.Wired3"
DIST_DIR="$PROJECT_DIR/dist"
ARCHIVE_PATH="$DIST_DIR/Wired3.xcarchive"
EXPORT_PATH="$DIST_DIR/export"
DOWNLOADS_DIR="$HOME/Downloads"
NOTARIZE="${NOTARIZE:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

# Auto-load notary profile from ~/.wired-notary if not set via environment.
# File format (shell-sourceable):  NOTARY_PROFILE="<your-profile>"
if [[ -z "$NOTARY_PROFILE" && -f "${HOME}/.wired-notary" ]]; then
  # shellcheck source=/dev/null
  source "${HOME}/.wired-notary"
  NOTARY_PROFILE="${NOTARY_PROFILE:-}"
fi

# ── Version: read from project.pbxproj ───────────────────────────────────────

PBXPROJ="$XCODEPROJ/project.pbxproj"
DETECTED_MARKETING="$(grep -m1 'MARKETING_VERSION = ' "$PBXPROJ" 2>/dev/null \
  | sed 's/.*= //; s/;//; s/[[:space:]]//g' || echo "3.0")"
DETECTED_BUILD="$(grep -m1 'CURRENT_PROJECT_VERSION = ' "$PBXPROJ" 2>/dev/null \
  | sed 's/.*= //; s/;//; s/[[:space:]]//g' || echo "1")"

MARKETING_VERSION="${WIRED_MARKETING_VERSION:-$DETECTED_MARKETING}"
BUILD_NUMBER="${WIRED_BUILD_NUMBER:-$DETECTED_BUILD}"
TAG="${MARKETING_VERSION}+${BUILD_NUMBER}"

echo "============================================================"
echo "  Wired 3 (macOS) – release"
echo "  Version  : ${TAG}"
echo "  Scheme   : ${SCHEME}"
echo "============================================================"
echo ""

# ── Find Developer ID Application identity ────────────────────────────────────

resolve_signing_identity() {
  if [[ -n "${APPLE_SIGN_IDENTITY:-}" ]]; then
    echo "$APPLE_SIGN_IDENTITY"; return 0
  fi
  security find-identity -v -p codesigning 2>/dev/null \
    | sed -nE 's/.*"(Developer ID Application:[^"]*)".*/\1/p' \
    | head -1
}

SIGNING_IDENTITY="$(resolve_signing_identity || true)"
SIGNING_MODE="adhoc"
EXPORT_TEAM=""

if [[ -n "$SIGNING_IDENTITY" ]]; then
  SIGNING_MODE="developer-id"
  EXPORT_TEAM="$(echo "$SIGNING_IDENTITY" | sed -nE 's/.*\(([A-Z0-9]+)\)$/\1/p')"
  echo "==> Signing identity : ${SIGNING_IDENTITY}"
  echo "    Team ID           : ${EXPORT_TEAM}"
  echo ""
else
  echo "==> WARNING: No Developer ID Application certificate found in keychain."
  echo "    App will be ad-hoc signed and cannot be notarized."
  echo ""
fi

if [[ -n "$SIGNING_IDENTITY" && -z "$NOTARY_PROFILE" ]]; then
  echo "    TIP: Notarization is disabled. To enable it, create ~/.wired-notary:"
  echo "         NOTARY_PROFILE=\"<profile-name>\""
  echo "         Then store the credentials once with:"
  echo "         xcrun notarytool store-credentials \"<profile-name>\" --apple-id <id> --team-id <team>"
  echo ""
fi

# ── Prepare output directories ────────────────────────────────────────────────

mkdir -p "$DIST_DIR"
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"
mkdir -p "$EXPORT_PATH"

# ── Archive ───────────────────────────────────────────────────────────────────

echo "==> Archiving \"${SCHEME}\" (${BUILD_CONFIGURATION})"

ARCHIVE_FLAGS=(
  -project       "$XCODEPROJ"
  -scheme        "$SCHEME"
  -configuration "$BUILD_CONFIGURATION"
  -archivePath   "$ARCHIVE_PATH"
  SKIP_INSTALL=NO
  BUILD_LIBRARY_FOR_DISTRIBUTION=NO
  # Developer ID signing: no provisioning profile required.
  "PROVISIONING_PROFILE_SPECIFIER="
)

# The macOS team in project.pbxproj may differ from the local certificate;
# override DEVELOPMENT_TEAM so xcodebuild uses whichever cert is in the keychain.
if [[ -n "$EXPORT_TEAM" ]]; then
  ARCHIVE_FLAGS+=("DEVELOPMENT_TEAM=$EXPORT_TEAM")
fi

BUILD_LOG="$(mktemp)"
if ! xcodebuild archive "${ARCHIVE_FLAGS[@]}" 2>&1 | tee "$BUILD_LOG" | \
    grep -E '(^===|^Build|error:|SUCCEEDED|FAILED)' | uniq || true; then
  echo ""
fi

if ! grep -qE "(BUILD|ARCHIVE) SUCCEEDED" "$BUILD_LOG"; then
  echo ""
  echo "ERROR: Archive build failed. Last 30 lines of build log:"
  tail -30 "$BUILD_LOG"
  rm -f "$BUILD_LOG"
  exit 1
fi
rm -f "$BUILD_LOG"

if [[ ! -d "$ARCHIVE_PATH" ]]; then
  echo "ERROR: Archive not found at $ARCHIVE_PATH"
  exit 1
fi
echo "==> Archive created: $ARCHIVE_PATH"
echo ""

# ── Extract app from archive and sign ─────────────────────────────────────────

ARCHIVE_APP="$(find "$ARCHIVE_PATH/Products/Applications" -name "*.app" -maxdepth 1 | head -1)"
if [[ -z "$ARCHIVE_APP" ]]; then
  echo "ERROR: No .app found in $ARCHIVE_PATH/Products/Applications"
  exit 1
fi

cp -R "$ARCHIVE_APP" "$EXPORT_PATH/"
APP_PATH="$EXPORT_PATH/$(basename "$ARCHIVE_APP")"

if [[ "$SIGNING_MODE" == "developer-id" ]]; then
  echo "==> Signing with Developer ID: ${SIGNING_IDENTITY}"
  # Sign all nested bundles/frameworks first, then the app itself
  find "$APP_PATH" -name "*.framework" -o -name "*.dylib" -o -name "*.bundle" 2>/dev/null | \
    sort -r | while read -r item; do
      codesign --force --timestamp --options runtime --sign "$SIGNING_IDENTITY" "$item" 2>/dev/null || true
    done
  codesign --force --deep --timestamp --options runtime --sign "$SIGNING_IDENTITY" "$APP_PATH"
else
  echo "==> Ad-hoc signing"
  codesign --force --deep --sign - "$APP_PATH"
fi

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "ERROR: Could not locate exported .app"
  ls -la "$EXPORT_PATH" || true
  exit 1
fi

echo "==> App ready: $APP_PATH"
echo ""

# ── Create distribution ZIP ───────────────────────────────────────────────────

APP_ZIP="$DIST_DIR/Wired-3-${TAG}.zip"
rm -f "$APP_ZIP"
echo "==> Creating archive: $(basename "$APP_ZIP")"
ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"

# ── Notarization ──────────────────────────────────────────────────────────────

[[ -z "$NOTARIZE" && -n "$NOTARY_PROFILE" ]] && NOTARIZE="1"
NOTARIZE="${NOTARIZE:-0}"
case "$NOTARIZE" in
  1|true|TRUE|yes|YES) NOTARIZE="1" ;;
  *) NOTARIZE="0" ;;
esac

if [[ "$NOTARIZE" == "1" ]]; then
  if [[ "$SIGNING_MODE" != "developer-id" ]]; then
    echo "ERROR: Notarization requires a Developer ID signature."
    echo "       Set APPLE_SIGN_IDENTITY or ensure a Developer ID cert is in your keychain."
    exit 1
  fi
  if [[ -z "$NOTARY_PROFILE" ]]; then
    echo "ERROR: NOTARIZE=1 requires NOTARY_PROFILE (notarytool keychain profile name)."
    echo "       Create one with: xcrun notarytool store-credentials <profile-name>"
    exit 1
  fi

  echo ""
  echo "==> Notarizing Wired 3"
  xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

  echo "==> Stapling notarization ticket"
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"

  # Re-create zip to include the stapled ticket
  rm -f "$APP_ZIP"
  ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"
  echo "==> Archive updated with stapled ticket"
fi

# ── Verify signature ──────────────────────────────────────────────────────────

echo ""
echo "==> Verifying code signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
if [[ "$SIGNING_MODE" == "developer-id" && "$NOTARIZE" == "1" ]]; then
  spctl --assess --type execute --verbose=4 "$APP_PATH"
elif [[ "$SIGNING_MODE" == "developer-id" ]]; then
  echo "    (Gatekeeper check skipped – app not notarized)"
fi

# ── Copy to ~/Downloads ───────────────────────────────────────────────────────

mkdir -p "$DOWNLOADS_DIR"

APP_BASENAME="$(basename "$APP_PATH")"
DEST_APP="$DOWNLOADS_DIR/$APP_BASENAME"
DEST_ZIP="$DOWNLOADS_DIR/Wired-3-${TAG}.zip"

rm -rf "$DEST_APP"
cp -R "$APP_PATH" "$DEST_APP"
cp -f "$APP_ZIP"  "$DEST_ZIP"

echo ""
echo "==> Release complete: ${DOWNLOADS_DIR}"
echo "    ${APP_BASENAME}"
echo "    Wired-3-${TAG}.zip"
