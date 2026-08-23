import ApplicationServices
import Cocoa

/// Moves a window to the next or previous Desktop (Space).
///
/// Technique validated by the move_next.md POC (`Try3_SystemEvents_anyApp`):
/// hold the title bar with a synthetic `leftMouseDown`, fire Ctrl+←/→ through
/// **System Events** (`osascript`) — the only path that reaches Dock's Space
/// hotkeys while a drag context is held; raw HID `CGEvent` posts are dropped —
/// then release on the new Space. When Mission Control is open it is dismissed
/// first (Escape), mirroring how fullscreen toggling closes MC before the real
/// desktop is interacted with.
///
/// The hold → switch → release sequence takes ~1.7s and runs on a utility
/// queue; nothing is retained, so there is no state to clean up.
struct MoveWindowToDesktopAction: ShortcutAction {
    enum Direction {
        case next
        case previous

        /// Right Arrow = 124, Left Arrow = 123.
        var arrowKeyCode: Int64 {
            switch self {
            case .next: 124
            case .previous: 123
            }
        }
    }

    /// Sequence pacing, kept at the POC's proven values minus its debug-log
    /// padding. All waits run off-main.
    private enum Timing {
        static let missionControlExit = TimeInterval(0.45)
        static let cursorSettle = TimeInterval(0.15)
        static let dragHold = TimeInterval(0.30)
        static let spaceSwitchAnimation = TimeInterval(0.85)
    }

    private let direction: Direction
    /// `true` when Mission Control must be dismissed before the drag starts.
    private let isMissionControlActiveProvider: () -> Bool

    // Side-effect seams. Production defaults post real HID events / spawn one
    // osascript process per invocation; tests substitute recording closures so
    // no event, process, or sleep is ever exercised.
    var postMouseEvent: (CGEventType, CGPoint) -> Void = SystemEffects.postMouse
    var warpCursor: (CGPoint) -> Void = { _ = CGWarpMouseCursorPosition($0) }
    var postEscapeKey: () -> Void = SystemEffects.postEscape
    var sendSpaceSwitchShortcut: (Direction) -> Void = SystemEffects.sendSpaceSwitch
    var waitFor: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }

    init(direction: Direction,
         isMissionControlActiveProvider: @escaping () -> Bool = { false }) {
        self.direction = direction
        self.isMissionControlActiveProvider = isMissionControlActiveProvider
    }

    // MARK: - ShortcutAction

    func perform(at point: CGPoint, service: AccessibilityServiceProtocol) {
        guard let element = service.getElement(at: point),
              let window = service.getWindow(for: element),
              let frame = service.getFrame(for: window) else { return }
        performMove(window: window, frame: frame, service: service)
    }

    /// Dock-target entry point: moves the app's focused window, matching the
    /// dock parity of `ToggleFullscreenAppAction`.
    func perform(app: NSRunningApplication, service: AccessibilityServiceProtocol) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let window: AXUIElement = service.getAttributeValue(kAXFocusedWindowAttribute, for: appElement),
              let frame = service.getFrame(for: window) else { return }
        performMove(window: window, frame: frame, service: service)
    }

    // MARK: - Sequence

    private func performMove(window: AXUIElement, frame: CGRect, service: AccessibilityServiceProtocol) {
        _ = service.focusWindow(window)

        // Title-bar grab point: just left of the red traffic light, centered
        // vertically — nudged further left to ensure clear miss.
        let grabPoint = CGPoint(x: frame.origin.x + 10, y: frame.origin.y + 12)
        let dismissMissionControl = isMissionControlActiveProvider()

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            runSequence(grabPoint: grabPoint, dismissMissionControl: dismissMissionControl)
        }
    }

    /// Synchronous POC sequence. Internal so tests can drive it with injected
    /// recorders without spawning events or sleeping.
    func runSequence(grabPoint: CGPoint, dismissMissionControl: Bool) {
        if dismissMissionControl {
            postEscapeKey()
            waitFor(Timing.missionControlExit)
        }

        // Dual move (event + warp) so WindowServer settles the cursor before press.
        postMouseEvent(.mouseMoved, grabPoint)
        warpCursor(grabPoint)
        waitFor(Timing.cursorSettle)

        postMouseEvent(.leftMouseDown, grabPoint)
        waitFor(Timing.dragHold)

        sendSpaceSwitchShortcut(direction)
        waitFor(Timing.spaceSwitchAnimation)

        // Keep the drag context alive, then release on the new Space (+3/+2).
        let releasePoint = CGPoint(x: grabPoint.x + 3, y: grabPoint.y + 2)
        postMouseEvent(.leftMouseDragged, releasePoint)
        postMouseEvent(.leftMouseUp, releasePoint)
    }
}

/// Production side effects for `MoveWindowToDesktopAction`.
private enum SystemEffects {
    /// `.hidSystemState` + `.cghidEventTap`: WindowServer sees the synthetic
    /// move before Exposé (same path as `WindowActivationAction`).
    static func postMouse(_ type: CGEventType, _ at: CGPoint) {
        CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState),
                mouseType: type,
                mouseCursorPosition: at,
                mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    static func postEscape() {
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
    }

    /// Ctrl+←/→ via System Events. During a held title-bar drag, Dock's Space
    /// hotkeys respond to this automation path only (move_next.md); raw HID
    /// posts are dropped. stdout/stderr go to null devices — no pipe buffers.
    static func sendSpaceSwitch(_ direction: MoveWindowToDesktopAction.Direction) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "tell application \"System Events\" to key code \(direction.arrowKeyCode) using control down"
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
