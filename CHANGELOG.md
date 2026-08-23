# Changelog

## Unreleased

- **Performance Audit — Hot-Path IPC & Allocations**: Systematic audit of the running build (`footprint` / `heap` / `vmmap` / `sample`) with five fixes:
  - **Zero AX IPC while typing**: every `keyDown` previously paid an `AXUIElementCopyElementAtPosition` hit-test (plus title-bar/frontmost reads) before the router discarded it. A cheap allocation-free pre-filter (`ShortcutActionRouter.isShortcutCandidate`) now rejects plain typing and untracked keys before any Accessibility call. Verified: 1 `SLWindowListCopyWindowInfo` per 5 s idle sample (was 7–9; ~38 in 0.5.0-beta).
  - **Pre-thread-hop frame throttle**: `MultitouchFrameGate` throttles non-empty trackpad frames to 30 Hz inside the framework callback, before the array + closure allocation and main-queue hop (previously 60–120 wakeups/s, throttled only after crossing threads). Empty frames bypass the gate so finger-lift is observed instantly.
  - **Cached frontmost-app element**: `isFrontmostWindow` no longer re-creates its `AXUIElementCreateApplication` up to 30×/s in the title-bar hover path (pid-keyed cache).
  - **Zombie-poll fix**: `MissionControlHoverService.deinit` now invalidates `windowFetchTimer` — a dealloc without `stop()` previously kept polling windows every 0.5 s forever.
  - **Smaller detection scan**: Mission Control window-list copy now uses `.excludeDesktopElements`.
- **Performance Regression Tests**: New `Tests/PerformanceTests.swift` — 9 wall-clock budget tests guarding the frame gate (30 Hz cap, concurrency safety, throughput), keystroke pre-filter (correctness + 100k-call budget), MC detection cache short-circuit, and window-list fuzzy-match/sort throughput. Registered in `TestRunner.swift` / `run_tests.sh`.
- **Title Bar Gestures & Shortcuts Outside Mission Control**: New opt-in setting that applies all gestures and Cmd-shortcuts while hovering the title bar of the frontmost window in normal desktop mode. Hover detection is a ~28 pt top-strip geometry check plus an `AccessibilityService.isFrontmostWindow(_:)` focused-window check, so only the frontmost window responds. Toggle via Settings → General (`isTitleBarActionsOutsideMCEnabled`, persisted under `mcsc.titleBarActionsOutsideMC.enabled`). Both this and the Dock outside-MC toggle now default to **off**.

## 0.5.2-beta (22 Aug 2026)

- **Make Smaller (−33%) resize action**: New gesture action that shrinks the window from its center by ~33% (1/1.33 factor, the inverse of Make Larger) clamped to a 200×100 pt minimum and screen bounds. Available as a selectable action in the gesture settings pop-ups (not bound by default), with app-level parity for Dock targets. Flashes a new `.makeSmaller` cursor feedback mode (`arrow.down.right.and.arrow.up.left`, accent palette). Adds `MakeSmallerAction` (`WindowActions/SizeActions.swift:58`) and `MakeSmallerAppAction` (`AppActions.swift:134`).
- **Lint & Style Hardening**: Fixed all SwiftLint / SwiftFormat violations blocking CI (`empty_count`, `identifier_name`, `line_length`, `cyclomatic_complexity`, `function_body_length`). Renamed `CoreDockSendNotification` → `coreDockSendNotification` (`@_silgen_name` preserved), table-drove `ShortcutConfiguration.init`, split `ShortcutActionRouter` into focused helpers. Auto-formatted 54 files.
- **Routing Refactor**: `ShortcutActionRouter` decomposed from 57 → <25 cyclomatic complexity via `routePureCmdShortcut`, `routeShiftTabActions`, `routeShiftWindowSizeActions`, `routeShiftDesktopActions`.
- **Cursor Symbol Fix**: `spaceRight` / `spaceLeft` now correctly use `arrow.right/left.square.fill` (was `arrowshape.*.circle.fill`) to match spec and fix `CursorFeedbackOverlayTests`.

## 0.5.1-beta (21 Aug 2026)

- **Cursor-Flash Symbol Animation Refinements**: Polished every cursor feedback flash:
  - **Close / Force Quit**: added a `.bounce.up.byLayer` entry effect on top of the hover-style scale-up.
  - **Minimize / Hide**: base symbol now morphs from the outline `minus.circle.fill` / `eye.slash.circle.fill` into their filled counterparts via `.replace.downUp.byLayer`.
  - **Eject**: `eject.fill` base morphs into `eject.circle.fill` via `.replace.magic` (fallback: `.downUp.wholeSymbol`).
  - **Tab swipes**: `.wiggle.byLayer` now plays unconditionally (dropped the pre-macOS 26 `.bounce` fallback) and unused `.bounce` / `.appear` cases were removed.
  - **Clipping fix**: reduced the flash scale-up from 1.08× → 1.03× so glyphs no longer clip at the panel bounds.

## 0.5.0-beta (21 Aug 2026)

- **Dock Gestures & Shortcuts Outside Mission Control**: All dock-targeted keyboard shortcuts (`Cmd+W`, `Cmd+Q`, `Cmd+M`, `Cmd+H`) and multitouch gestures (pinch-in, pinch-out, horizontal/vertical swipes, two-finger double-tap) now work directly over Dock icons in normal desktop mode without needing Mission Control open. Fully configurable via `isDockActionsOutsideMCEnabled` and status bar menu toggle (`"Dock Gestures & Shortcuts (outside MC)"`).
- **App Exposé & Context Menu Suppression (`DockInteractionSuppressor`)**: Introduced a dedicated low-level Quartz event tap service that intercepts `smartMagnify` (type 32), `quickLook`, `magnify`, and click events over the Dock when gestures/double-taps are active. This completely prevents macOS App Exposé from inadvertently opening during two-finger double taps while preserving single-click app switching.
- **Direct Dock AX Hit-Testing**: Enhanced `AccessibilityService.getElement(at:)` with a direct `AXUIElement` application hit-test fallback when system-wide hit testing returns `-25200` (`kAXErrorCannotComplete`) over the Dock process.
- **Pinch-Out Gesture for Fullscreen & Windowing**: New `PinchOutRecognizer` (extracted shared `BasePinchRecognizer`) — `pinch-out` toggles fullscreen (`kAXZoomButtonAttribute` + `CoreDockSendNotification("com.apple.expose.awake")`), `Cmd+pinch-out` creates a new window (`Cmd+N`). Includes distinct haptic (`alignment → levelChange` vs `levelChange → levelChange` for pinch-in) and `.fullscreen` cursor feedback (`arrow.down.left.and.arrow.up.right.circle.fill`, black/green palette). Toggle via `isPinchOutEnabled` / menu bar. See `PinchOutRecognizer.swift`, `WindowActions/WindowControlActions.swift:ToggleFullscreenAction`, `HapticService.swift:pinchOut`.
- **Dock Parity for Tiling / Fullscreen**: `SwipeDown` (Fill / Make Larger), `DoubleTap` (Reasonable 60% / Almost 90%), and `Pinch-Out` (Fullscreen) now resolve Dock targets via `AppActions.swift:111` — swiping/resizing on a Dock icon in Mission Control acts on the app's windows. `GestureActionRouter` previously returned `.none` for Dock on those paths.
- **Fullscreen Hover + Event-Tap Resilience**: `PreviewCloseButtonOverlay.Mode.fullscreen` (4th mode, green `arrow.down…circle.fill`) added to hover button; `MissionControlWindowActions.swift:performFullscreen` provides Mission Control dictionary path (`CoreDockSendNotification`) fallback. `EventTapService` auto-recreates tap on `.tapDisabledByTimeout` / `.tapDisabledByUserInput`.
- **Tab-Close Reliability Fix**: `AccessibilityService.findActiveTabCloseButton(in:)` now recursively descends bounded depth 8, skipping `AXWebArea`, to find `AXTabGroup` under `AXGroup` wrappers (Chrome). Fixes `Cmd+W` / swipe-left previously falling back to unreliable `Cmd+W`. Fallback now focuses hovered window via `kAXFocusedAttribute` first.
- **macOS 14+ Symbol-Effect Fallbacks**: Dropped macOS 26-only `.wiggle` / `.magic` requirements — `.wiggle.byLayer` falls back to `.bounce` on <26, `.magic(fallback: .upUp)` falls back to `.upUp.byLayer`. Prevents missing animations on 14/15.
- **MVVM Reorganization**: Moved to strict MVVM layout — `Models/Actions/`, `Models/Gestures/`, `Services/{Accessibility,EventTap,Haptics,LaunchAtLogin,MissionControl,Multitouch}`, `ViewModels/Routing/`, `Utilities/`. Extracted `ShortcutActionRouter` / `GestureActionRouter` / `ActionRegistry` / `ShortcutConfiguration` and `ScreenGeometry` / `SymbolImageFactory` / `KeyboardEventPoster`.
- **README Feature Advertising**: Expanded `README.md:34` from 7 to 11 bullets — new standalone entries for Hover Buttons, Cursor Feedback + Haptics (14 modes), Window Tiling & Tab Control, Auto-Eject, Dock-Aware Targeting, and Fully Configurable toggles.
- **Includes 0.4.1 & 0.4.2**: This beta rolls up **Mounted Volume Auto-Eject (0.4.1)** and **Type-to-Select Fuzzy Finder (0.4.2)** — see entries below — which were committed after `v0.4.0-beta` but not yet released.

## 0.4.2 (20 Aug 2026)

- **Type-to-Select Window Fuzzy Finder**: Simply start typing any app or window name while in Mission Control to immediately search, rank, and highlight visible windows:
  - **Stateless Selection Engine (`WindowSelectionEngine`)**: Ranks matches with prefix hits taking priority over substring hits, sorted alphabetically and by window ID.
  - **Top-Left Shoulder Targeting**: Targets the thumbnail's top-left shoulder (inset 20 pt right & down) rather than the center, ensuring windows grouped/stacked by application remain reachable without being blocked by the close/minimize button bar.
  - **Native Highlight Synchronization**: Injects synthetic `.mouseMoved` events so macOS Mission Control paints its native blue highlight on the matched window while keeping `hoveredWindow` in sync for subsequent `Cmd` shortcuts (`Cmd+W`, `Cmd+Q`, `Cmd+M`).
  - **Activation with 50 ms Dwell Click (`WindowActivationAction`)**: Pressing `Enter` / `Return` injects a timed `mouseMoved` → `leftMouseDown` → 50 ms dwell → `leftMouseUp` sequence at `.cghidEventTap` to reliably activate and raise the window while dismissing Mission Control.
  - **Dedicated HID Key Tap (`MCKeyboardTapService`)**: Installs a `.cghidEventTap` `keyDown` tap active strictly during Mission Control to capture keystrokes before the WindowServer swallows them.
  - **Dock-Style Query Pill (`SearchBarOverlay`)**: Renders an uppercase, bold (22 pt heavy) query bar using continuous squircle corners (`layer.cornerCurve = .continuous`) and macOS HUD material, floating cleanly above the Dock.
  - **Navigation Controls**: `Tab` and `Down Arrow` cycle forward; `Up Arrow` cycles backward; `Backspace` deletes characters; `Escape` (or 2-second idle timeout) resets the query.
- **Community Acknowledgement**: Special thanks to [OpenMissionControl](https://github.com/nohackjustnoobb/OpenMissionControl) and [PR #3 (changes)](https://github.com/nohackjustnoobb/OpenMissionControl/pull/3/changes) for inspiring and unlocking key techniques in macOS Exposé window handling and low-level SPI usage.

## 0.4.1 (20 Aug 2026)

- **Mounted Volume Auto-Eject Enhancement**: When pressing `Cmd+W` or `Cmd+Q` (or using pinch-in/swipe-left gestures) on a Finder window showing an ejectable volume (e.g. DMG installers) in Mission Control, MCSC automatically closes the window and unmounts/ejects the volume.
- **Eject Feedback Overlay**: Flashes `eject.circle.fill` with Red 100% primary tint (`[.white, .systemRed]` palette) and the same hover-style scale + alpha animation (1.08× scale over 0.15s ease-out) at the cursor position.
- **Menu Bar Toggle**: Added "Auto-Eject Mounted Volumes" toggle to status bar menu.

## 0.4.0-beta (18 Aug 2026)

- **Cmd+W Multi-Window Targeting Fix**: `CloseTabAction`/`CloseTabAppAction` now close the hovered window's active tab reliably in Mission Control. `findActiveTabCloseButton` recursively descends the AX tree (bounded depth, skipping `AXWebArea`) to locate the `AXTabGroup`/`AXRadioButton` close button — fixing browsers whose tab strip is nested under an `AXGroup` (e.g. Chrome) rather than a direct window child, which previously forced the unreliable ⌘W fallback. When no accessible tab button exists, the ⌘W fallback now focuses the hovered window first via `kAXFocusedAttribute` (best-effort). Browsers with non-standard tab UIs (Zen, Dia) or limited AX exposure (Safari) still fall back to the ⌘W path.
- **Tab Swipe Feedback**: two-finger swipe-left (Close Tab) flashes `xmark.rectangle.fill`, swipe-right (Reopen Tab) `plus.rectangle.fill`, Cmd+swipe-left (Close All Tabs) `rectangle.badge.xmark`, and Cmd+swipe-right (New Window) `rectangle.badge.plus` at the cursor — all animated with `.wiggle.byLayer` on macOS 26+ (`.bounce` fallback before). This closes the last cursor-feedback gaps: every shortcut and gesture now flashes.
- **Maximize Feedback**: swipe-down (Make Larger) now flashes an accent-coloured `rectangle.fill` at the cursor, animated with a `.replace.downUp.byLayer` content transition.
- **Hover Button Modifier Actions**: the Mission Control hover button now supports three actions. No modifier shows the Close button; holding **Option** switches it to Minimize (`minus.circle.fill`); holding **Cmd** switches it to Force Quit (the black→purple `xmark.circle.fill`). Clicking performs the shown action. Cmd takes precedence when both modifiers are held.
- **Resize Feedback**: two-finger double-tap (Reasonable Size), Cmd+two-finger double-tap (Almost Maximize), and swipe-down (Maximize) now flash accent-tinted symbols at the cursor — `inset.filled.center.rectangle` for Reasonable, `inset.filled.rectangle` for Almost, and `rectangle.fill` for Maximize — all sharing the same accent colour and `.replace.downUp.byLayer` content transition.
- **Extensible Replace Transitions**: `CursorFeedbackOverlay.Mode` gained a second animation descriptor — `replaceTransition` — so a feedback type can choose a `setSymbolImage` content transition (symbol morphs from the previous symbol) instead of an in-place `addSymbolEffect`. New replacement styles are one `case` plus one line in `show()`.
- **Hide Feedback**: `Cmd+H` and Cmd+swipe-up (hide) now flash a distinct `smallcircle.filled.circle.fill` at the cursor, tinted with a Primary / Accent / None palette (black / system blue / clear) and a `.bounce` entry animation.
- **Extensible Feedback Modes**: `CursorFeedbackOverlay.Mode` is now data-driven — each mode declares its SF Symbol name, accessibility label, tint palette, and optional entry symbol effect. Adding a new feedback type is a single `case` plus four descriptor lines; the image factory, caching, and animation plumbing are shared.
- **Force-Quit Feedback**: `Cmd+Q` and Cmd+pinch-in (force quit) now flash a distinct `xmark.circle.fill` at the cursor, rendered with a Black → Purple gradient variable palette and a hover-style scale-up + fade-in (1.08×, 0.15 s ease-out) entry animation matching the close button's hover, so quit actions read differently from close (red X) and minimize (black/yellow minus) through their palette.

## 0.3.2 (17 Aug 2026)

- **Cursor-Anchored Action Feedback**: Reused the same `xmark.circle.fill` (Close) and `minus.circle.fill` (Minimize) symbols from the Mission Control hover overlay as a transient, non-interactive visual feedback flash anchored at the mouse cursor whenever a close or minimize action executes:
  - `Cmd+W` (close) → red X flash at the cursor.
  - `Cmd+M` (minimize) → yellow minus flash at the cursor.
  - Pinch-in (close) and swipe-up (minimize) gestures → matching feedback at the cursor.
  - Auto-fades after ~0.6 s; repeated triggers reset the timer. Click-through (`ignoresMouseEvents`), lazily allocated, and cleaned up on `stop()`.
  - Close and force-quit feedback share a hover-style scale-up + fade-in (1.08×, 0.15 s ease-out) entry animation matching `CloseButtonView.setHovered`.
- **Feedback Timing Fix**: Feedback now emits *before* the (blocking, synchronous) Accessibility action instead of after it, so the symbol and haptic land at the same moment the close/minimize shortcut or gesture fires — rather than once the window has already closed or minimized (which read as janky, out-of-sync feedback).
  - The overlay sets its opacity synchronously (plus a `CATransaction.flush()`) and actions are deferred one run-loop turn, ensuring the symbol is composited on screen *before* the blocking AX action starves the main run loop — otherwise it would only render as the action completes and immediately fade (a flicker).
- **Animated Retract**: the symbol exits with a `.disappear.byLayer` symbol effect (each symbol layer vanishes sequentially) and a concurrent panel fade instead of a plain fade. Available on macOS 14+. The retract leads the display window by ~0.12 s so the exit overlaps, rather than waiting for, the end of the flash.

## 0.3.1 (17 Aug 2026)

- **Mission Control Hover Buttons**: Added preview close (`xmark.circle.fill`) and minimize (`minus.circle.fill`) action overlay button anchored directly to the top-left vertex of window thumbnails in Mission Control.
  - Supports Cmd-hold toggle to switch between Close and Minimize modes with smooth symbol content replacement animations.
  - Integrated an `.appear.byLayer` entry symbol animation.
- **Bug Fix**: Fixed application crash when clicking the close or minimize overlay button caused by recursive `dispatch_sync` execution on the main queue within the event tap callback.
- **Reliability & Fallbacks**: Added type-safe AX attribute resolution, fallback application activation + action triggering for non-standard windows, and window list caching cleanups.

## Archived (pre-0.3.1)

Older incremental changes from early July–mid August 2026 (haptics, gesture target validation, Dock AX fixes, MVVM reorg, etc.) are archived in git history. See `git log --oneline --before="2026-08-17"` for details.
