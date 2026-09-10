# MCSC Project Rules & Guidelines

This document outlines the strict architectural and performance standards for the MCSC (Mac Shortcut Control) project. Every contribution must adhere to these rules to maintain the application's lightweight profile.

## Core Mandate: Memory First
The primary goal of MCSC is to remain a "zero-footprint" utility. 
- **Memory Ceiling:** The baseline memory usage is currently **12.4 MB**. No feature addition or refactoring should push the memory usage beyond **13 MB** under normal operation.
- **Evaluation:** Every new feature must be evaluated for memory impact *before* implementation. If a feature requires a heavy framework or large data structures, it must be rejected or redesigned.

## Architectural Standards: MVVM
We follow a strict Model-View-ViewModel pattern to ensure testability and separation of concerns.

1.  **Models (`MCSC/Models`):**
    *   Pure logic and data structures.
    *   No dependencies on Services or ViewModels.
    *   Prefer `struct` over `class` for simple data to reduce heap allocation.
2.  **ViewModels (`MCSC/ViewModels`):**
    *   Orchestrates services and prepares data for the view (or handles event logic).
    *   Must use **weak references** for callbacks to prevent retain cycles.
    *   State should be minimal and focused.
3.  **Services (`MCSC/Services`):**
    *   Low-level wrappers for macOS APIs (Accessibility, Event Taps).
    *   **Rule:** Always cache system-wide objects (e.g., `AXUIElementCreateSystemWide`).
    *   **Rule:** Explicitly manage Core Foundation memory. Use `Unmanaged.passUnretained` unless you specifically need to take ownership of a CF object.
    *   **Rule:** Always provide a `stop()` or `invalidate()` method to clean up resources (run loops, ports, etc.).

## Memory Best Practices
- **Avoid SwiftUI for Core Logic:** Stay with AppKit/Core Graphics for background services. SwiftUI's runtime overhead is too high for this project's goals.
- **Lazy Initialization:** Initialize services only when they are actually needed.
- **CF Object Management:** Be extremely careful with `AXUIElement` and `CGEvent` objects. Ensure they are released or handled by Swift's ARC correctly.
- **Polling:** Avoid high-frequency timers. Prefer event-driven architecture (Event Taps, Notifications).

## Diagnostics & AI Agent Auditing
- **Zero-Footprint Logging:** Use Apple Unified Logging (`AppLogger.*`). Never use `print()` or heavy third-party crash reporters (Sentry, Firebase).
- **Background Only:** Do not add diagnostic UI/export dialogs. Logging and crash dumps run headlessly in the background for AI agents.
- **Audit Locations:**
  - `~/Library/Logs/MCSC/diagnostic_report.jsonl` (structured JSON lines via `OSLogStore`)
  - `~/Library/Logs/MCSC/crash.log` (fatal exception / signal stack traces)
  - `~/Library/Logs/DiagnosticReports/MCSC-*.ips` (macOS system crash reports)
- **Log Query Command:** `log show --predicate 'subsystem == "sj010.MCSC"' --info --debug --last 10m`
- See [docs/DIAGNOSTICS.md](docs/DIAGNOSTICS.md) for full audit guide and troubleshooting patterns.

## PR Checklist for Future Devs
- [ ] Memory usage verified to be under 13 MB.
- [ ] No new large dependencies added.
- [ ] Services include explicit cleanup logic.
- [ ] MVVM pattern is strictly followed.
- [ ] No retain cycles introduced (check `[weak self]` in closures).
- [ ] Key events instrumented via `AppLogger` with appropriate category and privacy flags.
