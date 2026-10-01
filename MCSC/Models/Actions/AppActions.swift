import ApplicationServices
import Cocoa

struct MinimizeAppAction {
    func perform(app: NSRunningApplication, service: AccessibilityServiceProtocol) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        guard let windows: [AXUIElement] = service.getAttributeValue(kAXWindowsAttribute, for: appElement),
              !windows.isEmpty else { return }

        for window in windows {
            if let minimizeButton: AXUIElement = service
                .getAttributeValue(kAXMinimizeButtonAttribute, for: window) {
                _ = service.performAction(kAXPressAction, on: minimizeButton)
            }
        }
    }
}

/// Restores (unminimizes) every minimized window of `app`. Minimized windows
/// remain listed under the app's AX windows with `kAXMinimizedAttribute` set,
/// so restoring is an attribute write rather than a button press.
struct UnminimizeAllWindowsAction {
    func perform(app: NSRunningApplication, service: AccessibilityServiceProtocol) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        guard let windows: [AXUIElement] = service.getAttributeValue(kAXWindowsAttribute, for: appElement),
              !windows.isEmpty else { return }

        for window in windows {
            guard let minimized: Bool = service.getAttributeValue(kAXMinimizedAttribute, for: window),
                  minimized else { continue }
            _ = service.setMinimized(false, for: window)
        }
    }
}

extension NSRunningApplication {
    /// Safe to target for destructive or hiding lifecycle operations (force quit, hide, etc.).
    /// Excludes current app self, Dock, WindowManager, and background / non-regular system processes.
    var isSafeTargetProcess: Bool {
        processIdentifier != NSRunningApplication.current.processIdentifier &&
            bundleIdentifier != "com.apple.dock" &&
            bundleIdentifier != "com.apple.WindowManager" &&
            bundleIdentifier != "com.apple.WindowServer" &&
            activationPolicy == .regular
    }
}

struct ForceQuitAppAction {
    func perform(app: NSRunningApplication) {
        if app.isSafeTargetProcess {
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
        guard let windows: [AXUIElement] = service.getAttributeValue(kAXWindowsAttribute, for: appElement),
              !windows.isEmpty else { return }
        for window in windows {
            guard let frame = service.getFrame(for: window) else { continue }
            let anchor = CGPoint(x: frame.midX, y: frame.midY)
            guard let screen = ScreenGeometry.screenContaining(axPoint: anchor) else { continue }
            let axBounds = ScreenGeometry.axVisibleBounds(for: screen)
            _ = service.setFrame(axBounds, for: window)
        }
    }
}

struct MakeLargerAppAction {
    private let scaleFactor: CGFloat = 1.33

    func perform(app: NSRunningApplication, service: AccessibilityServiceProtocol) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let windows: [AXUIElement] = service.getAttributeValue(kAXWindowsAttribute, for: appElement),
              !windows.isEmpty else { return }
        for window in windows {
            guard let currentFrame = service.getFrame(for: window) else { continue }
            let anchor = CGPoint(x: currentFrame.midX, y: currentFrame.midY)
            guard let screen = ScreenGeometry.screenContaining(axPoint: anchor) else { continue }
            let axScreenBounds = ScreenGeometry.axVisibleBounds(for: screen)

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
        guard let windows: [AXUIElement] = service.getAttributeValue(kAXWindowsAttribute, for: appElement),
              !windows.isEmpty else { return }
        for window in windows {
            guard let currentFrame = service.getFrame(for: window) else { continue }
            let anchor = CGPoint(x: currentFrame.midX, y: currentFrame.midY)
            guard let screen = ScreenGeometry.screenContaining(axPoint: anchor) else { continue }
            let axScreenBounds = ScreenGeometry.axVisibleBounds(for: screen)

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
        guard let windows: [AXUIElement] = service.getAttributeValue(kAXWindowsAttribute, for: appElement),
              !windows.isEmpty else { return }
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
        guard let windows: [AXUIElement] = service.getAttributeValue(kAXWindowsAttribute, for: appElement),
              !windows.isEmpty else { return }
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
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let windows: [AXUIElement] = service.getAttributeValue(kAXWindowsAttribute, for: appElement),
              !windows.isEmpty else { return }
        for window in windows {
            if let zoomButton: AXUIElement = service.getAttributeValue(kAXZoomButtonAttribute, for: window) {
                _ = service.performAction(kAXPressAction, on: zoomButton)
            }
        }
    }
}

private func performCycleSnapAppAction(
    _ direction: CycleDirection,
    app: NSRunningApplication,
    service: AccessibilityServiceProtocol
) {
    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    guard let windows: [AXUIElement] = service.getAttributeValue(kAXWindowsAttribute, for: appElement),
          !windows.isEmpty else { return }

    guard let firstFrame = service.getFrame(for: windows[0]) else { return }
    let anchor = CGPoint(x: firstFrame.midX, y: firstFrame.midY)
    guard let screen = ScreenGeometry.screenContaining(axPoint: anchor) else { return }
    let visibleBounds = ScreenGeometry.axVisibleBounds(for: screen)

    var wid: CGWindowID = 0
    _ = _AXUIElementGetWindow(windows[0], &wid)
    let effectiveID = wid != 0 ? wid : CGWindowID(truncatingIfNeeded: CFHash(windows[0]))
    let nextPos = CycleTracker.shared.nextPosition(
        direction: direction,
        windowID: effectiveID,
        currentFrame: firstFrame,
        visibleBounds: visibleBounds
    )

    for window in windows {
        guard let frame = service.getFrame(for: window) else { continue }
        let winAnchor = CGPoint(x: frame.midX, y: frame.midY)
        guard let winScreen = ScreenGeometry.screenContaining(axPoint: winAnchor) else { continue }
        let winVisibleBounds = ScreenGeometry.axVisibleBounds(for: winScreen)
        _ = service.setFrame(nextPos.frame(for: winVisibleBounds), for: window)
    }
}

struct LeftCycleSnapAppAction {
    func perform(app: NSRunningApplication, service: AccessibilityServiceProtocol) {
        performCycleSnapAppAction(.left, app: app, service: service)
    }
}

struct RightCycleSnapAppAction {
    func perform(app: NSRunningApplication, service: AccessibilityServiceProtocol) {
        performCycleSnapAppAction(.right, app: app, service: service)
    }
}
