import Cocoa

/// Scope of a close operation in the unified close flow.
///
/// - `activeTab`: the selected tab of one window (⌘W / gesture closeTab).
/// - `window`: one whole window via its red traffic-light button.
/// - `smartClose`: tries active tab first if present; otherwise closes window.
/// - `wholeApp`: every window of an app (Dock-triggered close).
enum CloseScope {
    case activeTab
    case window
    case smartClose
    case wholeApp
}

/// Unified close family: one target-resolution + mechanism ladder for tab,
/// window, and app closes. Replaces the former CloseTabAction /
/// CloseTabAppAction / CloseWindowAction / CloseAppAction
/// quartet whose cursor-vs-Dock branching was duplicated
/// across routers.
///
/// Targeting rule (see `docs/TARGETING_SCOPES.md`):
/// - Dock target (inside or outside MC) represents App Level: window close acts on all windows
///   of the app (`.wholeApp`), while tab close acts on its key window's active tab.
/// - Window preview and Title bar represent Singular Level: actions target only the specific
///   window (`.window`) or its active tab (`.activeTab`).
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
        case .smartClose:
            closeSmart(at: point, fromApp: app, service: service, quitIfNoWindows: quitIfNoWindows)
        case .wholeApp:
            closeAllWindows(of: app, service: service)
        }
    }

    // MARK: - Scopes

    static let tabbedBundleSubstrings = [
        "safari", "chrome", "firefox", "zen", "brave", "edge", "arc",
        "opera", "vivaldi", "terminal", "iterm", "ghostty", "alacritty",
        "warp", "kitty", "xcode", "code", "sublime"
    ]

    static func isTabbedApplication(_ app: NSRunningApplication?) -> Bool {
        guard let bundleId = app?.bundleIdentifier?.lowercased() else { return false }
        return tabbedBundleSubstrings.contains { bundleId.contains($0) }
    }

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

            let appElement = service.appElement(for: app)

            // Act on the app's key window (the one being targeted from the Dock).
            if let keyWindow: AXUIElement = service.getAttributeValue(kAXFocusedWindowAttribute, for: appElement),
               let closeButton = service.findActiveTabCloseButton(in: keyWindow) {
                _ = service.performAction(kAXPressAction, on: closeButton)
                return
            }

            _ = service.activate(app: app, window: nil)
            KeyboardEventPoster.postShortcut(virtualKey: Self.keyW, flags: .maskCommand, to: app.processIdentifier)
        } else {
            guard let element = service.getElement(at: point),
                  let window = service.getWindow(for: element) else { return }

            if let closeButton = service.findActiveTabCloseButton(in: window) {
                _ = service.performAction(kAXPressAction, on: closeButton)
                return
            }

            var pid: pid_t = 0
            guard AXUIElementGetPid(window, &pid) == .success else { return }
            if let targetApp = NSRunningApplication(processIdentifier: pid) {
                _ = service.activate(app: targetApp, window: window)
            } else {
                _ = service.focusWindow(window)
            }
            KeyboardEventPoster.postShortcut(virtualKey: Self.keyW, flags: .maskCommand, to: pid)
        }
    }

    private func closeSmart(
        at point: CGPoint,
        fromApp app: NSRunningApplication?,
        service: AccessibilityServiceProtocol,
        quitIfNoWindows: Bool
    ) {
        if let app {
            if quitIfNoWindows, fallbackQuitIfNoWindows(for: app, service: service) {
                return
            }

            let appElement = service.appElement(for: app)
            if let keyWindow: AXUIElement = service.getAttributeValue(kAXFocusedWindowAttribute, for: appElement),
               let closeButton = service.findActiveTabCloseButton(in: keyWindow) {
                _ = service.performAction(kAXPressAction, on: closeButton)
                return
            }

            if WindowCloser.isTabbedApplication(app) {
                closeActiveTab(at: point, fromApp: app, service: service, quitIfNoWindows: false)
            } else {
                closeWindow(at: point, fromApp: app, service: service, quitIfNoWindows: false)
            }
        } else {
            guard let element = service.getElement(at: point),
                  let window = service.getWindow(for: element) else { return }

            if let closeButton = service.findActiveTabCloseButton(in: window) {
                _ = service.performAction(kAXPressAction, on: closeButton)
                return
            }

            var pid: pid_t = 0
            if AXUIElementGetPid(window, &pid) == .success,
               let targetApp = NSRunningApplication(processIdentifier: pid),
               WindowCloser.isTabbedApplication(targetApp) {
                closeActiveTab(at: point, fromApp: nil, service: service, quitIfNoWindows: false)
                return
            }

            pressRedCloseButton(of: window, service: service)
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
            let appElement = service.appElement(for: app)
            if let keyWindow: AXUIElement = service.getAttributeValue(kAXFocusedWindowAttribute, for: appElement) {
                pressRedCloseButton(of: keyWindow, service: service)
                return
            }
            if let windows: [AXUIElement] = service.getAttributeValue(kAXWindowsAttribute, for: appElement),
               let first = windows.first {
                pressRedCloseButton(of: first, service: service)
                return
            }
            return
        }
        guard let element = service.getElement(at: point),
              let window = service.getWindow(for: element) else { return }
        pressRedCloseButton(of: window, service: service)
    }

    private func closeAllWindows(
        of app: NSRunningApplication?,
        service: AccessibilityServiceProtocol
    ) {
        guard let app,
              app.processIdentifier != NSRunningApplication.current.processIdentifier else { return }
        let appElement = service.appElement(for: app)

        guard let windows: [AXUIElement] = service.getAttributeValue(kAXWindowsAttribute, for: appElement),
              !windows.isEmpty else {
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
        guard app.isSafeTargetProcess else { return false }
        let appElement = service.appElement(for: app)
        let windows: [AXUIElement]? = service.getAttributeValue(kAXWindowsAttribute, for: appElement)
        if windows == nil || windows?.isEmpty == true {
            ForceQuitAppAction().perform(app: app, service: service)
            return true
        }
        return false
    }

    private func pressRedCloseButton(of window: AXUIElement, service: AccessibilityServiceProtocol) {
        if let closeButton: AXUIElement = service.getAttributeValue(kAXCloseButtonAttribute, for: window),
           service.performAction(kAXPressAction, on: closeButton) {
            return
        }

        // Fallback to ⌘W for windows without a standard AX close button (e.g. Electron, custom titlebars)
        var pid: pid_t = 0
        if AXUIElementGetPid(window, &pid) == .success {
            _ = service.focusWindow(window)
            KeyboardEventPoster.postShortcut(virtualKey: Self.keyW, flags: .maskCommand, to: pid)
        }
    }
}
