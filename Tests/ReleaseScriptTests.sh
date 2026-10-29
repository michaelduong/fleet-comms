#!/bin/bash
# Refusal paths must never reach a build, signer, key generator or uploader.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
mkdir "$scratch/bin"
cat > "$scratch/bin/security" <<'MOCK'
#!/bin/bash
case "$1" in
  find-identity) printf '  1) TEST "Developer ID Application: Release Test (TESTTEAM00)"\n' ;;
  find-generic-password) exit 44 ;;
  *) exit 99 ;;
esac
MOCK
chmod +x "$scratch/bin/security"
for tool in xcrun codesign generate_keys generate_appcast gh-axi; do
  cat > "$scratch/bin/$tool" <<'MOCK'
#!/bin/bash
echo forbidden >> "$RELEASE_TEST_FORBIDDEN"
exit 99
MOCK
  chmod +x "$scratch/bin/$tool"
done
export PATH="$scratch/bin:$PATH" RELEASE_TEST_FORBIDDEN="$scratch/forbidden"
export FLEET_COMMS_DIST="$scratch/output" FLEET_COMMS_TEAM=TESTTEAM00
for mode in --dry-run --prepare-draft; do
  export FLEET_COMMS_IDENTITY=''
  if "$repo/scripts/release.sh" "$mode" > "$scratch/result" 2>&1; then exit 1; fi
  grep -q 'FLEET_COMMS_IDENTITY must name' "$scratch/result"
  export FLEET_COMMS_IDENTITY='Developer ID Application: Release Test (TESTTEAM00)'
  if "$repo/scripts/release.sh" "$mode" > "$scratch/result" 2>&1; then exit 1; fi
  grep -q 'Sparkle signing key is missing from Keychain' "$scratch/result"
done
[ ! -e "$scratch/forbidden" ]
[ ! -e "$scratch/output" ]
printf '%s\n' 'PASS: both modes refuse missing identity/key without build, signing, key generation, upload or output writes'

# Exercise the rest of preflight entirely offline. These are empty/synthetic fixtures, not signing keys.
mkdir -p "$scratch/repo/scripts" "$scratch/repo/Config" "$scratch/sparkle/bin" \
  "$scratch/sparkle/Sparkle.framework/Resources" "$scratch/api-keys"
cp "$repo/scripts/release.sh" "$scratch/repo/scripts/"
printf 'MARKETING_VERSION = 1.0.0\nCURRENT_PROJECT_VERSION = 1\n' > "$scratch/repo/Config/Version.xcconfig"
printf 'FLEET_COMMS_UPDATES_ENABLED = YES\nFLEET_COMMS_SPARKLE_PUBLIC_KEY = fixture-public-key\n' > "$scratch/repo/Config/Sparkle.xcconfig"
cat > "$scratch/sparkle/Sparkle.framework/Resources/Info.plist" <<'PLIST'
<?xml version="1.0"?><plist version="1.0"><dict>
<key>CFBundleShortVersionString</key><string>2.10.1</string></dict></plist>
PLIST
cat > "$scratch/bin/security" <<'MOCK'
#!/bin/bash
case "$1" in
  find-identity) printf '  1) TEST "Developer ID Application: Release Test (TESTTEAM00)"\n' ;;
  find-generic-password) exit 0 ;;
  *) exit 99 ;;
esac
MOCK
cat > "$scratch/bin/git" <<'MOCK'
#!/bin/bash
case "$3 $4" in
  'status --porcelain') exit 0 ;;
  'branch --show-current') echo main ;;
  'rev-parse HEAD') echo fixture-commit ;;
  'rev-parse -q') exit 1 ;;
  *) echo forbidden >> "$RELEASE_TEST_FORBIDDEN"; exit 99 ;;
esac
MOCK
cat > "$scratch/bin/gh-axi" <<'MOCK'
#!/bin/bash
if [ "$1 $2" = 'release view' ]; then exit 1; fi
if [ "$1" = api ]; then
  case "$2" in
    */compare/*) echo identical ;;
    */git/matching-refs/*) exit 0 ;;
    repos/michaelduong/fleet-comms) echo false ;;
    *) exit 99 ;;
  esac
else
  echo forbidden >> "$RELEASE_TEST_FORBIDDEN"; exit 99
fi
MOCK
cat > "$scratch/bin/asc" <<'MOCK'
#!/bin/bash
if [ "$1" = --profile ]; then
  printf '{"credentials":[{"name":"mock-release","keyId":"TESTKEY000"}]}\n'
else
  printf '00000000-0000-0000-0000-000000000000\n'
fi
MOCK
cat > "$scratch/bin/xcrun" <<'MOCK'
#!/bin/bash
if [ "$1 $2" = 'notarytool history' ]; then
  printf '%s\n' "$@" > "$RELEASE_TEST_NOTARY_ARGS"
else
  echo forbidden >> "$RELEASE_TEST_FORBIDDEN"; exit 99
fi
MOCK
cat > "$scratch/sparkle/bin/generate_keys" <<'MOCK'
#!/bin/bash
if [ "$*" = '--account fleet-comms -p' ]; then
  echo fixture-public-key
else
  echo forbidden >> "$RELEASE_TEST_FORBIDDEN"; exit 99
fi
MOCK
cp "$scratch/bin/generate_appcast" "$scratch/sparkle/bin/"
cp "$scratch/bin/generate_appcast" "$scratch/sparkle/bin/sign_update"
chmod +x "$scratch/bin/"* "$scratch/sparkle/bin/"*
touch "$scratch/api-keys/AuthKey_TESTKEY000.p8"
export FLEET_COMMS_SPARKLE_BIN="$scratch/sparkle/bin" RELEASE_TEST_NOTARY_ARGS="$scratch/notary-args"
unset FLEET_COMMS_NOTARY_KEY_NAME FLEET_COMMS_NOTARY_PROFILE
"$scratch/repo/scripts/release.sh" --dry-run > "$scratch/result"
grep -q 'Preflight passed' "$scratch/result"
grep -qx -- '--keychain-profile' "$scratch/notary-args"
export FLEET_COMMS_NOTARY_KEY_NAME=mock-release FLEET_COMMS_NOTARY_KEY_DIR="$scratch/api-keys"
"$scratch/repo/scripts/release.sh" --dry-run > "$scratch/result"
grep -q 'Preflight passed' "$scratch/result"
grep -qx -- '--key' "$scratch/notary-args"
grep -qx -- '--key-id' "$scratch/notary-args"
grep -qx -- '--issuer' "$scratch/notary-args"
[ ! -e "$scratch/forbidden" ]
[ ! -e "$scratch/output" ]
printf '%s\n' 'PASS: offline dry-run fixtures cover keychain-profile and named-API-key notarization auth without building, signing, generating keys, submitting or uploading'
