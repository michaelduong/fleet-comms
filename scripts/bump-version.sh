#!/bin/bash
# Set the next version: MARKETING_VERSION in Config/Version.xcconfig, CURRENT_PROJECT_VERSION + 1, and a
# new CHANGELOG.md section to fill in. Usage: scripts/bump-version.sh X.Y.Z
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
version="${1:-}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: $0 X.Y.Z" >&2; exit 2; }
config="$repo/Config/Version.xcconfig"
changelog="$repo/CHANGELOG.md"
current="$(sed -n 's/^CURRENT_PROJECT_VERSION = //p' "$config")"
next=$((current + 1))
sed -i '' -e "s/^MARKETING_VERSION = .*/MARKETING_VERSION = $version/" \
  -e "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $next/" "$config"
if ! grep -q "^## \[$version\]" "$changelog"; then
  today="$(date +%Y-%m-%d)"
  awk -v v="$version" -v d="$today" '
    !done && /^## \[/ { print "## [" v "] - " d "\n\n### Added\n- \n\n### Changed\n- \n\n### Fixed\n- \n"; done = 1 }
    { print }
  ' "$changelog" > "$changelog.tmp" && mv "$changelog.tmp" "$changelog"
fi
echo "Version $version (build $next). Fill in the CHANGELOG.md section, then commit Config/Version.xcconfig and CHANGELOG.md."
