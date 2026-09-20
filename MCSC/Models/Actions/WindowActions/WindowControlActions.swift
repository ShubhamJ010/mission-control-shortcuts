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
              let window = service.getWindow(for: element),
              let app = service.getAppFromElement(window),
              app.isSafeTargetProcess else { return }

        app.hide()
    }
}

struct ForceQuitAction: ShortcutAction {
    func perform(at point: CGPoint, service: AccessibilityServiceProtocol) {
        guard let element = service.getElement(at: point),
              let window = service.getWindow(for: element),
              let app = service.getAppFromElement(window),
              app.isSafeTargetProcess else { return }

        app.forceTerminate()
    }
}

/// Toggles fullscreen/zoom for the window at `point`.
struct ToggleFullscreenAction: ShortcutAction {
    func perform(at point: CGPoint, service: AccessibilityServiceProtocol) {
        guard let element = service.getElement(at: point),
              let window = service.getWindow(for: element),
              let zoomButton: AXUIElement = service.getAttributeValue(kAXZoomButtonAttribute, for: window)
        else { return }
        _ = service.performAction(kAXPressAction, on: zoomButton)
    }
}
