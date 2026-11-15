# ADR 0003 — Fill/snap bounds ignore the auto-hiding Dock's strip

- Status: Accepted
- Date: 2026-11-15
- Supersedes: none

## Context

Eleven window-sizing call sites (Fill Screen, Almost Maximize, Make Larger/Smaller,
Reasonable Size, cycle-snap, and their app-level counterparts) sized windows to
`ScreenGeometry.axVisibleBounds(for:)`, which wraps `NSScreen.visibleFrame`.
`visibleFrame` excludes the Dock's strip in two cases:

1. **Dock pinned** — the reservation is real; the Dock owns that space.
2. **Dock set to auto-hide** — the strip *should* be free, but on macOS 27 the system
   can hold a **stale reservation** (the desync of ADR 0002), so `visibleFrame` still
   subtracts ~113 pt. A window sized to that rectangle keeps a dead band at the bottom
   and can never reach the bottom edge.

An auto-hiding Dock *overlays* the screen and reserves nothing while hidden, so case 2
is a semantics bug even when the system is healthy: only the menu bar is off limits.

## Decision

1. New `ScreenGeometry.axFillBounds(for:dockAutoHides:)`:
   - `dockAutoHides == true` → screen bounds minus the menu bar only (the Dock's strip
     is ignored).
   - `dockAutoHides == false` → unchanged `axVisibleBounds` (pinned Dock: keep the
     exclusion).
2. All eleven sizing call sites pass `service.isDockAutoHideEnabled`, which reads
   `com.apple.dock autohide` fresh via `CFPreferencesAppSynchronize` +
   `CFPreferencesCopyAppValue` (AccessibilityService).
3. The best-effort AppKit screen-cache refresh (`_prepareScreensIfNeeded`, private
   selector) after Mission Control exit is **kept** as a staleness mitigation for this
   geometry path. AppKit exposes no public cache invalidation, and a non-activating
   accessory app's `NSScreen` data can lag the compositor by seconds. It is
   best-effort by nature; the correctness of `axFillBounds` must not depend on it
   beyond the first seconds after a transaction.

## Alternatives Considered

### Always ignore the Dock's strip
- Pros: one code path.
- Cons: wrong with a pinned Dock — windows would slide under a permanently visible bar.
- Rejected.

### Keep `visibleFrame` everywhere (status quo)
- Pros: no new API.
- Cons: the dead-band bug stays; windows can never fill edge to edge while the stale
  reservation is held.
- Rejected.

### Query the Dock's live reservation per action (Dock AX or CGWindowList)
- Pros: no dependence on `NSScreen` freshness.
- Cons: adds WindowServer/AX IPC to a hot interaction path, for a value that is `0`
  in the normal auto-hide case; the menu bar still has to come from `NSScreen` anyway.
- Rejected; revisit only if post-exit staleness is observed in practice.

## Consequences

- Windows fill edge to edge with an auto-hiding Dock, including while the stale
  reservation is held — the user-visible symptom of ADR 0002's desync disappears for
  MCSC's own actions.
- The `dockAutoHides` flag is read per action, so a mid-session autohide toggle takes
  effect on the next action without restart.
- Verification requirement: Fill Screen immediately after exiting Mission Control must
  reach the bottom edge (this is the window where `visibleFrame` staleness would
  otherwise leak through the menu-bar subtraction).
