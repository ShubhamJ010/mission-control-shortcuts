import Cocoa

/// Common lifecycle protocol for floating Mission Control and HUD overlays.
@MainActor
protocol FloatingOverlayProtocol: AnyObject {
    /// Whether the overlay panel is currently ordered on screen.
    var isVisible: Bool { get }

    /// Hides the overlay panel and resets transient visual state.
    func hide()
}

/// Shared factory for creating non-activating, transparent floating panels
/// used by Mission Control and cursor HUD overlays (DRY architecture).
@MainActor
enum OverlayPanelFactory {
    /// Creates an `NSPanel` configured for floating overlay presentation:
    /// non-activating, borderless, transparent, stationary across all spaces,
    /// and floating above standard WindowServer windows.
    ///
    /// - Parameters:
    ///   - contentRect: Frame rectangle in screen coordinates.
    ///   - level: Window level (defaults to `.screenSaverWindow`).
    ///   - ignoresMouseEvents: Whether the panel intercepts mouse events.
    /// - Returns: A fully configured `NSPanel`.
    static func createPanel(
        contentRect: NSRect,
        level: NSWindow.Level = NSWindow.Level(Int(CGWindowLevelForKey(.screenSaverWindow))),
        ignoresMouseEvents: Bool = false
    ) -> NSPanel {
        let panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = level
        panel.ignoresMouseEvents = ignoresMouseEvents
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        return panel
    }
}
