# KeyPin

[中文](README.md) · **English**

**Keep your Mac locked to your chosen input source across apps.**

KeyPin is a lightweight macOS menu bar utility that helps keep your preferred input source active across apps. When switching between applications—such as moving between code editors, terminals, browsers, and chats—KeyPin detects input source changes and attempts to switch back to your designated target, reducing accidental language switches.

> **Requirements**: macOS 13 or later on Apple silicon or Intel Mac. The Universal download includes both architectures. Liquid Glass on macOS 26+, with native materials and buttons on earlier systems. Supports Simplified Chinese, Traditional Chinese, English, Japanese, and Korean.

[Website](https://keypin.kyun.si) · [Releases and Downloads](https://github.com/mreasonyang/keypin/releases) · [Report an Issue](https://github.com/mreasonyang/keypin/issues)

## Usage

### Menu Bar Interaction

1. **Initial Setup**: Open KeyPin, choose an enabled input source to keep, and decide whether to enable keeping right away and launch at login.
2. **Everyday Control**: Click the input source icon in your menu bar anytime to change the target or pause enforcement.

| Goal | Action | Details |
| --- | --- | --- |
| **Keep an input source** | Click it in the panel list | Immediately switches to it and enables automatic keeping |
| **Switch sources freely** | Choose the top item “Follow system” | Pauses keeping, remembers your target, and leaves the current source untouched |
| **Start automatically on login** | Turn on “Launch at login” in Settings | Automatically launches when you log in to your Mac session and stays in the menu bar |
| **Change interface language** | Select your language in Settings | Supports 5 built-in languages |
| **Quit application** | Click “Quit” at the bottom of the main panel | Closing the main window leaves KeyPin running in the menu bar |

### Icon and Status Feedback

- **Menu Bar Icon**: The menu bar displays the artwork of the input source macOS is currently using (falling back to KeyPin's keyboard glyph if the source lacks an icon). When set to “Follow system”, the icon appears dimmed.
- **Target vs. Current**: When keeping is enabled, the checkmark (✓) marks the target input source; when paused, it moves to “Follow system”. The “Current” badge always indicates the input source macOS is actively using in real time.
- **Conflict backoff**: Repeated switching within one app temporarily pauses automatic keeping and shows a retry prompt, limiting input-source and focus contention. Persistent conflicts extend the pause; switching apps or explicitly retrying resumes keeping.

For detailed panel mechanics, onboarding flows, and state definitions, see the [Interface and Behavior Reference](docs/behavior.md) (in Chinese).

## Installation

### Using a Pre-built App Bundle

Download the Universal DMG directly from GitHub Releases using the [website](https://keypin.kyun.si). The same installer supports Apple silicon and Intel Macs. Open the DMG and drag `KeyPin.app` to the `Applications` shortcut, then:

1. Move the app to its permanent location (such as `/Applications`) before opening it. If you plan to enable launch at login, settle the app location first.
2. Double-click to launch.

> [!NOTE]
> Official releases are built, Developer ID signed, and notarized by GitHub Actions before publication. If no official release is available yet, wait for publication or build from source. Actions artifacts labeled development and default local builds are ad-hoc signed; they do not establish notarization or real-device acceptance.

### In-App Updates

Open Settings > About and choose Check for Updates. Sparkle checks GitHub Releases, downloads a new version, and handles installation and relaunch. Automatic checks and automatic downloading/installation are off by default and can be enabled separately in About. Updates preserve your input-source configuration and launch-at-login setting.

Local development builds without an update public key show updates as unavailable. Version 0.0.14 and earlier cannot install updates in-app; manually install the first official version that includes automatic updates.

### Building from Source

Requires Xcode / Swift with the **macOS 26 SDK**:

```sh
./scripts/package.sh
open ./build/KeyPin.app
```

The compiled application is generated at `build/KeyPin.app`. Manual use does not require installing the CLI wrapper or enabling launch at login.

## Command Line

KeyPin includes a built-in CLI inside the app bundle. Before configuring a convenient user command in your PATH, you can invoke it directly from the bundle:

```sh
"./build/KeyPin.app/Contents/MacOS/keypin" list
"./build/KeyPin.app/Contents/MacOS/keypin" status --json
```

### Initial CLI Setup

To invoke `keypin` directly from your shell as a user command, find your desired input source ID via `list` above, then run `install` from the application bundle (example using a common input source ID):

```sh
# Replace com.apple.keylayout.ABC with an actual ID from your list output
"./build/KeyPin.app/Contents/MacOS/keypin" install "com.apple.keylayout.ABC"
```

> [!NOTE]
> The `install` command **saves the target source, enables keeping, registers the current user's login item, and creates a user-level symlink at `~/.local/bin/keypin`**.
> It operates strictly within your user profile and does not modify system directories or change your shell `PATH`; ensure `~/.local/bin` is in your `PATH`, or call the binary with its full path.

### Command Reference

After `keypin` is available in your shell, common commands include:

| Command | Description |
| --- | --- |
| `keypin status` | Show runtime status (active source, pinned target, keep state) |
| `keypin list` | List all available input source IDs and localized names |
| `keypin pause` | Pause keeping without changing the current source or forgetting the target |
| `keypin resume` | Save intent to resume keeping (does not spawn GUI if stopped) |
| `keypin toggle` | Toggle keeping state on or off |
| `keypin set <id>` | Save target and switch once, preserving the existing keeping switch |
| `keypin apply` | Attempt to switch back to the saved target again (subject to system and secure input constraints) |
| `keypin open` | Open the main application window |
| `keypin install <id>` | Save target, enable keeping, register login item, and link CLI command |
| `keypin uninstall` | Unregister login item and stop background agent (preserves config and CLI link) |

### Scripting and Automation

Every command except `help` accepts the `--json` flag (e.g. `keypin status --json`).

In `--json` mode:

- Exit code is `0` on success, `1` on failure.
- Standard output receives a single JSON object.
- `list --json` returns a `sources` array on success; other status and mutation commands return a `status` object on success; failures return an `error` object with machine-readable `code` and `message`.
- Automation scripts should check `ok` and `error.code`, rather than parsing human-readable localized text.

For full command arguments, JSON schemas, error codes, and paths, see the [CLI and Configuration Reference](docs/cli.md) (in Chinese).

## Privacy and Data

- **Completely On-Device**: KeyPin requires no account. All input switching, enforcement, and preferences remain strictly on your Mac.
- **Update Connections**: Official builds contact GitHub and its asset delivery services when you request an update check or enable automatic checks. Sparkle verifies update signatures. System profiling is disabled, and KeyPin does not upload typed text or input-source configuration. Local builds without an update public key do not start the update service.
- **Configuration Storage**: User preferences are saved in JSON format at:

  ```
  ~/Library/Application Support/KeyPin/config.json
  ```

  This stores the target source ID, keeping state, language preference, and onboarding completion. File writes use cross-process locks and atomic file replacement.

## Compatibility and Limitations

- **System Input Sources**: KeyPin only operates on input sources currently enabled in macOS System Settings > Keyboard. If a target is removed from macOS, KeyPin flags it as missing and prompts you to select another.
- **Secure Input**: When macOS activates Secure Input (e.g. password fields), KeyPin pauses automatic switching until the secure context ends.
- **CJK and Vietnamese Input Sources**: Switching these input sources uses an isolated, lightweight focus helper. Because third-party apps handle focus transitions differently, typing behavior in complex apps should be verified in real-world use.

## Development and Contributing

For instructions on running tests, packaging validation, localization linting, and isolated preview modes, refer to the [Development Guide](CONTRIBUTING.md) (in Chinese).

When [reporting issues](https://github.com/mreasonyang/keypin/issues), please include:

- macOS version and KeyPin version
- The input source ID or name
- The affected application
- Clear steps to reproduce the issue

## License

This project is licensed under the [MIT License](LICENSE). The Sparkle update framework has its own license; its notices are included in the app bundle. See the [Release Guide](docs/releasing.md) (in Chinese) for the release process and maintainer setup.
