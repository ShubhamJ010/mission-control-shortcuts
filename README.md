<div align="center">

<img src="./docs/assets/icon.png" width="96" alt="MCSC app icon">

# MCSC: Mission Control Shortcuts

### Keyboard shortcuts and trackpad gestures for Mission Control

[![Platform](https://img.shields.io/badge/platform-macOS-000000)](https://www.apple.com/macos/)
[![Language](https://img.shields.io/badge/language-Swift-FA7343)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-blue)](https://opensource.org/licenses/MIT)

A free, open-source menu bar app that turns Mission Control previews into
windows you can act on. Type to find one, swipe or press to close,
minimize, tile, quit, or eject it.

[Features](#features) · [Installation](#installation) · [Usage](#usage) · [Documentation](#documentation) · [Tests](#tests)

<img src="./docs/assets/preview.gif" alt="MCSC in action: type-to-select and window actions inside Mission Control" width="800">

</div>

---

Mission Control already shows you every open window. MCSC makes those previews
actionable: point at one, type its app name, or flick two fingers, and the
window closes, minimizes, tiles, quits, or ejects its disk image.

It listens only while Mission Control is open. On the desktop, in Launchpad,
and inside Finder folder stacks it stays completely silent, so your normal
shortcuts never change. A keystroke pre-filter ensures typing in other apps
costs MCSC zero Accessibility IPC. Everything runs event-driven in a
single AppKit process that idles around 12 MB of RAM with 0% CPU (measured on
macOS 15.7.3 with Mission Control open and closed; see
[PERFORMANCE.md](./docs/PERFORMANCE.md)).

## Features

- **Type to find any window**: Start typing an app name inside Mission Control. Fuzzy matching ranks open windows instantly, marks the best match with a native highlight, and displays a Dock-style query pill. `Tab` cycles matches, and `Enter` focuses the window.
- **14 trackpad gestures**: Pinch to close or force quit, swipe up to fill the screen, swipe down to minimize, and double-tap to resize. Each gesture includes a `Cmd` modifier variant for fourteen distinct actions under two fingers. Gestures fire once per finger lift to avoid accidental repeats.
- **Tile and resize directly**: Fill the screen, expand by 33%, snap to 60%, or almost maximize to 90%, plus a reversible Make Smaller action that returns windows to their original size.
- **Eject disk images from the overview**: Hover over a Finder window showing a mounted DMG, pinch in or press `Cmd+W`, and MCSC closes the window and unmounts the volume. No manual trip to the Finder sidebar.
- **Feedback you can feel**: Every action flashes its corresponding SF Symbol at the cursor paired with a tactile click, confirming the action immediately.
- **The Dock answers too**: Hover over Dock icons on the desktop to trigger app-level shortcuts and gestures. Point at a window preview for window actions, or point at the Dock for app actions. App Exposé stays suppressed mid-gesture.
- **Strictly scoped**: Nothing is intercepted outside Mission Control.
- **Configurable**: Toggle individual shortcuts and gestures from the menu bar, or enable launch at login.

## Installation

MCSC needs the Accessibility permission to inspect windows and intercept
input while Mission Control is open:

```text
System Settings → Privacy & Security → Accessibility
```

The first launch prompts for it, and the app starts as soon as permission is granted.
Without it, MCSC runs but cannot act on windows.

### Homebrew (Recommended)

```bash
brew tap ShubhamJ010/tap
brew trust ShubhamJ010/tap # on Homebrew 6+
brew install --cask mcsc
```

*The cask automatically strips quarantine attributes during install.*

### Downloaded release builds

Release binaries are unsigned, so macOS blocks them on first open. Clear the
quarantine flag with:

```bash
xattr -cr /Applications/MCSC.app
```

(Adjust the path if you keep the app elsewhere.)

To sign a distributed build yourself:

```bash
sentinel sign --app MCSC.app --identity "Developer ID Application: Your Name (TeamID)"
codesign -dv --verbose=4 MCSC.app
```

### Build from source

```bash
git clone https://github.com/ShubhamJ010/mission-control-shortcuts.git
cd mission-control-shortcuts
open MCSC.xcodeproj
```

Build the `MCSC` scheme and run.

## Usage

MCSC lives in the menu bar with no Dock icon. Use its menu to toggle individual
shortcuts and gestures, enable launch at login, or quit.

Once Mission Control is open, point at any preview or just start typing.

### Type-to-select

| Input | Action |
| --- | --- |
| Type letters / numbers | Fuzzy-match window owner names, highlight best match |
| `Enter` | Activate selected window, dismiss Mission Control |
| `Tab` / `Down` | Cycle forward through matches |
| `Up` | Cycle backward through matches |
| `Esc` / `Backspace` | Clear query / delete last character |

### Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| `Cmd + W` | Close window or tab (mounted volume → close + eject) |
| `Cmd + Q` | Force quit app (mounted volume → close + eject) |
| `Cmd + M` | Minimize window |
| `Cmd + H` | Hide app |
| `Cmd + Space` | Recover a stuck Mission Control / Spotlight state |

### Trackpad gestures

| Gesture | Action | With `Cmd` |
| --- | --- | --- |
| Pinch in | Close window / quit app | Force quit app |
| Swipe left | Close active tab | Close window |
| Swipe right | Reopen closed tab | New window |
| Swipe up | Fill screen | Make larger (+33%) |
| Swipe down | Minimize window | Hide app |
| Double tap | Reasonable size (60%) | Almost maximize (90%) |

On windows showing an ejectable volume, pinch-in and swipe-left eject instead
of closing. Hover buttons on each preview offer Close, Minimize (`Option`), and
Force Quit (`Command`) without touching the keyboard.

## Documentation

- [SHORTCUTS.md](./docs/SHORTCUTS.md) - Every shortcut, fuzzy finding details, and hover buttons.
- [GESTURES.md](./docs/GESTURES.md) - Every gesture and how recognition works.
- [MISSION_CONTROL.md](./docs/MISSION_CONTROL.md) - How MCSC detects and scopes to Mission Control.
- [MOVE_WINDOW_TO_DESKTOP.md](./docs/MOVE_WINDOW_TO_DESKTOP.md) - Moving windows across Spaces.
- [SYMBOLS.md](./docs/SYMBOLS.md) - The SF Symbol map behind feedback overlays.
- [PERFORMANCE.md](./docs/PERFORMANCE.md) - The memory and CPU budget, profiling recipes, and measured numbers.
- [ARCHITECTURE.md](./docs/ARCHITECTURE.md) - MVVM design, event taps, and low-level choices.

## Tests

127 unit and performance tests, including wall-clock budget tests that fail
on hot-path regressions (frame-throttle rate, keystroke pre-filter cost,
detection-cache short-circuit, and window-list matching):

```bash
./Tests/run_tests.sh
```

## Credits

- Inspired by [Mission Control Plus](https://www.folivora.ai/missionscontrol)
  and [Swish](https://highlyopinionated.co/swish/), whose gesture model MCSC
  follows within Mission Control.
- Special thanks to
  [OpenMissionControl PR #3](https://github.com/nohackjustnoobb/OpenMissionControl/pull/3/changes)
  by `nohackjustnoobb`. Studying that implementation unlocked private Exposé
  SPIs (`CoreDockSendNotification`) and Quartz event routing inside Mission
  Control after I had been stuck on both for weeks.
- Built with AI coding tools as a learning project. If you want a polished,
  production-grade experience, support the original developers above.

Licensed under the MIT License.
