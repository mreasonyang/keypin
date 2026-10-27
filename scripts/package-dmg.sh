#!/bin/bash
# Wrap an already signed and stapled app without changing its contents.
set -euo pipefail
[[ $# == 2 ]] || { echo 'Usage: package-dmg.sh APP OUTPUT.dmg' >&2; exit 2; }
root="$(cd "$(dirname "$0")/.." && pwd)"
app="$1"
output="$2"
[[ ! -e "$output" && "$output" == *.dmg ]] || { echo 'DMG output must be new' >&2; exit 1; }
python3 "$root/scripts/verify-package.py" "$app" --release --architecture universal
xcrun stapler validate "$app"
spctl --assess --type execute "$app"
stage="$(mktemp -d)"
mounted=0
cleanup() {
  status=$?
  trap - EXIT
  if [[ "$mounted" == 1 ]]; then hdiutil detach "$stage/mounted" >/dev/null || status=1; fi
  rm -rf "$stage"
  exit "$status"
}
trap cleanup EXIT
mkdir "$stage/mounted"
dmg_python="${KEYPIN_DMG_PYTHON:-python3}"
"$dmg_python" -m dmgbuild -s "$root/packaging/dmg/settings.py" \
  -D "app=$app" -D "background=$root/packaging/dmg/background.png" KeyPin "$output"
hdiutil verify "$output" >/dev/null
hdiutil attach -quiet -readonly -nobrowse -mountpoint "$stage/mounted" "$output"
mounted=1
"$dmg_python" "$root/scripts/verify-dmg-layout.py" "$stage/mounted"
[[ -L "$stage/mounted/Applications" && "$(readlink "$stage/mounted/Applications")" == /Applications ]]
python3 - "$app" "$stage/mounted/KeyPin.app" <<'PY'
from pathlib import Path
import hashlib, os, stat, sys
def manifest(root):
    root = Path(root)
    entries = {}
    for directory, folders, files in os.walk(root, followlinks=False):
        for name in folders + files:
            path = Path(directory) / name
            mode = path.lstat().st_mode
            value = ('link', os.readlink(path)) if stat.S_ISLNK(mode) else (
                ('directory',) if stat.S_ISDIR(mode) else ('file', hashlib.sha256(path.read_bytes()).hexdigest(), mode & 0o111))
            entries[str(path.relative_to(root))] = value
    return entries
assert manifest(sys.argv[1]) == manifest(sys.argv[2]), 'DMG changed application contents or links'
print('PASS: mounted app bytes, executable bits and symlinks exactly match the published app')
PY
python3 "$root/scripts/verify-package.py" "$stage/mounted/KeyPin.app" --release --architecture universal
xcrun stapler validate "$stage/mounted/KeyPin.app"
spctl --assess --type execute "$stage/mounted/KeyPin.app"
echo 'PASS: DMG mounts with the exact notarized Universal app and Applications link'
