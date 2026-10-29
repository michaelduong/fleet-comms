#!/bin/bash
# Prepare a signed, notarized Sparkle update and a DRAFT GitHub release. Never publishes.
# Usage: scripts/release.sh --dry-run | --prepare-draft
# --dry-run performs read-only preflight, refusing the first missing credential, then prints the plan.
# --prepare-draft archives, exports, notarizes, staples, packages, signs the appcast and uploads a draft.
# Required: FLEET_COMMS_IDENTITY (exact Developer ID Application name), FLEET_COMMS_TEAM,
# FLEET_COMMS_SPARKLE_BIN (bin directory from the pinned Sparkle 2.10.1 distribution).
# Optional: FLEET_COMMS_NOTARY_PROFILE=fleet-comms, or FLEET_COMMS_NOTARY_KEY_NAME=<asc profile>.
# FLEET_COMMS_NOTARY_KEY_DIR defaults to ~/.appstoreconnect/private_keys (API key files are read only).
# FLEET_COMMS_SPARKLE_ACCOUNT=fleet-comms, FLEET_COMMS_DIST=<repo>/dist. EdDSA keys stay in Keychain.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
die() { printf 'release: %s\n' "$*" >&2; exit 1; }
setting() { sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$2" | tail -1 | sed 's/[[:space:]]*$//'; }
mode="${1:-}"
case "$mode" in
  -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  --dry-run|--prepare-draft) [ "$#" -eq 1 ] || die 'supply exactly one mode' ;;
  *) die 'choose --dry-run or --prepare-draft; publishing is a separate manual step' ;;
esac

version="$(setting MARKETING_VERSION "$repo/Config/Version.xcconfig")"
build_number="$(setting CURRENT_PROJECT_VERSION "$repo/Config/Version.xcconfig")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 'MARKETING_VERSION must be X.Y.Z'
[[ "$build_number" =~ ^[0-9]+$ ]] || die 'CURRENT_PROJECT_VERSION must be numeric and increase for every update'
identity="${FLEET_COMMS_IDENTITY:-}"
team="${FLEET_COMMS_TEAM:-}"
profile="${FLEET_COMMS_NOTARY_PROFILE:-fleet-comms}"
account="${FLEET_COMMS_SPARKLE_ACCOUNT:-fleet-comms}"
sparkle_bin="${FLEET_COMMS_SPARKLE_BIN:-}"
dist="${FLEET_COMMS_DIST:-$repo/dist}"
forge='michaelduong/fleet-comms'
tag="v$version"
slug="Fleet-Comms-$version"

printf 'Read-only release preflight for %s (build %s)\n' "$tag" "$build_number"
[[ "$identity" == 'Developer ID Application: '* ]] || die 'FLEET_COMMS_IDENTITY must name an exact Developer ID Application identity; no archive or signing attempted'
security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$identity\"" || die 'requested Developer ID identity is missing or invalid'
[[ "$team" =~ ^[A-Z0-9]{10}$ && "$identity" == *"($team)" ]] || die 'FLEET_COMMS_TEAM must match the Developer ID identity'
# Look up metadata only, never use security -w/-g or export private key material.
security find-generic-password -s https://sparkle-project.org -a "$account" >/dev/null 2>&1 || die 'Sparkle signing key is missing from Keychain; project owner must run the one-time generate_keys setup'
[ "$(setting FLEET_COMMS_UPDATES_ENABLED "$repo/Config/Sparkle.xcconfig")" = YES ] || die 'release hold is active in Config/Sparkle.xcconfig'
public_key="$(setting FLEET_COMMS_SPARKLE_PUBLIC_KEY "$repo/Config/Sparkle.xcconfig")"
[ "$public_key" != REPLACE_WITH_SPARKLE_PUBLIC_ED25519_KEY ] || die 'replace the public verification key placeholder first'
for tool in generate_appcast generate_keys sign_update; do
  [ -x "$sparkle_bin/$tool" ] || die "FLEET_COMMS_SPARKLE_BIN must contain $tool from Sparkle 2.10.1"
done
framework_info="$sparkle_bin/../Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/Resources/Info.plist"
[ -f "$framework_info" ] || framework_info="$sparkle_bin/../Sparkle.framework/Resources/Info.plist"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$framework_info" 2>/dev/null)" = 2.10.1 ] || die 'Sparkle tools must come from the pinned 2.10.1 distribution'
for tool in gh-axi xcsift python3; do command -v "$tool" >/dev/null || die "$tool is required"; done
[ -z "$(git -C "$repo" status --porcelain)" ] || die 'working tree must be clean'
[ "$(git -C "$repo" branch --show-current)" = main ] || die 'release preparation requires the reviewed main branch'
[ "$(gh-axi api "repos/$forge" --jq '.private')" = false ] || die 'repository must be public before preparing Sparkle updates'
[ "$(gh-axi api "repos/$forge/compare/main...$(git -C "$repo" rev-parse HEAD)" --jq '.status')" = identical ] || die 'HEAD must match GitHub main'
notary_auth=(--keychain-profile "$profile")
if [ -n "${FLEET_COMMS_NOTARY_KEY_NAME:-}" ]; then
  [ -z "${FLEET_COMMS_NOTARY_PROFILE:-}" ] || die 'choose a notarization profile OR an asc key name'
  command -v asc >/dev/null || die 'asc is required for named App Store Connect key lookup'
  key_name="$FLEET_COMMS_NOTARY_KEY_NAME"
  key_id="$(asc --profile "$key_name" auth status --output json | python3 -c '
import json, sys
matches = [c["keyId"] for c in json.load(sys.stdin)["credentials"] if c["name"] == sys.argv[1]]
if len(matches) != 1:
    sys.exit("release: named App Store Connect key not found")
print(matches[0])' "$key_name")" || die 'cannot resolve the named App Store Connect key'
  issuer="$(asc auth issuer-id --name "$key_name")" || die 'cannot resolve the named key issuer'
  [[ "$key_id" =~ ^[A-Z0-9]{10}$ ]] || die 'named key has an invalid key ID'
  [[ "$issuer" =~ ^[A-Fa-f0-9-]{36}$ ]] || die 'named key has an invalid issuer ID'
  key_dir="${FLEET_COMMS_NOTARY_KEY_DIR:-$HOME/.appstoreconnect/private_keys}"
  key_file="$key_dir/AuthKey_$key_id.p8"
  [ -r "$key_file" ] || die 'private API key file for the named asc profile is missing or unreadable'
  notary_auth=(--key "$key_file" --key-id "$key_id" --issuer "$issuer")
fi
# Validate the selected profile/API key without submitting a build. Never print credentials.
xcrun notarytool history "${notary_auth[@]}" >/dev/null 2>&1 || die 'notarization credentials are missing or invalid'
# Lookup-only mode cannot generate keys. Capture the public output without printing it.
stored_public_key="$("$sparkle_bin/generate_keys" --account "$account" -p 2>/dev/null)" || die 'Sparkle Keychain key is inaccessible'
[ "$stored_public_key" = "$public_key" ] || die 'configured public key does not match the selected Keychain account'
if git -C "$repo" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  die 'tag already exists locally; choose a new version'
fi
refs="$(gh-axi api "repos/$forge/git/matching-refs/tags/$tag" --jq '.[].ref')" || die 'could not check existing GitHub tags'
if printf '%s\n' "$refs" | grep -Fxq "refs/tags/$tag"; then
  die 'tag already exists on GitHub; choose a new version'
fi
if gh-axi release view "$tag" --repo "$forge" >/dev/null 2>&1; then
  die 'release already exists; choose a new version rather than replacing release assets'
fi
if [ "$mode" = --dry-run ]; then
  printf '%s\n' 'Preflight passed. Plan: archive → Developer ID export → notarize app zip → staple app → zip/DMG → notarize/staple DMG → generate_appcast → verify feed → upload DRAFT. Nothing built, signed, submitted or uploaded.'
  exit 0
fi

[ ! -e "$dist/$slug" ] || die 'output directory already exists; choose a fresh FLEET_COMMS_DIST'
work="$dist/$slug"
mkdir -p "$work/updates"
notes="$work/notes.md"
awk -v v="$version" '$0 == "## [" v "]" || index($0, "## [" v "] ") == 1 { on=1; next } on && /^## \[/ { exit } on { print }' "$repo/CHANGELOG.md" > "$notes"
grep -q '[^[:space:]]' "$notes" || die 'version needs nonempty CHANGELOG release notes'

archive="$work/$slug.xcarchive"
derived="$work/DerivedData"
# Keep all build output out of terminal logs; xcsift provides the diagnostic summary.
run_build() {
  local log="$1"
  shift
  if ! "$@" > "$log" 2>&1; then
    xcsift < "$log"
    die "build failed; inspect the failing diagnostic in $log"
  fi
  xcsift < "$log"
}
run_build "$work/archive.log" xcrun xcodebuild -project "$repo/NotchVoice.xcodeproj" \
  -scheme NotchVoice -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$derived" -archivePath "$archive" -onlyUsePackageVersionsFromResolvedFile \
  -skipPackageUpdates DEVELOPMENT_TEAM="$team" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$identity" \
  FLEET_COMMS_BUNDLE_ID=io.github.michaelduong.fleetcomms archive
options="$work/ExportOptions.plist"
python3 - "$options" "$team" "$identity" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as stream:
    plistlib.dump(dict(method='developer-id', teamID=sys.argv[2], signingStyle='manual',
                       signingCertificate=sys.argv[3], destination='export'), stream)
PY
run_build "$work/export.log" xcrun xcodebuild -exportArchive -archivePath "$archive" \
  -exportOptionsPlist "$options" -exportPath "$work/export"
app="$work/export/Fleet Comms.app"
python3 - "$app/Contents/Info.plist" "$version" "$build_number" "$public_key" <<'PYINFO'
import plistlib, sys
info = plistlib.load(open(sys.argv[1], 'rb'))
expected = dict(CFBundleIdentifier='io.github.michaelduong.fleetcomms', CFBundleShortVersionString=sys.argv[2],
                CFBundleVersion=sys.argv[3], SUPublicEDKey=sys.argv[4], FleetCommsUpdatesEnabled='YES',
                SUFeedURL='https://github.com/michaelduong/fleet-comms/releases/latest/download/appcast.xml')
if any(info.get(k) != v for k, v in expected.items()):
    sys.exit('release: exported identity, version or updater configuration differs from the release config')
PYINFO
codesign --verify --deep --strict "$app"
codesign -d -r- "$app" 2>&1 | grep -Fq "certificate leaf[subject.OU] = $team" || die 'export is not signed by the requested team'

submission="$work/notarization.zip"
ditto -c -k --keepParent "$app" "$submission"
xcrun notarytool submit "$submission" "${notary_auth[@]}" --wait --output-format json > "$work/notary-app.json"
python3 - "$work/notary-app.json" <<'PY'
import json, sys
if json.load(open(sys.argv[1]))['status'] != 'Accepted':
    sys.exit('release: app notarization was not accepted')
PY
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute "$app"
zip="$work/updates/$slug.zip"
ditto -c -k --keepParent "$app" "$zip"
mkdir "$work/dmg-stage"
ditto "$app" "$work/dmg-stage/Fleet Comms.app"
ln -s /Applications "$work/dmg-stage/Applications"
dmg="$work/$slug.dmg"
hdiutil create -quiet -volname 'Fleet Comms' -srcfolder "$work/dmg-stage" -format UDZO "$dmg"
codesign --timestamp --sign "$identity" "$dmg"
xcrun notarytool submit "$dmg" "${notary_auth[@]}" --wait --output-format json > "$work/notary-dmg.json"
python3 - "$work/notary-dmg.json" <<'PY'
import json, sys
if json.load(open(sys.argv[1]))['status'] != 'Accepted':
    sys.exit('release: DMG notarization was not accepted')
PY
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature "$dmg"

# The ZIP contains the stapled app; make the DMG from that same stapled app before notarizing it.
cp "$notes" "$work/updates/$slug.md"
appcast="$work/updates/appcast.xml"
"$sparkle_bin/generate_appcast" --account "$account" --maximum-deltas 0 --embed-release-notes \
  --download-url-prefix "https://github.com/$forge/releases/download/$tag/" \
  -o "$appcast" "$work/updates" > "$work/appcast.log" 2>&1 || die "generate_appcast failed; see $work/appcast.log"
# generate_appcast can warn and omit signatures; never upload such a feed.
signature="$(python3 - "$appcast" "$zip" "$build_number" "https://github.com/$forge/releases/download/$tag/$slug.zip" <<'PY'
import base64, os, sys, xml.etree.ElementTree as ET
ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
items = ET.parse(sys.argv[1]).findall('./channel/item')
if len(items) != 1:
    sys.exit('release: expected exactly one signed full update')
e = items[0].find('enclosure')
if (e is None or len(base64.b64decode(e.get(ns+'edSignature', ''), validate=True)) != 64
        or items[0].findtext(ns+'version') != sys.argv[3]
        or e.get('url') != sys.argv[4] or int(e.get('length', 0)) != os.path.getsize(sys.argv[2])):
    sys.exit('release: missing signature or incorrect appcast metadata')
print(e.get(ns+'edSignature'))
PY
)" || die 'appcast validation failed'
"$sparkle_bin/sign_update" --account "$account" --verify "$zip" "$signature" > "$work/signature-check.log" 2>&1 || die 'EdDSA verification failed'
sums="$work/$slug-SHA256SUMS.txt"
shasum -a 256 "$zip" "$dmg" "$appcast" | sed "s|$work/updates/||;s|$work/||" > "$sums"
gh-axi release create "$tag" --repo "$forge" --draft --target "$(git -C "$repo" rev-parse HEAD)" \
  --title "Fleet Comms $version" --notes-file "$notes" "$zip" "$dmg" "$appcast" "$sums"
printf '%s\n' 'Draft prepared. Review assets, signatures, anonymous feed access and upgrade behavior before manually publishing as the latest stable release.'
