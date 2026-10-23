#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

mode="${KEYPIN_PACKAGE_MODE:-development}"
[[ "$mode" == development || "$mode" == release ]] || { echo 'Unknown package mode' >&2; exit 2; }
if [[ "$mode" == release && -z "${SPARKLE_PUBLIC_KEY:-}" ]]; then
  echo 'Release packaging requires SPARKLE_PUBLIC_KEY' >&2
  exit 1
fi
build_args=(-c release --disable-keychain --disable-netrc)
architecture="${KEYPIN_ARCH:-$(uname -m)}"
case "$architecture" in
  universal) build_args+=(--arch arm64 --arch x86_64) ;;
  arm64|x86_64) build_args+=(--arch "$architecture") ;;
  *) echo 'Unsupported package architecture' >&2; exit 2 ;;
esac
swift build "${build_args[@]}"
binary_dir="$(swift build "${build_args[@]}" --show-bin-path)"
binary="$binary_dir/keypin"
[[ -x "$binary" ]] || { echo "Built executable not found: $binary" >&2; exit 1; }
framework="$(python3 scripts/sparkle-path.py framework "$binary_dir")"
sparkle_license="$(python3 scripts/sparkle-path.py license "$binary_dir")"

build_dir="$root/build"
app="$build_dir/KeyPin.app"
mkdir -p "$build_dir"
staging_dir="$(mktemp -d "$build_dir/.keypin-stage.XXXXXX")"
staged_app="$staging_dir/KeyPin.app"
old_app="$staging_dir/replaced.app"
publication_started=0
committed=0
had_app=0

exists() { [[ -e "$1" || -L "$1" ]]; }
cleanup() {
  status=$?
  trap - EXIT INT TERM HUP
  rollback_ok=1
  if [[ "$publication_started" == 1 && "$committed" == 0 ]]; then
    # Infer completed renames from the filesystem. This also covers a signal
    # arriving between a successful rename and the following shell command.
    if ! exists "$staged_app" && exists "$app"; then
      if ! mv "$app" "$staged_app"; then rollback_ok=0; fi
    fi
    if [[ "$had_app" == 1 ]]; then
      if exists "$old_app"; then
        if exists "$app" || ! mv "$old_app" "$app"; then rollback_ok=0; fi
      fi
      if ! exists "$app"; then rollback_ok=0; fi
    fi
  fi
  if [[ "$rollback_ok" == 1 ]]; then
    rm -rf "$staging_dir"
  else
    echo "Package replacement failed; recovery files preserved at: $staging_dir" >&2
    status=1
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources" "$staged_app/Contents/Frameworks"
cp "$binary" "$staged_app/Contents/MacOS/keypin"
cp "$root/packaging/Info.plist" "$staged_app/Contents/Info.plist"
python3 "$root/scripts/configure-bundle.py" "$staged_app/Contents/Info.plist" "$mode"
cp "$root/LICENSE" "$staged_app/Contents/Resources/LICENSE"
cp "$sparkle_license" "$staged_app/Contents/Resources/Sparkle-LICENSE"
ditto "$framework" "$staged_app/Contents/Frameworks/Sparkle.framework"
bash "$root/scripts/embed-focus-helper.sh" "$staged_app"
for lang in en zh-Hans zh-Hant ja ko; do
  mkdir -p "$staged_app/Contents/Resources/$lang.lproj"
  cp "$root/packaging/$lang.lproj/"* "$staged_app/Contents/Resources/$lang.lproj/"
done
swift "$root/packaging/make-icon.swift" "$staged_app/Contents/Resources/AppIcon.icns"
[[ -s "$staged_app/Contents/Resources/AppIcon.icns" ]]
plutil -lint "$staged_app/Contents/Info.plist" >/dev/null
bash "$root/scripts/sign-app.sh" "$staged_app"
verify_args=("$staged_app" --architecture "$architecture")
[[ "$mode" != release ]] || verify_args+=(--release)
python3 "$root/scripts/verify-package.py" "${verify_args[@]}"

# Only a complete, verified package may replace the app. Renames remain on the
# same volume. The replaced app exists only inside this transaction and is
# discarded after success; failed publication restores it to the current path.
if exists "$app"; then had_app=1; fi
publication_started=1
if [[ "$had_app" == 1 ]]; then
  mv "$app" "$old_app"
fi
mv "$staged_app" "$app"
committed=1
echo "$app"
