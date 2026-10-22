#!/bin/bash
# Sparkle's documented inside-out signing order. Never sign with --deep.
set -euo pipefail
[[ $# -ge 1 && $# -le 3 ]] || { echo 'Usage: sign-app.sh APP [IDENTITY [KEYCHAIN]]' >&2; exit 2; }
app="$1"
identity="${2:--}"
framework="$app/Contents/Frameworks/Sparkle.framework"
version="$(cd "$framework/Versions/Current" && pwd -P)"
args=(--force --sign "$identity")
if [[ "$identity" != "-" ]]; then
  args+=(--options runtime --timestamp)
  [[ $# -ne 3 ]] || args+=(--keychain "$3")
fi
codesign "${args[@]}" "$version/XPCServices/Installer.xpc"
codesign "${args[@]}" --preserve-metadata=entitlements "$version/XPCServices/Downloader.xpc"
codesign "${args[@]}" "$version/Autoupdate"
codesign "${args[@]}" "$version/Updater.app"
codesign "${args[@]}" "$framework"
codesign "${args[@]}" "$app/Contents/Helpers/KeyPin Focus Helper.app"
codesign "${args[@]}" "$app"
codesign --verify --deep --strict "$app"
