#!/bin/bash
# This script may handle signing credentials only on the official Actions runner.
set +x
set -euo pipefail
umask 077
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
[[ $# == 2 && "$1" == --tag ]] || { echo 'Usage: release.sh --tag vVERSION' >&2; exit 2; }
tag="$2"
python3 scripts/release-preflight.py "$tag" --check-credentials --check-git
[[ "$(uname -m)" == arm64 ]] || { echo 'Official releases require an arm64 runner' >&2; exit 1; }
[[ -n "${RUNNER_TEMP:-}" && "${GITHUB_RUN_ID:-}" =~ ^[0-9]+$ && "${GITHUB_RUN_ATTEMPT:-}" =~ ^[0-9]+$ ]] || exit 1
signing_dir="$RUNNER_TEMP/keypin-signing-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
[[ ! -e "$signing_dir" ]] || { echo 'Signing directory already exists' >&2; exit 1; }
mkdir -m 700 "$signing_dir"
trap 'bash "$root/scripts/cleanup-release.sh"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
keychain="$signing_dir/signing.keychain-db"
certificate="$signing_dir/certificate.p12"
private_key="$signing_dir/sparkle-private-key"
export KEYPIN_SIGNING_DIRECTORY="$signing_dir"
python3 - <<'PY'
from pathlib import Path
import base64, os
directory = Path(os.environ["KEYPIN_SIGNING_DIRECTORY"])
(directory / "certificate.p12").write_bytes(base64.b64decode("".join(os.environ["MACOS_CERTIFICATE_P12_BASE64"].split()), validate=True))
(directory / "sparkle-private-key").write_text(os.environ["SPARKLE_PRIVATE_KEY"].strip())
PY
unset MACOS_CERTIFICATE_P12_BASE64 SPARKLE_PRIVATE_KEY
swift scripts/validate-signing-key.swift "$private_key"
keychain_password="$(openssl rand -base64 32)"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$certificate" -k "$keychain" -P "$MACOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
unset MACOS_CERTIFICATE_PASSWORD keychain_password
rm -f "$certificate"
identity="$(security find-identity -v -p codesigning "$keychain" | python3 -c 'import os,re,sys; matches=re.findall(r"([A-Fa-f0-9]{40}) \"Developer ID Application: [^\"]+ \("+re.escape(os.environ["AC_TEAM_ID"])+r"\)\"",sys.stdin.read()); len(matches)==1 or sys.exit("Expected exactly one valid Developer ID Application identity for AC_TEAM_ID"); print(matches[0])')"
xcrun notarytool store-credentials keypin-notary --keychain "$keychain" --apple-id "$AC_APPLE_ID" --team-id "$AC_TEAM_ID" --password "$AC_PASSWORD" >/dev/null
unset AC_APPLE_ID AC_PASSWORD
KEYPIN_ARCH=arm64 KEYPIN_PACKAGE_MODE=release bash scripts/package.sh
app="$root/build/KeyPin.app"
bash scripts/sign-app.sh "$app" "$identity" "$keychain"
python3 scripts/verify-package.py "$app" --release
codesign --display --verbose=4 "$app" 2> "$signing_dir/signature.txt"
python3 - "$signing_dir/signature.txt" <<'PY'
from pathlib import Path
import os,sys
text = Path(sys.argv[1]).read_text()
assert "Authority=Developer ID Application:" in text, "Not a Developer ID Application signature"
assert "TeamIdentifier=" + os.environ["AC_TEAM_ID"] in text, "Wrong signing team"
assert "runtime" in text and "Timestamp=" in text, "Hardened runtime or secure timestamp missing"
PY
ditto -c -k --sequesterRsrc --keepParent "$app" "$signing_dir/notarization.zip"
xcrun notarytool submit "$signing_dir/notarization.zip" --keychain-profile keypin-notary --keychain "$keychain" --wait --timeout 30m --output-format json > "$signing_dir/notarization.json"
python3 - "$signing_dir/notarization.json" <<'PY'
import json,sys
with open(sys.argv[1]) as stream: result=json.load(stream)
assert result.get("status") == "Accepted", "Apple notarization was not accepted"
print("PASS: Apple notarization accepted")
PY
xcrun stapler staple "$app"
xcrun stapler validate "$app"
codesign --verify --deep --strict "$app"
spctl --assess --type execute --verbose=2 "$app"
out="$root/build/release"
[[ ! -e "$out" ]] || { echo 'Release output already exists; refusing to mix artifacts' >&2; exit 1; }
mkdir -p "$out"
archive="$out/KeyPin-${tag#v}-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
binary_dir="$(swift build -c release --arch arm64 --disable-keychain --disable-netrc --show-bin-path)"
sparkle_tools="$(python3 scripts/sparkle-path.py tools "$binary_dir")"
"$sparkle_tools/generate_appcast" --ed-key-file "$private_key" --download-url-prefix "https://github.com/mreasonyang/keypin/releases/download/$tag/" --link https://github.com/mreasonyang/keypin --maximum-deltas 0 -o "$out/appcast.xml" "$out"
"$sparkle_tools/sign_update" --ed-key-file "$private_key" --verify "$out/appcast.xml"
python3 scripts/verify-appcast.py "$out/appcast.xml" "$archive" "$tag" "$app/Contents/Info.plist"
signature="$(python3 - "$out/appcast.xml" <<'PY'
import sys,xml.etree.ElementTree as ET
print(ET.parse(sys.argv[1]).find("./channel/item/enclosure").get("{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature"))
PY
)"
"$sparkle_tools/sign_update" --ed-key-file "$private_key" --verify "$archive" "$signature"
# Verify the exact final ZIP can be extracted without losing framework links or its staple.
ditto -x -k "$archive" "$signing_dir/extracted"
python3 scripts/verify-package.py "$signing_dir/extracted/KeyPin.app" --release
xcrun stapler validate "$signing_dir/extracted/KeyPin.app"
spctl --assess --type execute --verbose=2 "$signing_dir/extracted/KeyPin.app"
(cd "$out" && shasum -a 256 "$(basename "$archive")" appcast.xml > SHA256SUMS)
echo 'PASS: signed, notarized, stapled release ZIP and signed appcast verified'
