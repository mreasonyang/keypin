#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
for script in scripts/*.sh; do bash -n "$script"; done
python3 scripts/test-release.py
python3 scripts/test-packaging.py
python3 scripts/check-localizations.py
swift test --disable-keychain --disable-netrc
KEYPIN_PACKAGE_MODE=development bash scripts/package.sh
python3 scripts/verify-package.py "$root/build/KeyPin.app"
bash scripts/test-sparkle.sh "$root/build/KeyPin.app"
"$root/build/KeyPin.app/Contents/MacOS/keypin" --help >/dev/null
if [[ "${KEYPIN_CI_ARCHIVE:-0}" == 1 ]]; then
  mkdir -p "$root/build/development"
  archive="$root/build/development/KeyPin-development-$(uname -m).zip"
  ditto -c -k --sequesterRsrc --keepParent "$root/build/KeyPin.app" "$archive"
  (cd "$root/build/development" && shasum -a 256 "$(basename "$archive")" > SHA256SUMS)
fi
echo 'PASS: local/CI checks; development package only (ad-hoc, not notarized)'
