#!/bin/bash
# Source only from trusted official release scripts. Never print credentials.
set +x
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "${GITHUB_REPOSITORY:-}" == mreasonyang/keypin ]] || {
  echo 'Signing is restricted to the official GitHub Actions runner' >&2; exit 1;
}
for name in MACOS_CERTIFICATE_P12_BASE64 MACOS_CERTIFICATE_PASSWORD AC_APPLE_ID AC_TEAM_ID AC_PASSWORD; do
  [[ -n "${!name:-}" ]] || { echo "Missing release configuration: $name" >&2; exit 1; }
done
[[ "$(uname -m)" == arm64 ]] || { echo 'Official releases require an arm64 runner' >&2; exit 1; }
[[ -n "${RUNNER_TEMP:-}" && "${GITHUB_RUN_ID:-}" =~ ^[0-9]+$ && "${GITHUB_RUN_ATTEMPT:-}" =~ ^[0-9]+$ ]] || exit 1
signing_dir="$RUNNER_TEMP/keypin-signing-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
[[ ! -e "$signing_dir" ]] || { echo 'Signing directory already exists' >&2; exit 1; }
mkdir -m 700 "$signing_dir"
trap 'bash "$root/scripts/cleanup-release.sh"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
keychain="$signing_dir/signing.keychain-db"
certificate="$signing_dir/certificate.p12"
private_key="$signing_dir/sparkle-private-key"
export KEYPIN_SIGNING_DIRECTORY="$signing_dir"
python3 - <<'PY'
from pathlib import Path
import base64, os
directory = Path(os.environ["KEYPIN_SIGNING_DIRECTORY"])
(directory / "certificate.p12").write_bytes(base64.b64decode("".join(os.environ["MACOS_CERTIFICATE_P12_BASE64"].split()), validate=True))
if os.environ.get("SPARKLE_PRIVATE_KEY"):
    (directory / "sparkle-private-key").write_text(os.environ["SPARKLE_PRIVATE_KEY"].strip())
PY
unset MACOS_CERTIFICATE_P12_BASE64 SPARKLE_PRIVATE_KEY
if [[ -f "$private_key" ]]; then swift scripts/validate-signing-key.swift "$private_key"; fi
keychain_password="$(openssl rand -base64 32)"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$certificate" -k "$keychain" -P "$MACOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
# codesign also requires a file-based identity's keychain in the user search
# list. This is an ephemeral official runner; never change the local user's list.
security list-keychains -d user -s "$keychain"
unset MACOS_CERTIFICATE_PASSWORD keychain_password
rm -f "$certificate"
identity="$(security find-identity -v -p codesigning "$keychain" | python3 -c 'import os,re,sys; matches=re.findall(r"([A-Fa-f0-9]{40}) \"Developer ID Application: [^\"]+ \("+re.escape(os.environ["AC_TEAM_ID"])+r"\)\"",sys.stdin.read()); len(matches)==1 or sys.exit("Expected exactly one valid Developer ID Application identity for AC_TEAM_ID"); print(matches[0])')"
xcrun notarytool store-credentials keypin-notary --keychain "$keychain" --apple-id "$AC_APPLE_ID" --team-id "$AC_TEAM_ID" --password "$AC_PASSWORD" >/dev/null
unset AC_APPLE_ID AC_PASSWORD
