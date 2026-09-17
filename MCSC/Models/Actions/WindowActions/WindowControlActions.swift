import Cocoa

struct MinimizeWindowAction: ShortcutAction {
    func perform(at point: CGPoint, service: AccessibilityServiceProtocol) {
        guard let element = service.getElement(at: point),
              let window = service.getWindow(for: element) else { return }

        if let minimizeButton: AXUIElement = service.getAttributeValue(kAXMinimizeButtonAttribute, for: window) {
            _ = service.performAction(kAXPressAction, on: minimizeButton)
        }
    }
}

struct HideApplicationAction: ShortcutAction {
    func perform(at point: CGPoint, service: AccessibilityServiceProtocol) {
        guard let element = service.getElement(at: point),
              service.getWindow(for: element) != nil,
              let app = service.getAppFromElement(element),
              app.isSafeTargetProcess else { return }

        app.hide()
    }
}

struct ForceQuitAction: ShortcutAction {
    func perform(at point: CGPoint, service: AccessibilityServiceProtocol) {
        guard let element = service.getElement(at: point),
              service.getWindow(for: element) != nil,
              let app = service.getAppFromElement(element),
              app.isSafeTargetProcess else { return }

        app.forceTerminate()
    }
}

/// Toggles fullscreen/zoom for the window at `point`.
///
/// Wakens Mission Control's Exposé layer via `coreDockSendNotification` before
/// pressing the AX zoom button (`kAXZoomButtonAttribute`), mirroring
/// `MissionControlWindowActions.performFullscreen` and
/// `PreviewCloseButtonOverlay` Control→fullscreen. Service-layer abstraction
/// keeps `GestureActionRouter` free of raw Dock SPI / CF calls.
struct ToggleFullscreenAction: ShortcutAction {
    func perform(at point: CGPoint, service: AccessibilityServiceProtocol) {
        _ = coreDockSendNotification("com.apple.expose.awake" as CFString, 0)
        guard let element = service.getElement(at: point),
              let window = service.getWindow(for: element),
              let zoomButton: AXUIElement = service.getAttributeValue(kAXZoomButtonAttribute, for: window)
        else { return }
        _ = service.performAction(kAXPressAction, on: zoomButton)
    }
}
