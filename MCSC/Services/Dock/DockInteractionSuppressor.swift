import Cocoa
import os

/// Protocol for suppressing synthesized mouse and gesture events targeting the Dock.
protocol DockInteractionSuppressorProtocol: AnyObject {
    var isSuppressing: Bool { get set }
    var isDockHoveredProvider: ((CGPoint) -> Bool)? { get set }
    var isEnabledProvider: (() -> Bool)? { get set }
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

                // Check if suppression is enabled. Defaults to *disabled* when
                // unwired so a partially-configured suppressor can never
                // swallow system-wide input.
                guard suppressor.isEnabledProvider?() ?? false else {
                    return Unmanaged.passUnretained(event)
                }

                let location = event.location
                let rawType = type.rawValue

                // 1. Always swallow trackpad gesture events (smart zoom/smartMagnify -> App Exposé, magnify, swipe,
                // etc.)
                // when cursor is over the Dock.
                if rawType == 29 || rawType == 30 || rawType == 31 || rawType == 32 || rawType == 33 || rawType == 34 {
                    if suppressor.isDockHoveredProvider?(location) ?? false {
                        return nil // Swallow system gesture (prevents App Exposé)
                    }
                }

                // 2. Swallow synthesized clicks (left/right/other click) when actively suppressing
                // (e.g. 2+ fingers touching trackpad, during double-tap window, or post-gesture cooldown)
                // over the Dock.
                if suppressor.isSuppressing {
                    // Defaults to *false* when unwired (fail-open) for the
                    // same safety reason as `isEnabledProvider`.
                    if suppressor.isDockHoveredProvider?(location) ?? false {
                        return nil // Swallow synthesized click
                    }
                }

                return Unmanaged.passUnretained(event)
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
    }

    deinit {
        stop()
    }
}
