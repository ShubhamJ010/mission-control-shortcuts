import ApplicationServices
import Cocoa

/// Global `mouseMoved` / `leftMouseDown` / `flagsChanged` event tap for
/// `MissionControlHoverService`. Installed only while the hover-close feature
/// is enabled; the callback drives overlay show/hide and action execution.
/// Split from the main file to stay under the SwiftLint `file_length` budget.
@MainActor
extension MissionControlHoverService {
    func startInputTap() {
        guard eventTap == nil else { return }

        let mask = (1 << CGEventType.mouseMoved.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<MissionControlHoverService>.fromOpaque(refcon).takeUnretainedValue()

                // macOS disables event taps on timeout or user input; re-enable
                // so hover tracking survives without an app restart.
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = service.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                if type == .flagsChanged {
                    let cmdPressed = event.flags.contains(.maskCommand)
                    let optionPressed = event.flags.contains(.maskAlternate)
                    let controlPressed = event.flags.contains(.maskControl)
                    if Thread.isMainThread {
                        service.handleFlagsChanged(
                            cmdPressed: cmdPressed,
                            optionPressed: optionPressed,
                            controlPressed: controlPressed
                        )
                    } else {
                        DispatchQueue.main.async {
                            service.handleFlagsChanged(
                                cmdPressed: cmdPressed,
                                optionPressed: optionPressed,
                                controlPressed: controlPressed
                            )
                        }
                    }
                    return Unmanaged.passUnretained(event)
                }

                if type == .leftMouseDown {
                    let location = event.location
                    var intercepted = false

                    // Safely check if click hit the overlay button without blocking main thread
                    if Thread.isMainThread {
                        intercepted = service.handleMouseDown(at: location)
                    } else {
                        DispatchQueue.main.sync {
                            intercepted = service.handleMouseDown(at: location)
                        }
                    }

                    if intercepted {
                        return nil // Swallow the click so Mission Control does not dismiss prematurely
                    }
                    return Unmanaged.passUnretained(event)
                }

                let location = event.location
                if Thread.isMainThread {
                    service.handleMouseMoved(at: location)
                } else {
                    DispatchQueue.main.async {
                        service.handleMouseMoved(at: location)
                    }
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stopInputTap() {
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
    }
}
