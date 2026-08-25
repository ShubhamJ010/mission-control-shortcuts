import Cocoa

/// Scope of a close operation in the unified close flow.
///
/// - `activeTab`: the selected tab of one window (⌘W / gesture closeTab).
/// - `window`: one whole window via its red traffic-light button.
/// - `wholeApp`: every window of an app (Dock-triggered close).
enum CloseScope {
    case activeTab
    case window
    case wholeApp
}

/// Unified close family: one target-resolution + mechanism ladder for tab,
/// window, and app closes. Replaces the former CloseTabAction /
/// CloseTabAppAction / CloseWindowAction / CloseAppAction
/// quartet whose cursor-vs-Dock branching was duplicated
/// across routers.
///
/// Targeting rule: a non-nil `app` means the trigger was a Dock icon, so the
/// app's key window (or full window list) is acted on; otherwise the hovered
/// window under `point` is resolved through accessibility.
struct WindowCloser {
    /// Virtual key code for "W" — used by ⌘W fallback keystroke.
    private static let keyW: CGKeyCode = 0x0D

    func perform(
        _ scope: CloseScope,
        at point: CGPoint,
        fromApp app: NSRunningApplication?,
        service: AccessibilityServiceProtocol,
        quitIfNoWindows: Bool = false
    ) {
        switch scope {
        case .activeTab:
            closeActiveTab(at: point, fromApp: app, service: service, quitIfNoWindows: quitIfNoWindows)
        case .window:
            closeWindow(at: point, fromApp: app, service: service, quitIfNoWindows: quitIfNoWindows)
        case .wholeApp:
            closeAllWindows(of: app, service: service, quitIfNoWindows: quitIfNoWindows)
        }
    }

    // MARK: - Scopes

    private func closeActiveTab(
        at point: CGPoint,
        fromApp app: NSRunningApplication?,
        service: AccessibilityServiceProtocol,
        quitIfNoWindows: Bool
    ) {
        if let app {
            if quitIfNoWindows, fallbackQuitIfNoWindows(for: app, service: service) {
                return
            }

            let appElement = AXUIElementCreateApplication(app.processIdentifier)

            // Act on the app's key window (the one being targeted from the Dock).
            if let keyWindow: AXUIElement = service.getAttributeValue(kAXFocusedWindowAttribute, for: appElement),
               let closeButton = service.findActiveTabCloseButton(in: keyWindow) {
                _ = service.performAction(kAXPressAction, on: closeButton)
                return
            }

            KeyboardEventPoster.postShortcut(virtualKey: Self.keyW, flags: .maskCommand, to: app.processIdentifier)
        } else {
            guard let element = service.getElement(at: point),
                  let window = service.getWindow(for: element) else { return }

            if let closeButton = service.findActiveTabCloseButton(in: window) {
                _ = service.performAction(kAXPressAction, on: closeButton)
                return
            }

            // Steer the fallback keystroke at the hovered window, not the app's
            // previously focused key window. Best-effort focus.
            _ = service.focusWindow(window)

            var pid: pid_t = 0
            guard AXUIElementGetPid(element, &pid) == .success else { return }
            KeyboardEventPoster.postShortcut(virtualKey: Self.keyW, flags: .maskCommand, to: pid)
        }
    }

    private func closeWindow(
        at point: CGPoint,
        fromApp app: NSRunningApplication?,
        service: AccessibilityServiceProtocol,
        quitIfNoWindows: Bool
    ) {
        if let app {
            if quitIfNoWindows, fallbackQuitIfNoWindows(for: app, service: service) {
                return
            }
        }
        guard let element = service.getElement(at: point),
              let window = service.getWindow(for: element) else { return }
        pressRedCloseButton(of: window, service: service)
    }

    private func closeAllWindows(
        of app: NSRunningApplication?,
        service: AccessibilityServiceProtocol,
        quitIfNoWindows: Bool
    ) {
        guard let app,
              app.processIdentifier != NSRunningApplication.current.processIdentifier else { return }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        guard let windows: [AXUIElement] = service.getAttributeValue(kAXWindowsAttribute, for: appElement),
              !windows.isEmpty else {
            if quitIfNoWindows {
                ForceQuitAppAction().perform(app: app)
            }
            return
        }

        for window in windows {
            pressRedCloseButton(of: window, service: service)
        }
    }

    // MARK: - Mechanisms

    @discardableResult
    private func fallbackQuitIfNoWindows(
        for app: NSRunningApplication,
        service: AccessibilityServiceProtocol
    ) -> Bool {
        guard app.processIdentifier != NSRunningApplication.current.processIdentifier else { return false }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let windows: [AXUIElement]? = service.getAttributeValue(kAXWindowsAttribute, for: appElement)
        if windows == nil || windows?.isEmpty == true {
            ForceQuitAppAction().perform(app: app)
            return true
        }
        return false
    }

    private func pressRedCloseButton(of window: AXUIElement, service: AccessibilityServiceProtocol) {
        if let closeButton: AXUIElement = service.getAttributeValue(kAXCloseButtonAttribute, for: window) {
            _ = service.performAction(kAXPressAction, on: closeButton)
        }
    }
}
