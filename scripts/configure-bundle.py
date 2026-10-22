#!/usr/bin/env python3
"""Configure a copied bundle, never the source plist. Public data only."""
from pathlib import Path
import base64
import os
import plistlib
import sys

path = Path(sys.argv[1])
mode = sys.argv[2]
if mode not in ("development", "release", "preview"):
    raise SystemExit("Unknown package mode")
key = os.environ.get("SPARKLE_PUBLIC_KEY", "").strip()
if mode == "release" and not key:
    raise SystemExit("Release packaging requires SPARKLE_PUBLIC_KEY")
if key:
    try:
        decoded = base64.b64decode(key, validate=True)
        assert len(decoded) == 32 and base64.b64encode(decoded).decode() == key
    except (ValueError, AssertionError):
        raise SystemExit("SPARKLE_PUBLIC_KEY must encode a 32-byte Ed25519 public key")
with path.open("rb") as source:
    info = plistlib.load(source)
# Preview never starts the updater, even if the caller has a public key set.
if key and mode != "preview":
    info["SUPublicEDKey"] = key
    info["SUFeedURL"] = "https://github.com/mreasonyang/keypin/releases/latest/download/appcast.xml"
else:
    info.pop("SUPublicEDKey", None)
    info.pop("SUFeedURL", None)
info["SUVerifyUpdateBeforeExtraction"] = True
info["SURequireSignedFeed"] = True
info["SUEnableAutomaticChecks"] = False
info["SUAutomaticallyUpdate"] = False
if mode == "preview":
    info.update(CFBundleIdentifier="app.keypin.preview", CFBundleName="KeyPin Preview", CFBundleDisplayName="KeyPin Preview")
with path.open("wb") as target:
    plistlib.dump(info, target, sort_keys=False)
