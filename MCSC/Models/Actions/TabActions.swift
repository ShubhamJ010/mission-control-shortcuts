import Cocoa

struct ReopenTabAction: ShortcutAction {
    func perform(at point: CGPoint, service: AccessibilityServiceProtocol) {
        guard let element = service.getElement(at: point),
              let window = service.getWindow(for: element) else { return }

        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return }
        if let targetApp = NSRunningApplication(processIdentifier: pid) {
            _ = service.activate(app: targetApp, window: window)
        } else {
            _ = service.focusWindow(window)
        }
        KeyboardEventPoster.postShortcut(virtualKey: 0x11, flags: [.maskCommand, .maskShift], to: pid)
    }
}

/// Posts Cmd+N to the application under the point to open a new window.
struct NewWindowAction: ShortcutAction {
    func perform(at point: CGPoint, service: AccessibilityServiceProtocol) {
        guard let element = service.getElement(at: point) else { return }
        let target = service.getWindow(for: element) ?? element

        var pid: pid_t = 0
        guard AXUIElementGetPid(target, &pid) == .success else { return }
        if let targetApp = NSRunningApplication(processIdentifier: pid) {
            _ = service.activate(app: targetApp, window: target)
        } else {
            _ = service.focusWindow(target)
        }
        KeyboardEventPoster.postShortcut(virtualKey: 0x2D, flags: .maskCommand, to: pid)
    }
}

/// Posts Cmd+T to the application under the point to open a new tab.
struct NewTabAction: ShortcutAction {
    func perform(at point: CGPoint, service: AccessibilityServiceProtocol) {
        guard let element = service.getElement(at: point) else { return }
        let target = service.getWindow(for: element) ?? element

        var pid: pid_t = 0
        guard AXUIElementGetPid(target, &pid) == .success else { return }
        if let targetApp = NSRunningApplication(processIdentifier: pid) {
            _ = service.activate(app: targetApp, window: target)
        } else {
            _ = service.focusWindow(target)
        }
        KeyboardEventPoster.postShortcut(virtualKey: 0x11, flags: .maskCommand, to: pid)
    }
}
