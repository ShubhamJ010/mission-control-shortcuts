import Cocoa

/// Executes window-level operations (close, minimize, force-quit) on windows
/// identified by Mission Control / Exposé window metadata dictionaries.
enum MissionControlWindowActions {
    /// Finds the AX window matching `windowID` and presses its button for
    /// `attribute` (kAXCloseButtonAttribute / kAXMinimizeButtonAttribute / kAXZoomButtonAttribute).
    /// Returns true if the button was successfully pressed.
    private static func pressWindowButton(
        attribute: String,
        on windowInfo: [String: Any],
        accessibilityService: AccessibilityServiceProtocol
    ) -> Bool {
        guard let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
              let window = accessibilityService.getWindow(forWindowID: windowID),
              let button: AXUIElement = accessibilityService.getAttributeValue(attribute, for: window) else {
            return false
        }
        return accessibilityService.performAction(kAXPressAction, on: button)
    }

    static func performClose(on windowInfo: [String: Any], accessibilityService: AccessibilityServiceProtocol) {
        if pressWindowButton(attribute: kAXCloseButtonAttribute, on: windowInfo, accessibilityService: accessibilityService) {
            return
        }

        guard let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t else { return }

        // Finder windows (especially across spaces or desktop backgrounds) can be closed directly by window ID
        if let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
           let owner = windowInfo[kCGWindowOwnerName as String] as? String,
           owner == "Finder" {
            let script = "tell application \"Finder\" to close (every window whose id is \(windowID))"
            if let appleScript = NSAppleScript(source: script) {
                var err: NSDictionary?
                appleScript.executeAndReturnError(&err)
                if err == nil {
                    return
                }
            }
        }

        // Fallback: activate application and post ⌘W directly to target window/process
        if let app = NSRunningApplication(processIdentifier: pid) {
            _ = accessibilityService.activate(app: app, window: nil)
        }

        if let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
           let window = accessibilityService.getWindow(forWindowID: windowID) {
            _ = accessibilityService.focusWindow(window)
        }
        KeyboardEventPoster.postShortcut(virtualKey: 0x0D, flags: .maskCommand, to: pid)
    }

    static func performMinimize(on windowInfo: [String: Any], accessibilityService: AccessibilityServiceProtocol) {
        if pressWindowButton(attribute: kAXMinimizeButtonAttribute, on: windowInfo, accessibilityService: accessibilityService) {
            return
        }

        guard let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t else { return }

        // Finder windows can be collapsed directly by window ID
        if let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
           let owner = windowInfo[kCGWindowOwnerName as String] as? String,
           owner == "Finder" {
            let script = "tell application \"Finder\" to set collapsed of (every window whose id is \(windowID)) to true"
            if let appleScript = NSAppleScript(source: script) {
                var err: NSDictionary?
                appleScript.executeAndReturnError(&err)
                if err == nil {
                    return
                }
            }
        }

        if let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
           let window = accessibilityService.getWindow(forWindowID: windowID) {
            if accessibilityService.setMinimized(true, for: window) {
                return
            }
            _ = accessibilityService.focusWindow(window)
        }

        // Fallback: activate application and post ⌘M
        if let app = NSRunningApplication(processIdentifier: pid) {
            _ = accessibilityService.activate(app: app, window: nil)
        }
        KeyboardEventPoster.postShortcut(virtualKey: 0x2E, flags: .maskCommand, to: pid)
    }

    static func performForceQuit(on windowInfo: [String: Any]) {
        guard let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
              let app = NSRunningApplication(processIdentifier: pid),
              app.isSafeTargetProcess else {
            return
        }
        app.forceTerminate()
    }

    /// Toggles a window's zoom/fullscreen state via its AX zoom button (`kAXZoomButtonAttribute`).
    static func performFullscreen(on windowInfo: [String: Any], accessibilityService: AccessibilityServiceProtocol) {
        if pressWindowButton(attribute: kAXZoomButtonAttribute, on: windowInfo, accessibilityService: accessibilityService) {
            return
        }

        // Fallback: activate the owning app
        guard let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t else { return }

        if let app = NSRunningApplication(processIdentifier: pid) {
            _ = accessibilityService.activate(app: app, window: nil)
        }
    }
}
