#!/usr/bin/env python3
"""Verify a real bundle's metadata, embedded Sparkle, links, and signature."""
from pathlib import Path
import argparse
import base64
import plistlib
import subprocess
from macho import architectures, minimum_system_versions, version_tuple, THIN, FAT

parser = argparse.ArgumentParser()
parser.add_argument("app", type=Path)
parser.add_argument("--release", action="store_true")
parser.add_argument("--architecture", choices=("arm64", "x86_64", "universal"))
args = parser.parse_args()
app = args.app.resolve()
binary = app / "Contents/MacOS/keypin"
framework = app / "Contents/Frameworks/Sparkle.framework"
helper = app / "Contents/Helpers/KeyPin Focus Helper.app"
helper_binary = helper / "Contents/MacOS/keypin-focus"
with (app / "Contents/Info.plist").open("rb") as stream:
    info = plistlib.load(stream)
assert binary.is_file() and binary.stat().st_mode & 0o111, "Missing executable"
assert framework.is_dir(), "Missing Sparkle.framework"
assert (framework / "Versions/Current").is_symlink(), "Sparkle symlinks were not preserved"
assert (framework / "Sparkle").is_symlink(), "Sparkle executable link was not preserved"
assert (app / "Contents/Resources/Sparkle-LICENSE").stat().st_size, "Missing Sparkle license"
assert (app / "Contents/Resources/LICENSE").stat().st_size, "Missing KeyPin license"
with (helper / "Contents/Info.plist").open("rb") as stream:
    helper_info = plistlib.load(stream)
assert helper_info["CFBundleIdentifier"] == "app.keypin.focus-helper" != info["CFBundleIdentifier"], "Focus helper must have a separate process identity"
assert helper_info["CFBundleExecutable"] == "keypin-focus"
assert helper_info["LSUIElement"] is True
assert helper_info["LSMinimumSystemVersion"] == info["LSMinimumSystemVersion"], "Focus helper system requirement differs from the main app"
assert not any(key.startswith("SU") for key in helper_info), "Focus helper must never configure an updater"
assert helper_binary.is_file() and helper_binary.stat().st_mode & 0o111
main_architectures = architectures(binary.read_bytes())
expected = frozenset(("arm64", "x86_64")) if args.architecture == "universal" else (
    frozenset((args.architecture,)) if args.architecture else main_architectures)
assert main_architectures == expected, "Main executable architecture differs from the requested package"
assert architectures(helper_binary.read_bytes()) == expected, "Focus helper architecture differs from the main app"
assert expected <= architectures((framework / "Sparkle").read_bytes()), "Sparkle is missing a required architecture"
seen = set()
minimum = version_tuple(info["LSMinimumSystemVersion"])
for candidate in app.rglob("*"):
    if not candidate.is_file() or candidate.resolve() in seen:
        continue
    seen.add(candidate.resolve())
    with candidate.open("rb") as stream:
        magic = stream.read(4)
    if magic in THIN or magic in FAT:
        assert expected <= architectures(candidate.read_bytes()), f"Embedded code is missing a required architecture: {candidate.relative_to(app)}"
        targets = minimum_system_versions(candidate.read_bytes())
        assert all(targets[cpu] <= minimum for cpu in expected), f"Embedded code requires a newer macOS than advertised: {candidate.relative_to(app)}"
assert helper_info["CFBundleVersion"] == info["CFBundleVersion"]
assert info["SUVerifyUpdateBeforeExtraction"] is True
assert info["SURequireSignedFeed"] is True
assert info["SUEnableAutomaticChecks"] is False
assert info["SUAutomaticallyUpdate"] is False
if args.release:
    assert info.get("SUPublicEDKey"), "Release public key is missing"
    assert info.get("SUFeedURL") == "https://github.com/mreasonyang/keypin/releases/latest/download/appcast.xml"
if info.get("SUPublicEDKey"):
    key = info["SUPublicEDKey"]
    decoded = base64.b64decode(key, validate=True)
    assert len(decoded) == 32 and base64.b64encode(decoded).decode() == key, "Invalid or noncanonical Sparkle public key"
linked = subprocess.check_output(["otool", "-L", str(binary)], text=True)
assert "@rpath/Sparkle.framework/" in linked, "Binary does not link Sparkle via @rpath"
loads = subprocess.check_output(["otool", "-l", str(binary)], text=True)
assert any(f"path {path} (offset" in loads for path in ("@executable_path/../Frameworks", "@loader_path/../Frameworks")), "Missing embedded-framework rpath"
helper_loads = subprocess.check_output(["otool", "-l", str(helper_binary)], text=True)
assert "path @executable_path/../../../../Frameworks (offset" in helper_loads, "Missing focus-helper framework rpath"
helper_linked = subprocess.check_output(["otool", "-L", str(helper_binary)], text=True)
assert "@rpath/Sparkle.framework/" in helper_linked
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
print(f"PASS: {app.name} {info['CFBundleShortVersionString']} ({info['CFBundleVersion']}), embedded Sparkle, separate focus helper and signature")
