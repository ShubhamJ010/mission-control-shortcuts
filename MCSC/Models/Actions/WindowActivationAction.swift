import CoreGraphics
import Foundation

/// Posts synthetic mouse events used to highlight and activate a Mission
/// Control window thumbnail. Pure event injection — no service or view
/// dependencies — so it is reusable from `MissionControlHoverService` and
/// testable in isolation. Coordinates are in AX/Quartz space (origin at
/// top-left of the primary display in CGWindowList terms) positioned in the
/// middle of the preview thumbnail.
enum WindowActivationAction {
    /// Warps the hardware cursor to `point` and posts a HID `mouseMoved` (AX/Quartz coordinates)
    /// so Mission Control paints its native blue highlight and scaling animation on the
    /// thumbnail under that point and syncs `hoveredWindow` in the hover service.
    /// Uses `CGEventSource(stateID: .hidSystemState)` and posts at `.cghidEventTap`
    /// so the synthetic move is seen before WindowServer's Exposé grab.
    static func postSyntheticMouseMoved(to point: CGPoint) {
        _ = CGWarpMouseCursorPosition(point)
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        )?.post(tap: .cghidEventTap)
    }

    /// Posts `mouseMoved` → `leftMouseDown` → 50 ms dwell → `leftMouseUp` at
    /// `.cghidEventTap` to reliably activate the Exposé thumbnail under
    /// `point`. A zero-duration synthetic click (down immediately followed by
    /// up on the same run-loop turn) is unreliably registered by Mission
    /// Control; the 50 ms dwell lets WindowServer process the down, paint the
    /// highlight, and arm the activation before the up arrives. `dwell` is the
    /// single source of truth for that delay.
    static let dwell: TimeInterval = 0.05

    /// Injects the full synthetic click sequence at `point`. Reuses
    /// `postSyntheticMouseMoved(to:)` to ensure the highlight is painted
    /// before the down, then posts `leftMouseDown` immediately and schedules
    /// `leftMouseUp` after `dwell` on the main queue with a fresh
    /// `CGEventSource` to avoid retaining a potentially stale CF object.
    static func performSyntheticClick(at point: CGPoint) {
        let downSource = CGEventSource(stateID: .hidSystemState)

        postSyntheticMouseMoved(to: point)

        CGEvent(
            mouseEventSource: downSource,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        )?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + dwell) {
            let upSource = CGEventSource(stateID: .hidSystemState)
            CGEvent(
                mouseEventSource: upSource,
                mouseType: .leftMouseUp,
                mouseCursorPosition: point,
                mouseButton: .left
            )?.post(tap: .cghidEventTap)
        }
    }
}
