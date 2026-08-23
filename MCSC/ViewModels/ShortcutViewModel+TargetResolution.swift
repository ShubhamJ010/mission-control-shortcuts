import Cocoa

/// Target resolution, cursor-coordinate conversion, and app activation for
/// `ShortcutViewModel`. Split from the main file to stay under the SwiftLint
/// `file_length` budget; members here use the view model's internal services.
@MainActor
extension ShortcutViewModel {
    /// Current cursor position in top-left-origin AX coordinates (what
    /// `AXUIElementCopyElementAtPosition` expects). Prefers the Quartz event
    /// location; falls back to converting Cocoa's bottom-left `NSEvent`
    /// coordinates when no event source is available.
    func currentAXMouseLocation() -> CGPoint {
        if let loc = CGEvent(source: nil)?.location {
            return loc
        }
        let mouseLocation = NSEvent.mouseLocation
        let primaryHeight = ScreenGeometry.primaryScreenHeight
        return CGPoint(x: mouseLocation.x, y: primaryHeight - mouseLocation.y)
    }

    /// Standard macOS title-bar height (pt) used for the outside-MC hover strip.
    static let titleBarHeight: CGFloat = 28

    /// `true` when the cursor sits on the title-bar strip of the frontmost
    /// window. Only invoked when the feature is enabled and Mission Control is
    /// closed; rides the existing 30 Hz frame throttle.
    func isTitleBarHovered(at point: CGPoint) -> Bool {
        guard case let .window(window) = resolveTarget(at: point) else { return false }
        return isTitleBarHover(window: window, at: point)
    }

    /// Core geometry + frontmost check for an already-resolved window target.
    func isTitleBarHover(window: AXUIElement, at point: CGPoint) -> Bool {
        guard accessibilityService.isFrontmostWindow(window),
              let frame = accessibilityService.getFrame(for: window),
              frame.contains(point) else { return false }
        return point.y - frame.minY <= Self.titleBarHeight
    }

    func resolveTarget(at point: CGPoint) -> TargetResolution {
        guard let element = accessibilityService.getElement(at: point) else { return .none }
        if accessibilityService.isDockItem(element) {
            if let app = accessibilityService.getAppFromDockItem(element) {
                return .dock(app)
            }
            return .none
        }
        if let window = accessibilityService.getWindow(for: element) {
            return .window(window)
        }
        return .none
    }

    // MARK: - App Activation

    @discardableResult
    func activateAppIfNeeded(at point: CGPoint) -> NSRunningApplication? {
        let element = accessibilityService.getElement(at: point)
        let isDock = element.map { accessibilityService.isDockItem($0) } ?? false
        let app = isDock
            ? element.flatMap { accessibilityService.getAppFromDockItem($0) }
            : element.flatMap { accessibilityService.getAppFromElement($0) }
        app?.activate(options: .activateIgnoringOtherApps)
        return app
    }
}
