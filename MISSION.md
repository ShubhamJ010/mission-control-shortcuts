# Mission: macOS Multitouch, Quartz Event Routing & Dock Gesture Disambiguation

## Why
Enable simultaneous support for custom multitouch trackpad gestures (two-finger double tap for window tiling) and native system interactions (two-finger physical press-click for Dock context menus) without accidental event collisions or dropped input.

## Success looks like
- Understand the complete macOS event pipeline across MultitouchSupport (driver), IOKit, Quartz Event Taps (CGEvent), and AppKit.
- Explain the physical and programmatic difference between a capacitive "tap-to-click" and a Force Touch / mechanical "press-click".
- Diagnose why MCSC's existing Dock interaction suppression gate indiscriminately killed two-finger physical clicks.
- Design and ship an architectural refactor in MCSC that isolates gesture suppression to synthesized zero-pressure taps during double-tap windows while keeping physical press-clicks 100% responsive.

## Constraints
- MCSC baseline memory must remain under 13 MB (zero-footprint utility rule).
- Pure AppKit / Core Graphics / Core Foundation — no SwiftUI runtime overhead.
- No high-frequency polling; maintain strict 30 Hz / event-driven architecture.
- Full test suite passing with regression coverage.

## Out of scope
- Third-party mouse driver reverse engineering (Logitech Options, etc.).
- Changing macOS system-wide trackpad preferences programmatically.
