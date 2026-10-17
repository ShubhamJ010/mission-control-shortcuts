# Contributing to MCSC

Thank you for your interest in contributing to MCSC! To preserve the utility's lightweight profile and zero-footprint behavior, all contributions must follow these standards.

---

## 1. Core Principles

- **Memory Ceiling (< 13 MB):** Baseline memory usage is ~12.4 MB. No feature addition or refactor may push memory beyond 13 MB.
- **No Tests:** Do not add or write automated unit, integration, or UI tests; this codebase maintains zero test files.
- **MVVM Architecture:** Strict separation between Models (`MCSC/Models`), ViewModels (`MCSC/ViewModels`), and Services (`MCSC/Services`).
- **AppKit / Core Graphics Only:** Never use SwiftUI for background service or core event-processing logic.
- **Zero-Footprint Logging:** Use Apple Unified Logging via `AppLogger.*`. Never use `print()` or third-party loggers/crash reporters.

---

## 2. Development Setup

### Requirements
- **macOS:** macOS 27.0 or later
- **Xcode:** Xcode 27+ with macOS 27 SDK

### Quick Start
Clone the repository and inspect available developer tasks:

```bash
git clone https://github.com/ShubhamJ010/mission-control-shortcuts.git
cd mission-control-shortcuts
make help
```

### Essential Commands

| Command | Action |
| --- | --- |
| `make build` | Compile Release configuration via `xcodebuild` |
| `make run` | Build, install to `/Applications/MCSC.app`, and launch |
| `make install` | Build and install to `/Applications/MCSC.app` without launching |
| `make stop` | Cleanly terminate any running instance of MCSC |
| `make clean` | Delete `build/` derived data and build artifacts |
| `make logs` | Stream live Unified Logs (`subsystem == "sj010.MCSC"`) |
| `make audit` | Audit memory budget (<=13MB) & zero leaks (`make bench` / `make profile` alias) |
| `make audit-stress` | Audit memory under simulated Mission Control cycle |
| `make lint` | Run SwiftLint rules |
| `make format` | Auto-format Swift files using SwiftFormat |
| `make reset-tcc` | Reset macOS Accessibility permissions for clean onboarding test |

---

## 3. Persistent Accessibility Permissions

When developing locally with ad-hoc signing (`CODE_SIGN_IDENTITY="-"`), macOS generates a new code hash on every build. macOS Accessibility (TCC) treats the rebuilt binary as a modified or unverified application, requiring you to remove (`-`) and re-add (`+`) MCSC in System Settings.

### Fix: Create a local `MCSC-Dev` Certificate (One Time)

1. Open **Keychain Access** (`/System/Applications/Utilities/Keychain Access.app`).
2. In the menu bar: **Keychain Access** → **Certificate Assistant** → **Create a Certificate...**
3. Configure:
   - **Name:** `MCSC-Dev`
   - **Identity Type:** Self Signed Root
   - **Certificate Type:** Code Signing
4. Click **Create**, then click **Done**.

The `Makefile` automatically detects `MCSC-Dev` in your keychain and uses it for signing. Once granted in **System Settings → Privacy & Security → Accessibility**, your permission survives all future rebuilds without needing `-` or `+`.

---

## 4. Pull Request Checklist

Before submitting a PR:
- [ ] Memory verified to be under 13 MB (`make audit`).
- [ ] Code formatted with `make format` and passes `make lint`.
- [ ] No unit/UI test files added.
- [ ] Retain cycles prevented (closures use `[weak self]`).
- [ ] Low-level resources (CF objects, event taps) properly released.
- [ ] Key events instrumented with `AppLogger`.
