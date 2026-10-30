# ADR 0001 — Ignore floating component windows (PiP) as targets

- Status: Accepted
- Date: 2026-10-31
- Supersedes: none

## Context

MCSC resolves a gesture/shortcut target with an AX hit test and then treats the
resolved `AXWindow` as a document window. The "title bar" is a geometry guess:

```swift
frame.contains(point) && point.y - frame.minY <= 28
```

Browser picture-in-picture windows and always-on-top media panels are
borderless, so their top 28 pt is video, not a title bar. Gestures on a PiP
window therefore fired close, snap, space-move and app-activation actions on a
video window.

Measured on macOS 27:

| Window | CG layer | AX title | AX subrole | Fullscreen button |
|---|---|---|---|---|
| Zen PiP | 3 | `Picture-in-Picture` | `AXStandardWindow` | absent |
| Dia PiP | 3 | empty | `AXSystemDialog` | absent |
| floatyMPV panel | 3 | (AX ignored) | — | — |
| Zen main | 0 | page title | `AXStandardWindow` | present |
| Dia main | 0 | page title | `AXStandardWindow` | absent |

Title, subrole and traffic-light presence all differ between browsers. The only
portable signal is the CoreGraphics window layer.

## Decision

1. Windows at `kCGWindowLayer >= 3` are classified as **components**.
2. Component windows are never resolved as a target: `resolveTarget` returns
   `.none`, and `isTitleBarHover` returns `false`.
3. Mission Control tracking drops component windows, so no preview target
   exists for them.
4. Detection is on by default (`mcsc.windowComponents.ignoreFloating` absent
   means enabled). No setup required for Zen, Dia, Arc, Safari or floatyMPV.
5. A per-app override (`WindowComponentBehavior.allow`) restores normal
   behavior for apps whose floating panels should stay targetable.
6. Classification is cached: one window-list scan per second, verdicts keyed by
   window id with a 5 s TTL, both purged through the existing
   `.mcscPurgeCaches` path.

## Why layer, not AX metadata

AX metadata is app-specific: Zen exposes virtual close/zoom/minimize buttons on
its PiP window and reports `AXStandardWindow`; Dia reports `AXSystemDialog` with
no title. Matching titles or button presence would need a per-browser table and
break on the next browser update. Layer 3 is a platform invariant: a window that
floats above normal windows is not a document window.

## Consequences

- PiP and floating panels no longer respond to gestures or Command shortcuts.
- Some legitimate floating utilities (quick-reply panels, overlay widgets) are
  ignored by default. They can be re-enabled per app in Settings → Windows.
- floatyMPV opts out of the accessibility tree entirely, so MCSC already cannot
  see it. The classifier still records it from the window list when its layer is
  observed, and the override remains available if AX support is added later.
- Cost: one bounded dictionary cache (~32 entries) and one window-list scan per
  second. Measured footprint stays under the 13 MB ceiling.

## Alternatives considered

- **Title matching** (`"Picture-in-Picture"`): fails for Dia (empty title) and
  is localized.
- **AX button probing**: fails for Zen, which exposes virtual buttons.
- **`AXSubrole`**: both PiP windows report different subroles, one of them
  `AXStandardWindow`.
- **Window size heuristic**: fragile with resizable PiP windows.

## References

- `MCSC/Services/Accessibility/WindowComponentClassifier.swift`
- `MCSC/Models/WindowComponents/WindowComponent.swift`
- `MCSC/ViewModels/ShortcutViewModel+TargetResolution.swift`
- `MCSC/Services/MissionControl/MissionControlHoverService.swift`
- `docs/TARGETING_SCOPES.md`
