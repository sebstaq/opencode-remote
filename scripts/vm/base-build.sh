#!/usr/bin/env bash
set -euo pipefail

# Runs on the macOS VM as `base` (holds the signing identity). Reads the login
# keychain password from stdin so it can be unlocked in the same SSH session.
#
# Signing uses an App Store Connect API key for automatic signing, which is the
# supported headless path and does not need an Apple ID account in Xcode. The
# credentials live on the VM at ~/.config/opencode-remote/app-store-connect/
# (key-id, issuer-id, AuthKey_<keyid>.p8) and are provisioned from Doppler.
#
# CONFIG defaults to Debug; pass Release only when a release build is required.
CONFIG="${CONFIG:-Debug}"
CRED_DIR="${OPENCODE_ASC_CREDENTIALS_DIR:-$HOME/.config/opencode-remote/app-store-connect}"

# Automatic signing needs the team ID; it is intentionally not committed to the
# repo. Pass it as an environment variable (environment variables act as build
# settings for xcodebuild).
if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  echo "STOPP: DEVELOPMENT_TEAM ar inte satt (exportera den i anropet, se .env.example)"
  exit 42
fi
export DEVELOPMENT_TEAM

IFS= read -r keychain_password
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
if ! security unlock-keychain -p "$keychain_password" "$KEYCHAIN" >/dev/null 2>&1; then
  unset keychain_password
  echo "STOPP: login-keychain kunde inte lasas upp"
  exit 41
fi
unset keychain_password
echo "KEYCHAIN_UNLOCKED=yes"

key_id="$(tr -d '\r\n' < "$CRED_DIR/key-id" 2>/dev/null || true)"
issuer_id="$(tr -d '\r\n' < "$CRED_DIR/issuer-id" 2>/dev/null || true)"
key_path="$CRED_DIR/AuthKey_${key_id}.p8"
if [[ ! "$key_id" =~ ^[A-Z0-9]{10}$ || ! "$issuer_id" =~ ^[0-9a-fA-F-]{36}$ || ! -r "$key_path" ]]; then
  echo "STOPP: App Store Connect-nyckeln ar inte korrekt installerad i $CRED_DIR"
  exit 70
fi
echo "ASC_KEY_ID=$key_id"

cd /Users/base/opencode-remote
export DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer
/Users/w3/tools/xcodegen/xcodegen/bin/xcodegen generate >/dev/null 2>&1 || true

BUILD_ROOT="/tmp/opencode-build/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BUILD_ROOT"

AUTH=(
  -allowProvisioningUpdates
  -authenticationKeyPath "$key_path"
  -authenticationKeyID "$key_id"
  -authenticationKeyIssuerID "$issuer_id"
)

if ! xcodebuild \
  -project OpenCodeRemote.xcodeproj \
  -scheme OpenCodeRemote \
  -configuration "$CONFIG" \
  -destination "generic/platform=iOS" \
  -archivePath "$BUILD_ROOT/OpenCodeRemote.xcarchive" \
  -skipPackagePluginValidation \
  "${AUTH[@]}" \
  archive >"$BUILD_ROOT/archive.log" 2>&1; then
  echo "ARCHIVE_FAILED"
  tail -n 50 "$BUILD_ROOT/archive.log"
  exit 45
fi
echo "ARCHIVE_OK"

if ! xcodebuild \
  -exportArchive \
  -archivePath "$BUILD_ROOT/OpenCodeRemote.xcarchive" \
  -exportPath "$BUILD_ROOT/export" \
  -exportOptionsPlist /Users/base/opencode-remote/scripts/ExportOptions-Dev.plist \
  "${AUTH[@]}" >"$BUILD_ROOT/export.log" 2>&1; then
  echo "EXPORT_FAILED"
  tail -n 50 "$BUILD_ROOT/export.log"
  exit 46
fi
echo "EXPORT_OK"

IPA="$BUILD_ROOT/export/OpenCodeRemote.ipa"
if [ ! -s "$IPA" ]; then
  echo "NO_IPA"
  ls -la "$BUILD_ROOT/export"
  exit 47
fi
echo "IPA=$IPA"
