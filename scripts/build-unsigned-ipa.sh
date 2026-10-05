#!/bin/bash
# Creates a device (not simulator) IPA. Signing/provisioning are intentionally not performed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p build/logs build/ipa
xcodebuild -project Pupudiary.xcodeproj -scheme Pupudiary \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/DeviceDerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO build 2>&1 | tee build/logs/device-build.log
APP='build/DeviceDerivedData/Build/Products/Release-iphoneos/Pupudiary.app'
[[ -d "$APP/PlugIns/PupudiaryWidgetExtension.appex" ]] || { echo 'Missing embedded widget extension' >&2; exit 1; }
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/pupudiary-package.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
mkdir -p "$STAGING/Payload"
ditto "$APP" "$STAGING/Payload/Pupudiary.app"
# Preserve the complete app bundle and PlugIns; never strip the widget to make signing easier.
rm -f "$ROOT/build/ipa/Pupudiary-unsigned.ipa"
(cd "$STAGING" && /usr/bin/zip -q -r -y "$ROOT/build/ipa/Pupudiary-unsigned.ipa" Payload)
python3 scripts/validate-ipa.py build/ipa/Pupudiary-unsigned.ipa --unsigned | tee build/logs/ipa-validation.log
shasum -a 256 build/ipa/Pupudiary-unsigned.ipa > build/ipa/SHA256SUMS.txt
cp Config/App.entitlements build/ipa/App.entitlements
cp Config/Widget.entitlements build/ipa/Widget.entitlements
cp Docs/SIGNING.md build/ipa/SIGNING.md
