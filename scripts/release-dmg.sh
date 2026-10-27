#!/bin/bash
# Add an installer for an existing release; never rebuild or replace the app.
set +x
set -euo pipefail
[[ $# == 3 && "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 2
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
tag="$1"
archive="$2"
output="$3"
source "$root/scripts/signing-session.sh"
ditto -x -k "$archive" "$signing_dir/extracted"
app="$signing_dir/extracted/KeyPin.app"
python3 - "$tag" "$app/Contents/Info.plist" <<'PY'
import plistlib, sys
from importlib.machinery import SourceFileLoader
preflight = SourceFileLoader('preflight', 'scripts/release-preflight.py').load_module()
with open(sys.argv[2], 'rb') as stream: preflight.validate_tag(sys.argv[1], plistlib.load(stream))
PY
bash scripts/package-dmg.sh "$app" "$output"
bash scripts/notarize-dmg.sh "$output" "$identity" "$keychain" "$signing_dir"
(cd "$(dirname "$output")" && shasum -a 256 "$(basename "$output")" > "$(basename "$output").sha256")
