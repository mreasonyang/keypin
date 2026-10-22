#!/usr/bin/env python3
"""Credential-free regression checks for release preflight and bundle modes."""
from pathlib import Path
import base64
import importlib.util
import os
import plistlib
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("preflight", root / "scripts/release-preflight.py")
preflight = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preflight)
checks = 0

def rejects(action, expected):
    global checks
    try:
        action()
    except ValueError as error:
        assert expected in str(error), str(error)
    else:
        raise AssertionError("Expected rejection: " + expected)
    checks += 1

info = {"CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "16"}
preflight.validate_tag("v1.2.3", info)
checks += 1
for tag in ("main", "v1.2.3-rc1", "v01.2.3", "v1.2.3\n", "v1.2.3;echo test"):
    rejects(lambda: preflight.validate_tag(tag, info), "exact stable version")
rejects(lambda: preflight.validate_tag("v1.2.4", info), "does not match")
rejects(lambda: preflight.validate_tag("v1.2.3", dict(info, CFBundleVersion="0")), "positive integer")
rejects(lambda: preflight.validate_credentials({}), "Missing required")
# Deliberately synthetic fixtures, never read from a user's environment or Keychain.
fake = {name: "fixture" for name in preflight.SECRET_NAMES}
fake.update(SPARKLE_PUBLIC_KEY=base64.b64encode(b"p" * 32).decode(), SPARKLE_PRIVATE_KEY=base64.b64encode(b"s" * 32).decode(), MACOS_CERTIFICATE_P12_BASE64=base64.b64encode(b"fake-p12").decode(), AC_TEAM_ID="ABCDEFGHIJ")
preflight.validate_credentials(fake)
checks += 1
for name in (*preflight.SECRET_NAMES, "SPARKLE_PUBLIC_KEY"):
    rejects(lambda: preflight.validate_credentials(dict(fake, **{name: ""})), name)
for name in ("SPARKLE_PUBLIC_KEY", "SPARKLE_PRIVATE_KEY", "MACOS_CERTIFICATE_P12_BASE64", "AC_TEAM_ID"):
    rejects(lambda: preflight.validate_credentials(dict(fake, **{name: "invalid"})), name)
noncanonical = fake["SPARKLE_PUBLIC_KEY"][:-2] + "B="
assert base64.b64decode(noncanonical) == base64.b64decode(fake["SPARKLE_PUBLIC_KEY"])
rejects(lambda: preflight.validate_credentials(dict(fake, SPARKLE_PUBLIC_KEY=noncanonical)), "SPARKLE_PUBLIC_KEY")
with tempfile.TemporaryDirectory(prefix="keypin-release-fixtures-") as directory:
    plist = Path(directory) / "Info.plist"
    for mode, key, succeeds in (("development", "", True), ("development", fake["SPARKLE_PUBLIC_KEY"], True), ("release", fake["SPARKLE_PUBLIC_KEY"], True), ("release", "", False), ("preview", fake["SPARKLE_PUBLIC_KEY"], True), ("release", "invalid", False)):
        plist.write_bytes(plistlib.dumps(info))
        env = dict(os.environ, SPARKLE_PUBLIC_KEY=key)
        result = subprocess.run(["python3", str(root / "scripts/configure-bundle.py"), str(plist), mode], env=env, capture_output=True, text=True)
        assert (result.returncode == 0) == succeeds, result.stderr
        if succeeds:
            actual = plistlib.loads(plist.read_bytes())
            assert actual["SURequireSignedFeed"] and actual["SUVerifyUpdateBeforeExtraction"]
            assert not actual["SUEnableAutomaticChecks"] and not actual["SUAutomaticallyUpdate"]
            assert ("SUPublicEDKey" in actual) == bool(key and mode != "preview")
            assert ("SUFeedURL" in actual) == bool(key and mode != "preview")
        checks += 1
# Cleanup still removes every sensitive file if the keychain service fails.
with tempfile.TemporaryDirectory(prefix="keypin-cleanup-fixture-") as directory:
    temporary = Path(directory)
    signing = temporary / "keypin-signing-123-1"
    signing.mkdir()
    (signing / "signing.keychain-db").write_text("fake keychain")
    (signing / "sparkle-private-key").write_text("fake private key")
    (temporary / "security").write_text("#!/bin/bash\nexit 71\n")
    (temporary / "security").chmod(0o755)
    env = dict(os.environ, PATH=str(temporary) + ":" + os.environ["PATH"], GITHUB_ACTIONS="true", GITHUB_RUN_ID="123", GITHUB_RUN_ATTEMPT="1", RUNNER_TEMP=str(temporary))
    result = subprocess.run(["bash", str(root / "scripts/cleanup-release.sh")], env=env, capture_output=True)
    assert result.returncode == 71 and not signing.exists()
    checks += 1
# Real release command must refuse local use before touching any credentials.
env = {name: value for name, value in os.environ.items() if name not in (*preflight.SECRET_NAMES, "SPARKLE_PUBLIC_KEY", "GITHUB_ACTIONS", "GITHUB_REPOSITORY")}
with (root / "packaging/Info.plist").open("rb") as stream:
    version = plistlib.load(stream)["CFBundleShortVersionString"]
result = subprocess.run(["bash", str(root / "scripts/release.sh"), "--tag", "v" + version], env=env, capture_output=True, text=True)
assert result.returncode != 0 and "restricted" in result.stderr, result.stderr
checks += 1
print(f"PASS: {checks} release preflight and bundle-mode checks; synthetic fixtures only, no real credentials")
