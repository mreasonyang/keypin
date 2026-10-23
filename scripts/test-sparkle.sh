#!/bin/bash
# Real official-tool integration with a disposable key. Never accesses Keychain.
set +x
set -euo pipefail
umask 077
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
source_app="${1:-$root/build/KeyPin.app}"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/keypin-sparkle-fixture.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
mkdir -p "$fixture/archives" "$fixture/cache-home"
ditto "$source_app" "$fixture/KeyPin.app"
# Generate an ephemeral seed directly with CryptoKit; no generate_keys/Keychain.
cat > "$fixture/create-fixture-key.swift" <<'SWIFT'
import CryptoKit
import Foundation
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let key = Curve25519.Signing.PrivateKey()
try key.rawRepresentation.base64EncodedString().write(to: directory.appendingPathComponent("private-key"), atomically: true, encoding: .utf8)
try key.publicKey.rawRepresentation.base64EncodedString().write(to: directory.appendingPathComponent("public-key"), atomically: true, encoding: .utf8)
SWIFT
swift "$fixture/create-fixture-key.swift" "$fixture"
export SPARKLE_PUBLIC_KEY="$(cat "$fixture/public-key")"
swift scripts/validate-signing-key.swift "$fixture/private-key"
python3 scripts/configure-bundle.py "$fixture/KeyPin.app/Contents/Info.plist" release
bash scripts/sign-app.sh "$fixture/KeyPin.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$fixture/KeyPin.app/Contents/Info.plist")"
architecture="$(python3 scripts/macho.py "$fixture/KeyPin.app/Contents/MacOS/keypin")"
archive="$fixture/archives/KeyPin-$version-$architecture.zip"
ditto -c -k --sequesterRsrc --keepParent "$fixture/KeyPin.app" "$archive"
binary_dir="$(swift build -c release --disable-keychain --disable-netrc --show-bin-path)"
sparkle_tools="$(python3 scripts/sparkle-path.py tools "$binary_dir")"
# Foundation's cache location is redirected so extracted test archives are removed too.
CFFIXED_USER_HOME="$fixture/cache-home" "$sparkle_tools/generate_appcast" --ed-key-file "$fixture/private-key" --download-url-prefix "https://github.com/mreasonyang/keypin/releases/download/v$version/" --maximum-deltas 0 -o "$fixture/archives/appcast.xml" "$fixture/archives"
"$sparkle_tools/sign_update" --ed-key-file "$fixture/private-key" --verify "$fixture/archives/appcast.xml"
python3 scripts/verify-appcast.py "$fixture/archives/appcast.xml" "$archive" "v$version" "$fixture/KeyPin.app/Contents/Info.plist"
signature="$(python3 - "$fixture/archives/appcast.xml" <<'PY'
import sys,xml.etree.ElementTree as ET
print(ET.parse(sys.argv[1]).find('./channel/item/enclosure').get('{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature'))
PY
)"
"$sparkle_tools/sign_update" --ed-key-file "$fixture/private-key" --verify "$archive" "$signature"
printf '\nchanged\n' >> "$archive"
if "$sparkle_tools/sign_update" --ed-key-file "$fixture/private-key" --verify "$archive" "$signature" >/dev/null 2>&1; then
  echo 'Tampered archive was incorrectly accepted' >&2; exit 1
fi
python3 - "$fixture/archives/appcast.xml" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
feed = path.read_text()
assert '<title>' in feed
path.write_text(feed.replace('<title>', '<title>tampered ', 1))
PY
if "$sparkle_tools/sign_update" --ed-key-file "$fixture/private-key" --verify "$fixture/archives/appcast.xml" >/dev/null 2>&1; then
  echo 'Tampered feed was incorrectly accepted' >&2; exit 1
fi
echo 'PASS: official Sparkle ZIP/feed signing and tamper rejection; disposable key deleted on exit'
