#!/bin/bash
# Test-only older-build client. Never uploads a Release or changes the stable feed.
# Reuses the exact published executable; signs/notarizes changed bundle metadata.
set +x
set -euo pipefail
umask 077
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
[[ "${GITHUB_ACTIONS:-}" == true && "${GITHUB_REPOSITORY:-}" == mreasonyang/keypin && "$(uname -m)" == arm64 ]] || {
  echo 'Fixture signing is restricted to the official arm64 Actions runner' >&2; exit 1;
}
[[ -n "${RUNNER_TEMP:-}" && "${GITHUB_RUN_ID:-}" =~ ^[0-9]+$ && "${GITHUB_RUN_ATTEMPT:-}" =~ ^[0-9]+$ ]] || exit 1
python3 - <<'PY'
import os,re
names=('MACOS_CERTIFICATE_P12_BASE64','MACOS_CERTIFICATE_PASSWORD','AC_APPLE_ID','AC_TEAM_ID','AC_PASSWORD')
assert all(os.environ.get(name,'').strip() for name in names), 'Missing signing configuration'
assert re.fullmatch(r'[A-Z0-9]{10}', os.environ['AC_TEAM_ID']), 'Invalid signing team identifier'
PY
signing_dir="$RUNNER_TEMP/keypin-signing-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
[[ ! -e "$signing_dir" ]] || { echo 'Signing directory already exists' >&2; exit 1; }
mkdir -m 700 "$signing_dir"
trap 'bash "$root/scripts/cleanup-release.sh"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
export KEYPIN_SIGNING_DIRECTORY="$signing_dir"
source_zip="$signing_dir/published.zip"
curl --fail --silent --show-error --location --retry 3 \
  https://github.com/mreasonyang/keypin/releases/download/v0.0.16/KeyPin-0.0.16-arm64.zip -o "$source_zip"
python3 - "$source_zip" <<'PY'
from pathlib import Path
import hashlib,sys
assert hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest() == 'fdfe363910a90cedf8a0c1bafbb255f5db0c528b42d785ee0a3573bc45cfec3a', 'Published source archive mismatch'
PY
ditto -x -k "$source_zip" "$signing_dir/source"
app="$signing_dir/source/KeyPin.app"
python3 scripts/verify-package.py "$app" --release
codesign --verify --deep --strict "$app"
spctl --assess --type execute "$app"
python3 - "$app" <<'PY'
from pathlib import Path
import hashlib,json,plistlib,sys
app=Path(sys.argv[1]);path=app/'Contents/Info.plist'
info=plistlib.loads(path.read_bytes())
assert info['CFBundleShortVersionString']=='0.0.16' and info['CFBundleVersion']=='17'
assert info['CFBundleIdentifier']=='app.keypin'
assert info['SUFeedURL']=='https://github.com/mreasonyang/keypin/releases/latest/download/appcast.xml'
assert info['SURequireSignedFeed'] and info['SUVerifyUpdateBeforeExtraction']
baseline={'sourceTag':'v0.0.16','sourceArchiveSHA256':'fdfe363910a90cedf8a0c1bafbb255f5db0c528b42d785ee0a3573bc45cfec3a','executableSHA256':hashlib.sha256((app/'Contents/MacOS/keypin').read_bytes()).hexdigest(),'feed':info['SUFeedURL'],'publicVerificationKeyUnchanged':True,'fixtureVersion':'0.0.15','fixtureBuild':'16','publishedTargetVersion':'0.0.16','publishedTargetBuild':'17','purpose':'Update installation fixture derived from the published executable; not a historical released 0.0.15 build.'}
Path(app.parents[1]/'fixture-source.json').write_text(json.dumps(baseline,indent=2)+'\n')
info.update(CFBundleShortVersionString='0.0.15',CFBundleVersion='16',KeyPinUpdateTestFixture=True)
path.write_bytes(plistlib.dumps(info,sort_keys=False))
helper_path=app/'Contents/Helpers/KeyPin Focus Helper.app/Contents/Info.plist'
helper=plistlib.loads(helper_path.read_bytes())
helper.update(CFBundleShortVersionString='0.0.15',CFBundleVersion='16')
helper_path.write_bytes(plistlib.dumps(helper,sort_keys=False))
PY
keychain="$signing_dir/signing.keychain-db"
certificate="$signing_dir/certificate.p12"
python3 - <<'PY'
from pathlib import Path
import base64,os
Path(os.environ['KEYPIN_SIGNING_DIRECTORY'],'certificate.p12').write_bytes(base64.b64decode(''.join(os.environ['MACOS_CERTIFICATE_P12_BASE64'].split()),validate=True))
PY
unset MACOS_CERTIFICATE_P12_BASE64
keychain_password="$(openssl rand -base64 32)"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$certificate" -k "$keychain" -P "$MACOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain"
unset MACOS_CERTIFICATE_PASSWORD keychain_password
rm -f "$certificate"
identity="$(security find-identity -v -p codesigning "$keychain" | python3 -c 'import os,re,sys; matches=re.findall(r"([A-Fa-f0-9]{40}) \"Developer ID Application: [^\"]+ \("+re.escape(os.environ["AC_TEAM_ID"])+r"\)\"",sys.stdin.read()); len(matches)==1 or sys.exit("Expected exactly one Developer ID Application identity"); print(matches[0])')"
xcrun notarytool store-credentials keypin-notary --keychain "$keychain" --apple-id "$AC_APPLE_ID" --team-id "$AC_TEAM_ID" --password "$AC_PASSWORD" >/dev/null
unset AC_APPLE_ID AC_PASSWORD
bash scripts/sign-app.sh "$app" "$identity" "$keychain"
python3 scripts/verify-package.py "$app" --release
ditto -c -k --sequesterRsrc --keepParent "$app" "$signing_dir/notarization.zip"
xcrun notarytool submit "$signing_dir/notarization.zip" --keychain-profile keypin-notary --keychain "$keychain" --wait --timeout 30m --output-format json > "$signing_dir/notarization.json"
python3 - "$signing_dir/notarization.json" <<'PY'
import json,sys
assert json.load(open(sys.argv[1])).get('status')=='Accepted', 'Fixture notarization was not accepted'
print('PASS: fixture notarization accepted')
PY
xcrun stapler staple "$app"
xcrun stapler validate "$app"
codesign --verify --deep --strict "$app"
spctl --assess --type execute "$app"
out="$root/build/update-fixture"
[[ ! -e "$out" ]] || { echo 'Fixture output already exists' >&2; exit 1; }
mkdir -p "$out"
archive="$out/KeyPin-update-fixture-0.0.15-16.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
python3 - "$signing_dir" "$archive" <<'PY'
from pathlib import Path
import datetime,hashlib,json,os,sys
signing=Path(sys.argv[1]);archive=Path(sys.argv[2])
receipt=json.loads((signing/'fixture-source.json').read_text())
receipt.update(createdAt=datetime.datetime.now(datetime.timezone.utc).isoformat(),archive=archive.name,archiveSHA256=hashlib.sha256(archive.read_bytes()).hexdigest(),notarization=json.loads((signing/'notarization.json').read_text())['status'],workflowURL=f'https://github.com/mreasonyang/keypin/actions/runs/{os.environ["GITHUB_RUN_ID"]}')
(archive.parent/'fixture.json').write_text(json.dumps(receipt,indent=2)+'\n')
PY
echo 'PASS: signed and notarized update fixture; stable Release/feed unchanged'
