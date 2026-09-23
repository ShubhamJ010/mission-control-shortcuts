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

                if let processed = service.handleTapEvent(type: type, event: event) {
                    return Unmanaged.passUnretained(processed)
                }
                return nil
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

    /// Dispatches events received on the input tap. Returns the event to pass through, or nil to swallow.
    private func handleTapEvent(type: CGEventType, event: CGEvent) -> CGEvent? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return event
        }

        if type == .flagsChanged {
            let cmdPressed = event.flags.contains(.maskCommand)
            let optionPressed = event.flags.contains(.maskAlternate)
            let controlPressed = event.flags.contains(.maskControl)
            let notifyFlags = { [weak self] in
                self?.handleFlagsChanged(
                    cmdPressed: cmdPressed,
                    optionPressed: optionPressed,
                    controlPressed: controlPressed
                )
            }
            if Thread.isMainThread {
                notifyFlags()
            } else {
                DispatchQueue.main.async { notifyFlags() }
            }
            return event
        }

        if type == .leftMouseDown {
            let location = event.location
            var intercepted = false
            let testClick = { [weak self] in
                intercepted = self?.handleMouseDown(at: location) ?? false
            }
            if Thread.isMainThread {
                testClick()
            } else {
                DispatchQueue.main.sync { testClick() }
            }

            if intercepted {
                return nil // Swallow the click so Mission Control does not dismiss prematurely
            }

            let dismissActions = { [weak self] in
                self?.hideAllOverlays()
            }
            if Thread.isMainThread {
                dismissActions()
            } else {
                DispatchQueue.main.async { dismissActions() }
            }
            return event
        }

        let location = event.location
        if Thread.isMainThread {
            handleMouseMoved(at: location)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.handleMouseMoved(at: location)
            }
        }
        return event
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
