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
source "$root/scripts/signing-session.sh"
KEYPIN_ARCH=universal KEYPIN_PACKAGE_MODE=release bash scripts/package.sh
app="$root/build/KeyPin.app"
bash scripts/sign-app.sh "$app" "$identity" "$keychain"
python3 scripts/verify-package.py "$app" --release --architecture universal
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
archive="$out/KeyPin-${tag#v}-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
binary_dir="$(swift build -c release --arch arm64 --arch x86_64 --disable-keychain --disable-netrc --show-bin-path)"
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
python3 scripts/verify-package.py "$signing_dir/extracted/KeyPin.app" --release --architecture universal
xcrun stapler validate "$signing_dir/extracted/KeyPin.app"
spctl --assess --type execute --verbose=2 "$signing_dir/extracted/KeyPin.app"
bash scripts/package-dmg.sh "$app" "$out/KeyPin-${tag#v}-universal.dmg"
bash scripts/notarize-dmg.sh "$out/KeyPin-${tag#v}-universal.dmg" "$identity" "$keychain" "$signing_dir"
python3 - "$signing_dir/notarization.json" "$app/Contents/Info.plist" "$out/verification.json" <<'PY'
from pathlib import Path
import json, os, plistlib, subprocess, sys
notarization = json.loads(Path(sys.argv[1]).read_text())
info = plistlib.loads(Path(sys.argv[2]).read_bytes())
receipt = {
    "schemaVersion": 1,
    "tag": os.environ["RELEASE_TAG"],
    "commit": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
    "version": info["CFBundleShortVersionString"],
    "build": info["CFBundleVersion"],
    "architecture": "universal",
    "architectures": ["arm64", "x86_64"],
    "workflowURL": f'https://github.com/mreasonyang/keypin/actions/runs/{os.environ["GITHUB_RUN_ID"]}',
    "notarization": {"id": notarization["id"], "status": notarization["status"]},
    "checks": {
        "developerID": True, "hardenedRuntime": True, "secureTimestamp": True,
        "staple": True, "gatekeeper": True, "archiveExtraction": True,
        "sparkleArchiveSignature": True, "sparkleFeedSignature": True,
    },
    "installer": {"format": "dmg", "developerID": True, "notarized": True, "staple": True, "gatekeeper": True},
    "installationAcceptance": "pending",
}
Path(sys.argv[3]).write_text(json.dumps(receipt, indent=2) + "\n")
PY
(cd "$out" && shasum -a 256 "$(basename "$archive")" "KeyPin-${tag#v}-universal.dmg" appcast.xml verification.json > SHA256SUMS)
echo 'PASS: signed, notarized, stapled release ZIP and signed appcast verified'
