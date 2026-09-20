import Cocoa
import os

/// Protocol for suppressing synthesized mouse and gesture events targeting the Dock.
protocol DockInteractionSuppressorProtocol: AnyObject {
    var isSuppressing: Bool { get set }
    var isDockHoveredProvider: ((CGPoint) -> Bool)? { get set }
    var isEnabledProvider: (() -> Bool)? { get set }
    var onUserClick: (() -> Void)? { get set }
    func start()
    func stop()
}

/// Suppresses synthesized mouse events (clicks, double-clicks, right-clicks)
/// and system gesture events (`smartMagnify` / double-tap smart zoom, `quickLook`, `swipe`)
/// that macOS generates when the cursor is over a Dock icon outside Mission Control.
///
/// This completely prevents App Exposé (from double two-finger tap) and Dock context
/// menus (from two-finger tap / right-click) from triggering.
final class DockInteractionSuppressor: DockInteractionSuppressorProtocol {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// When `true`, mouse clicks (left, right, other mouse down/up) are swallowed over the Dock.
    var isSuppressing: Bool = false

    /// Closure returning `true` if the given Quartz screen point is over the Dock.
    var isDockHoveredProvider: ((CGPoint) -> Bool)?

    /// Closure returning `true` if Dock interaction suppression is currently active
    /// (i.e. `isDockActionsOutsideMCEnabled` is on and Mission Control is not active).
    var isEnabledProvider: (() -> Bool)?

    /// Closure invoked when an un-swallowed user mouse click occurs.
    /// Used by ViewModel to abort hold detection so physical press-clicks don't latch Cmd.
    var onUserClick: (() -> Void)?

    func start() {
        guard eventTap == nil else { return }

        // Intercept all mouse clicks and trackpad gesture events:
        // 1: leftMouseDown, 2: leftMouseUp, 3: rightMouseDown, 4: rightMouseUp
        // 18: rotate, 25: otherMouseDown, 26: otherMouseUp
        // 29: gesture, 30: magnify, 31: swipe, 32: smartMagnify (macOS double-tap zoom -> App Exposé),
        // 33: quickLook, 34: pressure, 37: directTouch
        // Note: scrollWheel (22) is deliberately excluded — it is never suppressed.
        var mask: UInt64 = 0
        mask |= (1 << CGEventType.leftMouseDown.rawValue)
        mask |= (1 << CGEventType.leftMouseUp.rawValue)
        mask |= (1 << CGEventType.rightMouseDown.rawValue)
        mask |= (1 << CGEventType.rightMouseUp.rawValue)
        mask |= (1 << CGEventType.otherMouseDown.rawValue)
        mask |= (1 << CGEventType.otherMouseUp.rawValue)
        mask |= (1 << 18) // rotate
        mask |= (1 << 29) // gesture
        mask |= (1 << 30) // magnify
        mask |= (1 << 31) // swipe
        mask |= (1 << 32) // smartMagnify (macOS double-tap zoom -> triggers App Exposé on Dock)
        mask |= (1 << 33) // quickLook
        mask |= (1 << 34) // pressure
        mask |= (1 << 37) // directTouch

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let suppressor = Unmanaged<DockInteractionSuppressor>.fromOpaque(refcon).takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let eventTap = suppressor.eventTap {
                        CGEvent.tapEnable(tap: eventTap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                if let filtered = suppressor.filterEvent(type: type, event: event) {
                    return Unmanaged.passUnretained(filtered)
                } else {
                    return nil
                }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            AppLogger.eventTap.error("Failed to create DockInteractionSuppressor event tap")
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Undocumented Quartz trackpad gesture event raw types (gesture, magnify, swipe, smartMagnify, quickLook,
    /// pressure).
    private static let gestureEventRawTypes: ClosedRange<UInt32> = 29 ... 34

    /// Tracks whether a physical mouse-down event (pressure > 0.0) was passed through to the system.
    /// Used to guarantee that the corresponding mouse-up event is never swallowed even if pressure
    /// drops to 0.0 upon release during an active double-tap window.
    private var hasActivePhysicalMouseDown: Bool = false

    /// Evaluates whether an intercepted event should be passed through or swallowed.
    /// Internal for direct unit testability without registering a CFMachPort event tap.
    func filterEvent(type: CGEventType, event: CGEvent) -> CGEvent? {
        // Check if suppression is enabled. Defaults to *disabled* when
        // unwired so a partially-configured suppressor can never
        // swallow system-wide input.
        guard isEnabledProvider?() ?? false else {
            return event
        }

        let location = event.location
        let rawType = type.rawValue

        // 1. Always swallow trackpad gesture events (smart zoom/smartMagnify -> App Exposé, magnify, swipe,
        // etc.) when cursor is over the Dock.
        if Self.gestureEventRawTypes.contains(rawType) {
            if isDockHoveredProvider?(location) ?? false {
                return nil // Swallow system gesture (prevents App Exposé)
            }
        }

        // 2. Swallow synthesized clicks (left/right/other click) when actively suppressing
        // during double-tap window or post-gesture cooldown over the Dock.
        // Physical press-clicks (pressure > 0.0) and their matching release (mouseUp) are NEVER swallowed.
        let isMouseDown = type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown
        let isMouseUp = type == .leftMouseUp || type == .rightMouseUp || type == .otherMouseUp

        if isMouseDown {
            let pressure = event.getDoubleValueField(.mouseEventPressure)
            if pressure > 0.0 {
                hasActivePhysicalMouseDown = true
                onUserClick?()
                return event // Pass through physical press click
            }
            hasActivePhysicalMouseDown = false
            if isSuppressing, isDockHoveredProvider?(location) ?? false {
                return nil // Swallow synthesized tap click down
            }
            onUserClick?()
            return event
        }

        if isMouseUp {
            if hasActivePhysicalMouseDown {
                hasActivePhysicalMouseDown = false
                return event // Guarantee physical press click release passes through
            }
            let pressure = event.getDoubleValueField(.mouseEventPressure)
            if pressure > 0.0 {
                return event // Pass through any press-click release reporting positive pressure
            }
            if isSuppressing, isDockHoveredProvider?(location) ?? false {
                return nil // Swallow synthesized tap click up
            }
            return event
        }

        return event
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopSourceInvalidate(source)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        isSuppressing = false
        hasActivePhysicalMouseDown = false
    }

    deinit {
        stop()
    }
}
