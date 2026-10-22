#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
swift build --disable-keychain --disable-netrc
binary_dir="$(swift build --disable-keychain --disable-netrc --show-bin-path)"
framework="$(python3 scripts/sparkle-path.py framework "$binary_dir")"
sparkle_license="$(python3 scripts/sparkle-path.py license "$binary_dir")"
app="$root/build/KeyPin Preview.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$binary_dir/keypin" "$app/Contents/MacOS/keypin"
cp packaging/Info.plist "$app/Contents/Info.plist"
cp LICENSE "$app/Contents/Resources/LICENSE"
cp "$sparkle_license" "$app/Contents/Resources/Sparkle-LICENSE"
rm -rf "$app/Contents/Frameworks/Sparkle.framework"
ditto "$framework" "$app/Contents/Frameworks/Sparkle.framework"
python3 scripts/configure-bundle.py "$app/Contents/Info.plist" preview
bash scripts/embed-focus-helper.sh "$app"
for lang in en zh-Hans zh-Hant ja ko; do
  mkdir -p "$app/Contents/Resources/$lang.lproj"
  cp "packaging/$lang.lproj/Localizable.strings" "$app/Contents/Resources/$lang.lproj/"
done
swift "$root/packaging/make-icon.swift" "$app/Contents/Resources/AppIcon.icns"
bash scripts/sign-app.sh "$app"
python3 scripts/verify-package.py "$app"
if [[ "${1:-}" != "--build-only" ]]; then
  "$app/Contents/MacOS/keypin" preview "${1:-active}" "${2:-zh-Hans}" "${3:-light}" "${4:-}"
fi
