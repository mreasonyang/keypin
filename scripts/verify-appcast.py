#!/usr/bin/env python3
"""Check release metadata against the exact archived app before publication."""
from pathlib import Path
import base64
import plistlib
import sys
import xml.etree.ElementTree as ET

feed, archive, tag, plist = sys.argv[1:]
namespace = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
with open(plist, "rb") as stream:
    info = plistlib.load(stream)
items = ET.parse(feed).findall("./channel/item")
assert len(items) == 1, "Expected one release in this appcast"
item = items[0]
assert item.findtext(namespace + "version") == info["CFBundleVersion"]
assert item.findtext(namespace + "shortVersionString") == info["CFBundleShortVersionString"]
def normalized_version(value):
    parts = [int(part) for part in value.split(".")]
    while parts and parts[-1] == 0:
        parts.pop()
    return parts
assert normalized_version(item.findtext(namespace + "minimumSystemVersion")) == normalized_version(info["LSMinimumSystemVersion"])
assert item.findtext(namespace + "hardwareRequirements") == "arm64"
enclosure = item.find("enclosure")
assert enclosure is not None
assert enclosure.get("url") == f"https://github.com/mreasonyang/keypin/releases/download/{tag}/{Path(archive).name}"
assert int(enclosure.get("length")) == Path(archive).stat().st_size
assert len(base64.b64decode(enclosure.get(namespace + "edSignature"), validate=True)) == 64
print("PASS: appcast version, build, platform, archive URL, length, and EdDSA signature metadata")
