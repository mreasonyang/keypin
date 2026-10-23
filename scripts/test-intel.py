#!/usr/bin/env python3
"""Compile XCTest for Intel, then explicitly run its matching XCTest driver."""
from pathlib import Path
import json
import re
import subprocess
import sys
from macho import architectures

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "build/architecture-checks"
OUT.mkdir(parents=True, exist_ok=True)
arguments = ["swift", "build", "--build-tests", "--arch", "x86_64",
             "--force-resolved-versions", "--disable-keychain", "--disable-netrc"]
build = subprocess.run(arguments, cwd=ROOT, capture_output=True, text=True)
report = {"architecture": "x86_64", "buildExitCode": build.returncode}
if build.returncode:
    report["diagnosticLocations"] = re.findall(
        r"/(?:Sources/keypin|Tests/keypinTests)/([A-Za-z0-9_]+\.swift):(\d+):(\d+): error:",
        build.stdout + build.stderr)
else:
    products = Path(subprocess.check_output(arguments + ["--show-bin-path"], cwd=ROOT, text=True).strip())
    bundles = list(products.glob("*.xctest"))
    assert len(bundles) == 1, "Expected one Intel XCTest bundle"
    executables = [path for path in (bundles[0] / "Contents/MacOS").iterdir() if path.is_file()]
    assert len(executables) == 1 and architectures(executables[0].read_bytes()) == frozenset(("x86_64",)), "Test executable is not Intel"
    runner = subprocess.check_output(["xcrun", "--find", "xctest"], text=True).strip()
    result = subprocess.run(["/usr/bin/arch", "-x86_64", runner, "-XCTest", "All", str(bundles[0])],
                            cwd=ROOT, capture_output=True, text=True)
    output = result.stdout + result.stderr
    summaries = [tuple(map(int, match)) for match in re.findall(
        r"Executed (\d+) tests?, with (\d+) failures? \((\d+) unexpected\)", output)]
    summary = max(summaries, default=(0, 0, 0))
    report.update(testExitCode=result.returncode, tests=summary[0], failures=summary[1], unexpected=summary[2])
    report["failingTests"] = re.findall(r"Test Case '-\[keypinTests\.([A-Za-z0-9_]+ [A-Za-z0-9_]+)\]' failed", output)
    report["runnerArchitectureMismatch"] = "incompatible architecture" in output
    report["rosettaUnavailable"] = "Bad CPU type" in output
report["passed"] = build.returncode == 0 and report.get("testExitCode") == 0 and report.get("tests", 0) > 0 and report.get("failures") == 0
(OUT / "intel-tests.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report))
sys.exit(0 if report["passed"] else 1)
