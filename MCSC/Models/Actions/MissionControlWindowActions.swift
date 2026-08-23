import Cocoa

/// Private Dock SPI used to wake/dismiss Mission Control's Exposé overlay
/// before performing a zoom action. Declared via `@_silgen_name` exactly as
/// OpenMissionControl does — without this, pressing `kAXZoomButtonAttribute`
/// while Mission Control is still intercepting window management is a no-op.
@_silgen_name("CoreDockSendNotification")
@discardableResult
func coreDockSendNotification(_ notification: CFString, _ unknown: Int32) -> CGError

/// Executes window-level operations (close, minimize, force-quit) on windows
/// identified by Mission Control / Exposé window metadata dictionaries.
enum MissionControlWindowActions {
    /// Finds the AX window matching `windowID` and presses its button for
    /// `attribute` (kAXCloseButtonAttribute / kAXMinimizeButtonAttribute).
    /// Returns true if the button was successfully pressed.
    static func pressWindowButton(attribute: String, on windowInfo: [String: Any]) -> Bool {
        guard let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
              let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID else {
            return false
        }

        let app = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windowsRef, CFGetTypeID(windowsRef) == CFArrayGetTypeID(),
           let axWindows = windowsRef as? [AXUIElement] {
            for axWindow in axWindows {
                var axId: CGWindowID = 0
                _AXUIElementGetWindow(axWindow, &axId)
                if axId == windowID {
                    var buttonRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(axWindow, attribute as CFString, &buttonRef) == .success,
                       let buttonRef, CFGetTypeID(buttonRef) == AXUIElementGetTypeID() {
                        // TypeID verified above; `as?` cannot check CF types.
                        let actionResult = AXUIElementPerformAction(
                            unsafeDowncast(buttonRef, to: AXUIElement.self),
                            kAXPressAction as CFString
                        )
                        if actionResult == .success {
                            return true
                        }
                    }
                }
            }
        }
        return false
    }

    static func performClose(on windowInfo: [String: Any], accessibilityService: AccessibilityServiceProtocol) {
        if pressWindowButton(attribute: kAXCloseButtonAttribute, on: windowInfo) {
            return
        }

        guard let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t else { return }

        // Fallback: activate application and trigger close action
        if let app = NSRunningApplication(processIdentifier: pid) {
            if #available(macOS 14.0, *) {
                app.activate()
            } else {
                app.activate(options: .activateIgnoringOtherApps)
            }
        }

        if let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat] {
            let centerPoint = CGPoint(
                x: (boundsDict["X"] ?? 0) + (boundsDict["Width"] ?? 0) / 2,
                y: (boundsDict["Y"] ?? 0) + (boundsDict["Height"] ?? 0) / 2
            )
            CloseWindowAction().perform(at: centerPoint, service: accessibilityService)
        }
    }

    static func performMinimize(on windowInfo: [String: Any], accessibilityService: AccessibilityServiceProtocol) {
        if pressWindowButton(attribute: kAXMinimizeButtonAttribute, on: windowInfo) {
            return
        }

        guard let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t else { return }

        // Fallback: activate application and trigger minimize action
        if let app = NSRunningApplication(processIdentifier: pid) {
            if #available(macOS 14.0, *) {
                app.activate()
            } else {
                app.activate(options: .activateIgnoringOtherApps)
            }
        }

        if let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat] {
            let centerPoint = CGPoint(
                x: (boundsDict["X"] ?? 0) + (boundsDict["Width"] ?? 0) / 2,
                y: (boundsDict["Y"] ?? 0) + (boundsDict["Height"] ?? 0) / 2
            )
            MinimizeWindowAction().perform(at: centerPoint, service: accessibilityService)
        }
    }

    static func performForceQuit(on windowInfo: [String: Any]) {
        guard let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
              pid != NSRunningApplication.current.processIdentifier,
              let app = NSRunningApplication(processIdentifier: pid) else {
            return
        }
        app.forceTerminate()
    }

    /// Toggles a window's zoom/fullscreen state. Mirrors OpenMissionControl's
    /// approach: first wakes Mission Control's Exposé layer via the private
    /// `com.apple.expose.awake` Dock notification (otherwise the zoom button
    /// press is swallowed while MC is still intercepting), then presses the
    /// AX zoom button (`kAXZoomButtonAttribute`).
    static func performFullscreen(on windowInfo: [String: Any]) {
        // Wake the Exposé layer so the zoom press reaches the real window.
        _ = coreDockSendNotification("com.apple.expose.awake" as CFString, 0)

        if pressWindowButton(attribute: kAXZoomButtonAttribute, on: windowInfo) {
            return
        }

        // Fallback: activate the owning app and press the zoom button at the
        // window's center via the Accessibility hit-test path.
        guard let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t else { return }

        if let app = NSRunningApplication(processIdentifier: pid) {
            if #available(macOS 14.0, *) {
                app.activate()
            } else {
                app.activate(options: .activateIgnoringOtherApps)
            }
        }
    }
}
