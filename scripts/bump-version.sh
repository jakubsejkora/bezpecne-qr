#!/usr/bin/env bash
# Bumps the repo version by +0.0.1, following the project rule:
#   0.0.1 → 0.0.2 → … → 0.0.9 → 0.0.10 (never rolls over to 0.1.0 automatically).
# Updates VERSION, the iOS MARKETING_VERSION (once ios/project.yml exists), adds a CHANGELOG
# section and regenerates the prototype data so the prototype shows the new version.
#
# Usage: scripts/bump-version.sh "Short summary of the change set"
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cur="$(tr -d '[:space:]' < "$root/VERSION")"
IFS=. read -r major minor patch <<<"$cur"
next="$major.$minor.$((patch + 1))"
echo "$next" > "$root/VERSION"

if [ -f "$root/ios/project.yml" ]; then
  sed -i '' -E "s/(MARKETING_VERSION: *\"?)[0-9]+\.[0-9]+\.[0-9]+(\"?)/\1$next\2/" "$root/ios/project.yml"
fi

python3 - "$root/CHANGELOG.md" "$next" "$(date +%Y-%m-%d)" "${1:-}" <<'PY'
import sys
path, ver, date, summary = sys.argv[1:5]
text = open(path, encoding="utf-8").read()
entry = f"## [{ver}] - {date}\n\n### Changed\n- {summary or 'TODO: describe the changes'}\n\n"
marker = "## [Unreleased]\n\n"
if marker in text:
    text = text.replace(marker, marker + entry, 1)
else:
    i = text.find("\n## ")
    text = text[: i + 1] + entry + text[i + 1 :] if i != -1 else text + "\n" + entry
open(path, "w", encoding="utf-8").write(text)
PY

node "$root/scripts/gen-prototype-data.mjs" > /dev/null
echo "Version bumped: $cur → $next (edit the new CHANGELOG entry before committing)"
