#!/usr/bin/env bash
# Builds, signs and uploads the iOS app to TestFlight from this Mac. There is no CI.
#
# Usage:
#   scripts/testflight.sh                 archive + upload an internal-testing-only build
#   scripts/testflight.sh --external      upload a build that may later go to external testers / App Review
#   scripts/testflight.sh --ipa-only      archive + export a distribution-signed .ipa, skip the upload
#   scripts/testflight.sh --archive-only  sign and archive, skip the export and the upload
#
# Requirements: Xcode signed in with the team account (Settings → Accounts), Mint (brew install mint),
# and an App Store Connect app record for cz.bezpecneqr.app (needed for the upload step only).
# One-time setup is described in ios/README.md.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

internal=true
mode=upload
for arg in "$@"; do
  case "$arg" in
    --external) internal=false ;;
    --ipa-only) mode=ipa ;;
    --archive-only) mode=archive ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

cd "$root/ios"
version="$(tr -d '[:space:]' < "$root/VERSION")"

# Reserve the next build number before anything can fail half-way through an upload.
build=$(( $(tr -d '[:space:]' < BUILD_NUMBER) + 1 ))
echo "$build" > BUILD_NUMBER
echo "▸ Bezpečné QR $version ($build)"

echo "▸ Generating the Xcode project"
mint run xcodegen generate > /dev/null

for pkg in Packages/*/; do
  if [ -f "$pkg/Package.swift" ]; then
    echo "▸ swift test — $pkg"
    (cd "$pkg" && swift test)
  fi
done

artifacts="artifacts/$version-$build"
mkdir -p "$artifacts"

echo "▸ Archiving (Release, automatic signing)"
set +e
xcodebuild archive \
  -project BezpecneQR.xcodeproj \
  -scheme BezpecneQR \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$artifacts/BezpecneQR.xcarchive" \
  CURRENT_PROJECT_VERSION="$build" \
  -allowProvisioningUpdates > "$artifacts/archive.log" 2>&1
status=$?
set -e
grep -E "error:|ARCHIVE (SUCCEEDED|FAILED)" "$artifacts/archive.log" | head -20 || true
if [ $status -ne 0 ]; then
  echo "✗ Archive failed — full log: ios/$artifacts/archive.log" >&2
  exit $status
fi

if [ "$mode" = archive ]; then
  echo "✓ Archive ready: ios/$artifacts/BezpecneQR.xcarchive (export and upload skipped)"
  exit 0
fi

cp ExportOptions.plist "$artifacts/ExportOptions.plist"
/usr/libexec/PlistBuddy -c "Set :testFlightInternalTestingOnly $internal" "$artifacts/ExportOptions.plist"
if [ "$mode" = ipa ]; then
  /usr/libexec/PlistBuddy -c "Set :destination export" "$artifacts/ExportOptions.plist"
  echo "▸ Exporting a distribution-signed .ipa (no upload)"
else
  echo "▸ Uploading to App Store Connect (internal only: $internal)"
fi

set +e
xcodebuild -exportArchive \
  -archivePath "$artifacts/BezpecneQR.xcarchive" \
  -exportOptionsPlist "$artifacts/ExportOptions.plist" \
  -exportPath "$artifacts/export" \
  -allowProvisioningUpdates > "$artifacts/export.log" 2>&1
status=$?
set -e
grep -E "error:|Upload succeeded|EXPORT (SUCCEEDED|FAILED)|Uploaded" "$artifacts/export.log" | head -20 || true
if [ $status -ne 0 ]; then
  if grep -q "App record with bundle identifier" "$artifacts/export.log"; then
    echo "  The app record is missing. xcodebuild cannot create it — see \"One-time setup\" in ios/README.md." >&2
  fi
  echo "✗ Export failed — full log: ios/$artifacts/export.log" >&2
  exit $status
fi

if [ "$mode" = ipa ]; then
  echo "✓ Signed .ipa ready: ios/$artifacts/export/BezpecneQR.ipa (upload skipped)"
else
  echo "✓ Uploaded $version ($build). TestFlight notifies the internal group once processing finishes."
fi
