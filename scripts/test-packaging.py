#!/usr/bin/env python3
"""Exercise package.sh transaction behavior entirely inside temporary fixtures.

Swift and codesign are stubs. This is not native build, signing, or launch evidence.
"""

from pathlib import Path
import hashlib
import os
import shutil
import subprocess
import tempfile


APP_NAME = "KeyPin.app"
PHASES = ("success", "first-install", "icon", "sign", "sign-downloader", "verify", "missing-framework", "framework-copy", "rpath", "retire", "publish", "published-error")


def run_fixture(source: Path, base: Path, phase: str) -> None:
    fixture = base / phase
    shutil.copytree(source / "scripts", fixture / "scripts")
    tools = fixture / "fake-tools"
    tools.mkdir()
    shutil.copytree(source / "packaging", fixture / "packaging")
    shutil.copyfile(source / "LICENSE", fixture / "LICENSE")
    (tools / "swift").write_text('''#!/bin/bash
set -euo pipefail
if [[ "$1" == "build" ]]; then
  if [[ " $* " == *" --show-bin-path "* ]]; then
    echo "$PWD/.build/custom-release"
  else
    mkdir -p .build/custom-release
    echo new-binary > .build/custom-release/keypin
    chmod +x .build/custom-release/keypin
    mkdir -p .build/checkouts/Sparkle
    echo 'Sparkle license fixture' > .build/checkouts/Sparkle/LICENSE
    if [[ "$FAIL_PHASE" != "missing-framework" ]]; then
      framework=.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework
      mkdir -p "$framework/Versions/B/XPCServices/Installer.xpc" "$framework/Versions/B/XPCServices/Downloader.xpc" "$framework/Versions/B/Updater.app"
      echo framework > "$framework/Versions/B/Sparkle"
      echo autoupdate > "$framework/Versions/B/Autoupdate"
      ln -s B "$framework/Versions/Current"
      ln -s Versions/Current/Sparkle "$framework/Sparkle"
    fi
  fi
else
  [[ "$FAIL_PHASE" != "icon" ]] || exit 61
  echo icon > "$2"
fi
''')
    (tools / "codesign").write_text('''#!/bin/bash
set -euo pipefail
if [[ "$1" == "--verify" ]]; then
  [[ "$FAIL_PHASE" != "verify" ]] || exit 62
else
  [[ "$FAIL_PHASE" != "sign" ]] || exit 63
  [[ "$FAIL_PHASE" != "sign-downloader" || "$*" != *Downloader.xpc* ]] || exit 67
  echo "$*" >> "$FIXTURE_ROOT/sign-order"
fi
''')
    (tools / "otool").write_text('''#!/bin/bash
if [[ "$1" == -L ]]; then
  echo '@rpath/Sparkle.framework/Versions/B/Sparkle'
elif [[ "$FAIL_PHASE" != "rpath" ]]; then
  echo '         path @executable_path/../Frameworks (offset 12)'
fi
''')
    (tools / "ditto").write_text('''#!/bin/bash
[[ "$FAIL_PHASE" != "framework-copy" ]] || exit 68
exec /usr/bin/ditto "$@"
''')
    (tools / "mv").write_text('''#!/bin/bash
set -euo pipefail
if [[ "$FAIL_PHASE" == "publish" && "$1" == *"/.keypin-stage."*"/$PACKAGE_APP_NAME" && "$2" == "$FIXTURE_ROOT/build/$PACKAGE_APP_NAME" && ! -e "$FIXTURE_ROOT/failed-once" ]]; then
  touch "$FIXTURE_ROOT/failed-once"
  exit 64
fi
if [[ "$FAIL_PHASE" == "retire" && "$1" == "$FIXTURE_ROOT/build/$PACKAGE_APP_NAME" && "$2" == *"/replaced.app" && ! -e "$FIXTURE_ROOT/failed-once" ]]; then
  touch "$FIXTURE_ROOT/failed-once"
  exit 65
fi
if [[ "$FAIL_PHASE" == "published-error" && "$1" == *"/.keypin-stage."*"/$PACKAGE_APP_NAME" && "$2" == "$FIXTURE_ROOT/build/$PACKAGE_APP_NAME" && ! -e "$FIXTURE_ROOT/failed-once" ]]; then
  /bin/mv "$@"
  touch "$FIXTURE_ROOT/failed-once"
  exit 66
fi
exec /bin/mv "$@"
''')
    for tool in tools.iterdir():
        tool.chmod(0o755)
    app = fixture / "build" / APP_NAME
    if phase != "first-install":
        app.mkdir(parents=True)
        (app / "current-marker").write_bytes(b"current app bytes")
    home = fixture / "home"
    command = home / ".local/bin/keypin"
    command.parent.mkdir(parents=True)
    command.write_bytes(b"user owned command")
    before = hashlib.sha256(command.read_bytes()).hexdigest()
    env = os.environ.copy()
    env.update(
        PATH=str(tools) + ":" + env["PATH"],
        FAIL_PHASE=phase,
        FIXTURE_ROOT=str(fixture),
        PACKAGE_APP_NAME=APP_NAME,
        KEYPIN_PACKAGE_MODE="development",
        SPARKLE_PUBLIC_KEY="",
    )
    result = subprocess.run(
        ["/bin/bash", str(fixture / "scripts/package.sh")],
        env=env, text=True, capture_output=True,
    )
    assert not command.is_symlink(), phase
    assert hashlib.sha256(command.read_bytes()).hexdigest() == before, phase
    if phase in ("success", "first-install"):
        assert result.returncode == 0, result.stderr
        assert (app / "Contents/MacOS/keypin").read_text() == "new-binary\n"
        assert (app / "Contents/Resources/LICENSE").read_bytes() == (source / "LICENSE").read_bytes()
        assert (app / "Contents/Resources/Sparkle-LICENSE").read_text() == "Sparkle license fixture\n"
        assert (app / "Contents/Frameworks/Sparkle.framework/Versions/Current").is_symlink()
        signs = (fixture / "sign-order").read_text().splitlines()
        assert len(signs) == 6, signs
        assert all(name in line for name, line in zip(("Installer.xpc", "Downloader.xpc", "Autoupdate", "Updater.app", "Sparkle.framework", "KeyPin.app"), signs))
        assert "--preserve-metadata=entitlements" in signs[1]
        assert all("--deep" not in line for line in signs)
        assert not (app / "current-marker").exists()
    else:
        assert result.returncode != 0, phase
        assert (app / "current-marker").read_bytes() == b"current app bytes", phase
        assert not (app / "Contents/MacOS/keypin").exists(), phase
    assert list((fixture / "build").iterdir()) == [app], phase
    print(f"PASS {phase}: exit={result.returncode}; user command preserved; only current app remains")


def main() -> None:
    source = Path(__file__).resolve().parent.parent
    base = Path(tempfile.mkdtemp(prefix="keypin-package-transaction-"))
    print("ISOLATED FIXTURE ONLY: Swift and codesign are stubbed; this does not verify a real release.")
    try:
        for phase in PHASES:
            run_fixture(source, base, phase)
    except BaseException:
        print(f"Failed fixture retained for inspection: {base}")
        raise
    else:
        shutil.rmtree(base)
    print(f"PASS: {len(PHASES)} scenarios. Only temporary fixture files were modified.")


if __name__ == "__main__":
    main()
