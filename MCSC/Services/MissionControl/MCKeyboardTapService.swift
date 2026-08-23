import Cocoa

/// HID-level `keyDown` tap active only while Mission Control is open.
///
/// A session-level tap (`.sessionEventTap` / `.cgSessionEventTap`) does not
/// receive alphanumeric `keyDown` events while WindowServer has grabbed the
/// keyboard for Exposé. This service installs a dedicated `.cghidEventTap` at
/// `.headInsertEventTap` exclusively while `MissionControlHoverService` is
/// tracking, so typing can drive `WindowSearchSession` / `WindowSelectionEngine`
/// before WindowServer swallows the event.
///
/// Threading: the tap callback fires on the CFMachPort thread. The service
/// hops to the main thread synchronously for `onKeyDown` because the session
/// and AppKit state are main-actor isolated, then returns the swallow decision
/// synchronously to the tap. If WindowServer disables the tap
/// (`.tapDisabledByTimeout` / `.tapDisabledByUserInput`) it is re-enabled
/// immediately.
///
/// Ownership: `userInfo` holds an unretained pointer to this instance;
/// `stop()` invalidates the `CFMachPort` and `CFRunLoopSource` so the pointer
/// is never dereferenced after teardown. `onKeyDown` returns `true` to swallow
/// the event (`nil` to the tap) and `false` to let it pass through.
protocol MCKeyboardTapServiceProtocol: AnyObject {
    var onKeyDown: ((_ keyCode: Int64, _ characters: String?, _ flags: CGEventFlags) -> Bool)? { get set }
    func start()
    func stop()
}

final class MCKeyboardTapService: MCKeyboardTapServiceProtocol {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var onKeyDown: ((_ keyCode: Int64, _ characters: String?, _ flags: CGEventFlags) -> Bool)?

    func start() {
        guard eventTap == nil else { return }

        let eventMask = (1 << CGEventType.keyDown.rawValue)

        guard let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<MCKeyboardTapService>.fromOpaque(refcon).takeUnretainedValue()

                service.reEnableTapIfDisabled(for: type)

                guard type == .keyDown else {
                    return Unmanaged.passUnretained(event)
                }

                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                let characters = NSEvent(cgEvent: event)?.characters

                // `onKeyDown` touches `WindowSearchSession` and AppKit and must
                // run on main, but the tap must return the swallow decision
                // synchronously. `DispatchQueue.main.sync` is intentional here;
                // if the main thread is stalled long enough to time out, the
                // tap is re-enabled via `reEnableTapIfDisabled`.
                var swallowed = false
                let invoke = {
                    if let callback = service.onKeyDown {
                        swallowed = callback(keyCode, characters, flags)
                    }
                }
                if Thread.isMainThread {
                    invoke()
                } else {
                    DispatchQueue.main.sync(execute: invoke)
                }

                return swallowed ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            AppLogger.eventTap.error("Failed to create Mission Control keyboard tap")
            return
        }

        self.eventTap = eventTap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func reEnableTapIfDisabled(for type: CGEventType) {
        guard type == .tapDisabledByTimeout || type == .tapDisabledByUserInput else { return }
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        AppLogger.eventTap.info("Mission Control keyboard tap was disabled by the system; re-enabled.")
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopSourceInvalidate(runLoopSource)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        eventTap = nil
        runLoopSource = nil
    }

    deinit {
        stop()
    }
}
