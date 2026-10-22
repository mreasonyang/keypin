#!/usr/bin/env python3
"""Fail closed before expensive CI work; report names, never credential values."""
from pathlib import Path
import argparse
import base64
import os
import plistlib
import re
import subprocess

SECRET_NAMES = (
    "MACOS_CERTIFICATE_P12_BASE64", "MACOS_CERTIFICATE_PASSWORD",
    "AC_APPLE_ID", "AC_TEAM_ID", "AC_PASSWORD", "SPARKLE_PRIVATE_KEY",
)

def validate_tag(tag: str, info: dict) -> None:
    if not re.fullmatch(r"v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", tag):
        raise ValueError("Release tag must be an exact stable version, such as v0.0.14")
    if tag != "v" + info["CFBundleShortVersionString"]:
        raise ValueError("Release tag does not match CFBundleShortVersionString")
    if not re.fullmatch(r"[1-9][0-9]*", info["CFBundleVersion"]):
        raise ValueError("CFBundleVersion must be a positive integer")

def validate_credentials(env) -> None:
    missing = [name for name in (*SECRET_NAMES, "SPARKLE_PUBLIC_KEY") if not env.get(name, "").strip()]
    if missing:
        raise ValueError("Missing required release configuration: " + ", ".join(missing))
    for name, lengths in (("SPARKLE_PUBLIC_KEY", (32,)), ("SPARKLE_PRIVATE_KEY", (32, 96))):
        try:
            decoded = base64.b64decode(env[name].strip(), validate=True)
            if len(decoded) not in lengths or base64.b64encode(decoded).decode() != env[name].strip():
                raise ValueError()
        except ValueError:
            raise ValueError(f"Invalid {name} encoding or length") from None
    try:
        if not base64.b64decode("".join(env["MACOS_CERTIFICATE_P12_BASE64"].split()), validate=True):
            raise ValueError()
    except ValueError:
        raise ValueError("Invalid MACOS_CERTIFICATE_P12_BASE64 encoding") from None
    if not re.fullmatch(r"[A-Z0-9]{10}", env["AC_TEAM_ID"]):
        raise ValueError("AC_TEAM_ID must be a 10-character Apple team identifier")

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("tag")
    parser.add_argument("--check-credentials", action="store_true")
    parser.add_argument("--check-git", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    with (root / "packaging/Info.plist").open("rb") as stream:
        validate_tag(args.tag, plistlib.load(stream))
    if args.check_credentials:
        if os.environ.get("GITHUB_ACTIONS") != "true" or os.environ.get("GITHUB_REPOSITORY") != "mreasonyang/keypin":
            raise ValueError("Credential preflight is restricted to this repository's GitHub Actions runner")
        validate_credentials(os.environ)
    if args.check_git:
        def git(*parts):
            return subprocess.check_output(["git", *parts], cwd=root, text=True).strip()
        tagged = git("rev-parse", "--verify", f"refs/tags/{args.tag}^{{commit}}")
        if tagged != git("rev-parse", "HEAD"):
            raise ValueError("Checkout is not the exact requested tag commit")
        subprocess.run(["git", "merge-base", "--is-ancestor", tagged, "origin/main"], cwd=root, check=True)
    print("PASS: release preflight")

if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error)) from None
