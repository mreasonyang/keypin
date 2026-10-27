#!/usr/bin/env python3
"""Read the shipped Finder metadata, not just the packaging settings."""
from pathlib import Path
import sys
from ds_store import DSStore

volume = Path(sys.argv[1])
assert (volume / "Applications").is_symlink()
assert (volume / "Applications").readlink() == Path("/Applications")
assert (volume / ".background.tiff").stat().st_size > 0
with DSStore.open(str(volume / ".DS_Store"), "r") as store:
    assert store["KeyPin.app"]["Iloc"] == (166, 190), "KeyPin must be on the left"
    assert store["Applications"]["Iloc"] == (474, 190), "Applications must be on the right"
    window = store["."]["bwsp"]
    assert window["WindowBounds"] == "{{200, 160}, {640, 400}}"
    assert not any(window[k] for k in ("ShowToolbar", "ShowSidebar", "ShowStatusBar", "ShowPathbar"))
    icons = store["."]["icvp"]
    assert icons["arrangeBy"] == "none" and icons["iconSize"] == 96
    assert icons["backgroundType"] == 2 and icons["backgroundImageAlias"]
print("PASS: shipped Finder layout, left-to-right drag targets, background and 640x400 window")
