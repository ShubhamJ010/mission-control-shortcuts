import Cocoa

struct ReopenTabAction: ShortcutAction {
    func perform(at point: CGPoint, service: AccessibilityServiceProtocol) {
        guard let element = service.getElement(at: point),
              service.getWindow(for: element) != nil else { return }

        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return }
        KeyboardEventPoster.postShortcut(virtualKey: 0x11, flags: [.maskCommand, .maskShift], to: pid)
    }
}

/// Posts Cmd+N to the application under the point to open a new window.
struct NewWindowAction: ShortcutAction {
    func perform(at point: CGPoint, service: AccessibilityServiceProtocol) {
        // Wake Exposé so the keystroke reaches the app while Mission Control is
        // still intercepting input — same pattern as ToggleFullscreenAction.
        _ = coreDockSendNotification("com.apple.expose.awake" as CFString, 0)
        guard let element = service.getElement(at: point) else { return }

        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return }
        KeyboardEventPoster.postShortcut(virtualKey: 0x2D, flags: .maskCommand, to: pid)
    }
}

/// Posts Cmd+T to the application under the point to open a new tab.
struct NewTabAction: ShortcutAction {
    func perform(at point: CGPoint, service: AccessibilityServiceProtocol) {
        // Wake Exposé so the keystroke reaches the app while Mission Control is
        // still intercepting input — same pattern as ToggleFullscreenAction.
        _ = coreDockSendNotification("com.apple.expose.awake" as CFString, 0)
        guard let element = service.getElement(at: point) else { return }

        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return }
        KeyboardEventPoster.postShortcut(virtualKey: 0x11, flags: .maskCommand, to: pid)
    }
}
