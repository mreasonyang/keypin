#!/usr/bin/env python3
"""Find the framework/tools from the resolved SwiftPM binary artifact."""
from pathlib import Path
import argparse

parser = argparse.ArgumentParser()
parser.add_argument("kind", choices=("framework", "tools", "license"))
parser.add_argument("binary_dir", type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
artifacts = root / ".build/artifacts"
if args.kind == "framework":
    candidates = [args.binary_dir / "Sparkle.framework"]
    candidates += sorted(artifacts.glob("**/macos*/Sparkle.framework"))
elif args.kind == "tools":
    candidates = sorted(artifacts.glob("**/bin/generate_appcast"))
else:
    candidates = sorted((root / ".build/checkouts").glob("[Ss]parkle/LICENSE"))
    candidates += sorted(artifacts.glob("**/LICENSE"))
for candidate in candidates:
    if candidate.exists():
        if args.kind == "framework" and not (candidate / "Sparkle").is_file():
            continue
        print(candidate.parent if args.kind == "tools" else candidate)
        break
else:
    raise SystemExit(f"Resolved Sparkle {args.kind} not found; run swift package resolve first.")
