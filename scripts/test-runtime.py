#!/usr/bin/env python3
"""Launch packaged code and isolated native UI fixtures on the current host OS."""
from pathlib import Path
import argparse
import json
import platform
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("app", type=Path)
parser.add_argument("preview", type=Path)
args = parser.parse_args()


def run(arguments, expected=0):
    result = subprocess.run(list(map(str, arguments)), capture_output=True, timeout=25)
    # Never emit raw runtime logs; they may contain system diagnostics.
    assert result.returncode == expected, f"Runtime check failed with exit {result.returncode}"
    return result.stdout


binary = args.app / "Contents/MacOS/keypin"
assert b"keypin status" in run([binary, "--help"])
run([args.app / "Contents/Helpers/KeyPin Focus Helper.app/Contents/MacOS/keypin-focus", "--help"], expected=64)
preview = args.preview / "Contents/MacOS/keypin"
count = 0
for language in ("zh-Hans", "zh-Hant", "en", "ja", "ko"):
    for state in ("active", "first-confirm"):
        for appearance in ("light", "dark"):
            output = run([preview, "preview", state, language, appearance, "legacy", "--smoke-test"])
            assert b"PASS: preview window rendered" in output
            count += 1
print(json.dumps({"passed": True, "macOS": platform.mac_ver()[0], "architecture": platform.machine(),
                  "cli": True, "helperRejectedCLI": True, "renderedLegacyWindows": count}))
