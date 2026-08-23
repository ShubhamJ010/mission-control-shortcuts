import Cocoa
import os

/// Alias bridging the legacy `CFEventTimestamp` name to the Quartz timestamp
/// type used by `CGEvent`.
typealias CFEventTimestamp = CGEventTimestamp

/// Low-level wrapper around a Quartz event tap (`CGEvent.tapCreate`) that
/// observes keyboard events and forwards matching shortcuts to its owner.
///
/// - Threading: the tap is attached to the caller's run loop (the main run
///   loop in production), so `onShortcutDetected` fires on the main thread.
/// - Ownership: the tap's `userInfo` holds an *unretained* pointer to this
///   instance because `ShortcutViewModel` owns the service for the whole app
///   lifetime. `stop()` disables the tap and invalidates the run-loop source,
///   so the pointer is never dereferenced after teardown.
/// - Contract: `onShortcutDetected` returns `true` to consume (swallow) the
///   key event and `false` to let it pass through to other apps.
protocol EventTapServiceProtocol: AnyObject {
    typealias ShortcutDetectedCallback = (Int64, CGEventFlags, CGPoint) -> Bool
    var onShortcutDetected: ShortcutDetectedCallback? { get set }
    func start()
    func stop()
}

final class EventTapService: EventTapServiceProtocol {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var onShortcutDetected: ShortcutDetectedCallback?

    /// Installs a `keyDown` event tap on the current run loop and enables it.
    /// If no tap can be created (e.g. missing Accessibility permission), the
    /// call is a no-op and the failure is logged.
    func start() {
        let eventMask = (1 << CGEventType.keyDown.rawValue)

        guard let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<EventTapService>.fromOpaque(refcon).takeUnretainedValue()

                // macOS disables event taps on timeout or user input; re-enable
                // so shortcuts survive without an app restart.
                service.reEnableTapIfDisabled(for: type)

                if type == .keyDown {
                    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                    let flags = event.flags
                    let location = event.location

                    if let callback = service.onShortcutDetected, callback(keyCode, flags, location) {
                        // Return nil to consume the event
                        return nil
                    }
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            AppLogger.eventTap.error("Failed to create event tap")
            return
        }

        self.eventTap = eventTap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    /// Re-enables the event tap when the system disables it (timeout or user
    /// input). Without this, the tap silently dies and shortcuts stop working
    /// until the app is restarted.
    private func reEnableTapIfDisabled(for type: CGEventType) {
        guard type == .tapDisabledByTimeout || type == .tapDisabledByUserInput else { return }
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        AppLogger.eventTap.info("Event tap was disabled by the system; re-enabled.")
    }

    /// Disables the tap, invalidates its run-loop source, and releases the
    /// event tap. Safe to call multiple times and when `start()` never ran.
    func stop() {
        if let runLoopSource {
            CFRunLoopSourceInvalidate(runLoopSource)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        eventTap = nil
        runLoopSource = nil
    }
}
