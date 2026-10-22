#!/bin/bash
# Both release.sh's EXIT trap and the workflow's always() step call this.
set +x
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && -n "${RUNNER_TEMP:-}" && "${GITHUB_RUN_ID:-}" =~ ^[0-9]+$ && "${GITHUB_RUN_ATTEMPT:-}" =~ ^[0-9]+$ ]] || {
  echo 'Release cleanup requires a GitHub Actions runner context' >&2; exit 1;
}
signing_dir="$RUNNER_TEMP/keypin-signing-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
keychain="$signing_dir/signing.keychain-db"
status=0
if [[ -e "$keychain" ]]; then
  security delete-keychain "$keychain" >/dev/null || status=$?
fi
# Even a keychain-service error must not retain the exported private-key file.
rm -rf "$signing_dir" || status=$?
exit "$status"
