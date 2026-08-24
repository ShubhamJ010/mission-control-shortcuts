import Cocoa

struct MinimizeAppAction {
    func perform(app: NSRunningApplication, service: AccessibilityServiceProtocol) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var windows: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windows)

        if let windowList = windows as? [AXUIElement] {
            for window in windowList {
                if let minimizeButton: AXUIElement = service
                    .getAttributeValue(kAXMinimizeButtonAttribute, for: window) {
                    _ = service.performAction(kAXPressAction, on: minimizeButton)
                }
            }
        }
    }
}

struct ForceQuitAppAction {
    func perform(app: NSRunningApplication) {
        if app.processIdentifier != NSRunningApplication.current.processIdentifier {
            app.forceTerminate()
        }
    }
}

struct ReopenTabAppAction {
    func perform(app: NSRunningApplication) {
        KeyboardEventPoster.postShortcut(virtualKey: 0x11, flags: [.maskCommand, .maskShift], to: app.processIdentifier)
    }
}

// MARK: - Dock parity: App-level tiling / fullscreen (apply same as window preview)

struct FillScreenAppAction {
    func perform(app: NSRunningApplication, service: AccessibilityServiceProtocol) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard let windows = windowsRef as? [AXUIElement], !windows.isEmpty else { return }
        for window in windows {
            guard let frame = service.getFrame(for: window) else { continue }
            let anchor = CGPoint(x: frame.midX, y: frame.midY)
            guard let screen = ScreenGeometry.screenContaining(axPoint: anchor) else { continue }
            let axBounds = ScreenGeometry.axBounds(for: screen)
            _ = service.setFrame(axBounds, for: window)
        }
    }
}

struct MakeLargerAppAction {
    private let scaleFactor: CGFloat = 1.33

    func perform(app: NSRunningApplication, service: AccessibilityServiceProtocol) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard let windows = windowsRef as? [AXUIElement], !windows.isEmpty else { return }
        for window in windows {
            guard let currentFrame = service.getFrame(for: window) else { continue }
            let anchor = CGPoint(x: currentFrame.midX, y: currentFrame.midY)
            guard let screen = ScreenGeometry.screenContaining(axPoint: anchor) else { continue }
            let axScreenBounds = ScreenGeometry.axBounds(for: screen)

            let targetWidth = (currentFrame.width * scaleFactor).rounded()
            let targetHeight = (currentFrame.height * scaleFactor).rounded()
            let newWidth = min(targetWidth, axScreenBounds.width)
            let newHeight = min(targetHeight, axScreenBounds.height)

            var newX = (currentFrame.origin.x - (newWidth - currentFrame.width) / 2.0).rounded()
            var newY = (currentFrame.origin.y - (newHeight - currentFrame.height) / 2.0).rounded()

            if newX < axScreenBounds.minX {
                newX = axScreenBounds.minX
            } else if newX + newWidth > axScreenBounds.maxX {
                newX = axScreenBounds.maxX - newWidth
            }
            if newY < axScreenBounds.minY {
                newY = axScreenBounds.minY
            } else if newY + newHeight > axScreenBounds.maxY {
                newY = axScreenBounds.maxY - newHeight
            }

            _ = service.setFrame(CGRect(x: newX, y: newY, width: newWidth, height: newHeight), for: window)
        }
    }
}

struct MakeSmallerAppAction {
    private let scaleFactor: CGFloat = 1.0 / 1.33
    private let minWidth: CGFloat = 200
    private let minHeight: CGFloat = 100

    func perform(app: NSRunningApplication, service: AccessibilityServiceProtocol) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard let windows = windowsRef as? [AXUIElement], !windows.isEmpty else { return }
        for window in windows {
            guard let currentFrame = service.getFrame(for: window) else { continue }
            let anchor = CGPoint(x: currentFrame.midX, y: currentFrame.midY)
            guard let screen = ScreenGeometry.screenContaining(axPoint: anchor) else { continue }
            let axScreenBounds = ScreenGeometry.axBounds(for: screen)

            let targetWidth = max((currentFrame.width * scaleFactor).rounded(), minWidth)
            let targetHeight = max((currentFrame.height * scaleFactor).rounded(), minHeight)
            let newWidth = min(targetWidth, axScreenBounds.width)
            let newHeight = min(targetHeight, axScreenBounds.height)

            var newX = (currentFrame.origin.x + (currentFrame.width - newWidth) / 2.0).rounded()
            var newY = (currentFrame.origin.y + (currentFrame.height - newHeight) / 2.0).rounded()

            if newX < axScreenBounds.minX {
                newX = axScreenBounds.minX
            } else if newX + newWidth > axScreenBounds.maxX {
                newX = axScreenBounds.maxX - newWidth
            }
            if newY < axScreenBounds.minY {
                newY = axScreenBounds.minY
            } else if newY + newHeight > axScreenBounds.maxY {
                newY = axScreenBounds.maxY - newHeight
            }

            _ = service.setFrame(CGRect(x: newX, y: newY, width: newWidth, height: newHeight), for: window)
        }
    }
}

struct ReasonableSizeAppAction {
    func perform(app: NSRunningApplication, service: AccessibilityServiceProtocol) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard let windows = windowsRef as? [AXUIElement], !windows.isEmpty else { return }
        for window in windows {
            guard let frame = service.getFrame(for: window) else { continue }
            let anchor = CGPoint(x: frame.midX, y: frame.midY)
            guard let screen = ScreenGeometry.screenContaining(axPoint: anchor) else { continue }
            let axBounds = ScreenGeometry.axBounds(for: screen)
            let w = (axBounds.width * 0.604).rounded()
            let h = (axBounds.height * 0.58).rounded()
            let x = (axBounds.origin.x + (axBounds.width - w) / 2).rounded()
            let y = (axBounds.origin.y + (axBounds.height - h) / 2).rounded()
            _ = service.setFrame(CGRect(x: x, y: y, width: w, height: h), for: window)
        }
    }
}

struct AlmostMaximizeAppAction {
    func perform(app: NSRunningApplication, service: AccessibilityServiceProtocol) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard let windows = windowsRef as? [AXUIElement], !windows.isEmpty else { return }
        for window in windows {
            guard let frame = service.getFrame(for: window) else { continue }
            let anchor = CGPoint(x: frame.midX, y: frame.midY)
            guard let screen = ScreenGeometry.screenContaining(axPoint: anchor) else { continue }
            let axBounds = ScreenGeometry.axBounds(for: screen)
            let w = (axBounds.width * 0.904).rounded()
            let h = (axBounds.height * 0.872).rounded()
            let x = (axBounds.origin.x + (axBounds.width - w) / 2).rounded()
            let y = (axBounds.origin.y + (axBounds.height - h) / 2).rounded()
            _ = service.setFrame(CGRect(x: x, y: y, width: w, height: h), for: window)
        }
    }
}

struct ToggleFullscreenAppAction {
    func perform(app: NSRunningApplication, service: AccessibilityServiceProtocol) {
        _ = coreDockSendNotification("com.apple.expose.awake" as CFString, 0)
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard let windows = windowsRef as? [AXUIElement], !windows.isEmpty else { return }
        for window in windows {
            if let zoomButton: AXUIElement = service.getAttributeValue(kAXZoomButtonAttribute, for: window) {
                _ = service.performAction(kAXPressAction, on: zoomButton)
            }
        }
    }
}
