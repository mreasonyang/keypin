#!/bin/bash
set -euo pipefail
[[ $# == 1 ]] || { echo 'Usage: embed-focus-helper.sh APP' >&2; exit 2; }
app="$1"
helper="$app/Contents/Helpers/KeyPin Focus Helper.app"
mkdir -p "$helper/Contents/MacOS"
cp "$app/Contents/MacOS/keypin" "$helper/Contents/MacOS/keypin-focus"
python3 - "$app/Contents/Info.plist" "$helper/Contents/Info.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1], 'rb') as stream:
    main = plistlib.load(stream)
helper = {
    'CFBundleIdentifier': 'app.keypin.focus-helper',
    'CFBundleExecutable': 'keypin-focus',
    'CFBundleName': 'KeyPin Focus Helper',
    'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': main['CFBundleShortVersionString'],
    'CFBundleVersion': main['CFBundleVersion'],
    'LSMinimumSystemVersion': main['LSMinimumSystemVersion'],
    'LSUIElement': True,
    'NSPrincipalClass': 'NSApplication',
}
# This helper never inherits the main app's updater keys.
with open(sys.argv[2], 'wb') as stream:
    plistlib.dump(helper, stream, sort_keys=False)
PY
# Only modify the helper copy. Its framework is in the containing app's Contents.
install_name_tool -add_rpath '@executable_path/../../../../Frameworks' "$helper/Contents/MacOS/keypin-focus"
