#!/usr/bin/env bash
# Copies the shared rules and content (single source of truth in shared/) into the BQCore package
# resources. Run after editing anything in shared/rules or shared/content; BQCoreTests fails when the
# copies are out of date.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
dest="$root/ios/Packages/BQCore/Sources/BQCore/Resources"
rm -rf "$dest/rules" "$dest/content"
mkdir -p "$dest/rules" "$dest/content"
cp "$root"/shared/rules/*.json "$dest/rules/"
cp "$root"/shared/content/*.json "$dest/content/"
echo "Synced shared/rules and shared/content → ios/Packages/BQCore/Sources/BQCore/Resources"
