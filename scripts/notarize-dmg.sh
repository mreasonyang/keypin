#!/bin/bash
set +x
set -euo pipefail
[[ $# == 4 && "${GITHUB_ACTIONS:-}" == true && "${GITHUB_REPOSITORY:-}" == mreasonyang/keypin ]] || exit 2
dmg="$1"
identity="$2"
keychain="$3"
signing_dir="$4"
codesign --force --sign "$identity" --keychain "$keychain" --timestamp "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile keypin-notary --keychain "$keychain" --wait --timeout 30m --output-format json > "$signing_dir/dmg-notarization.json"
python3 - "$signing_dir/dmg-notarization.json" <<'PY'
import json, sys
with open(sys.argv[1]) as stream: result = json.load(stream)
assert result.get('status') == 'Accepted', 'DMG notarization was not accepted'
print('PASS: Apple DMG notarization accepted')
PY
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
codesign --verify --strict "$dmg"
spctl --assess --type open --context context:primary-signature "$dmg"
echo 'PASS: Developer ID signed, notarized, stapled DMG accepted by Gatekeeper'
