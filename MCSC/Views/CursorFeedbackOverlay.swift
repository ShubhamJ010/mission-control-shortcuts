import Cocoa

/// A lightweight, non-interactive, transient overlay that flashes the action
/// symbol for a shortcut or gesture — e.g. red `xmark.circle.fill` for Close,
/// `minus.circle.fill` for Minimize, a purple `xmark.circle.fill` for Force
/// Quit, an accent `rectangle.fill` for Maximize — centered at the mouse
/// cursor as visual feedback whenever an action executes.
///
/// The full symbol set, palettes, and per-mode animation styles are declared
/// data-only in `CursorFeedbackMode` (Models layer); the table in
/// `docs/SYMBOLS.md` is the reference. Modes that declare a `baseSymbol`
/// (the resize glyphs, for example) first paint an empty outline and then
/// morph into their filled glyph via a cross-fade transition.
///
/// Unlike `PreviewCloseButtonOverlay` (which is anchored to the top-left of a
/// Mission Control window preview and is clickable), this overlay ignores all
/// mouse events so it never intercepts clicks or changes the cursor while
/// sitting directly under it.
@MainActor
final class CursorFeedbackOverlay {
    /// Resting dimension of the feedback symbol image view.
    static let dimension: CGFloat = 34.0

    /// Total dimension of the backing `NSPanel` (hosted view plus bleed margin).
    static var panelDimension: CGFloat {
        OverlayPanelFactory.panelDimension(forContentDimension: dimension)
    }

    /// Nominal window the symbol stays on screen before retracting. Snappy HUD
    /// window gives immediate visual confirmation without lingering under cursor.
    private let displayDuration: TimeInterval = 0.28

    /// How much the retract leads the end of the display window: the disappear
    /// effect starts `retractLead` seconds before `displayDuration` elapses.
    private let retractLead: TimeInterval = 0.04

    /// Duration of the retract: crisp fade-out and subtle scale-down.
    private let retractDuration: TimeInterval = 0.16

    private var panel: NSPanel?
    private var imageView: NSImageView?
    private var dismissWork: DispatchWorkItem?

    /// Cache of rendered feedback symbols, keyed by mode. Populated lazily so
    /// each symbol is rasterized at most once per process and reused across
    /// triggers.
    private var imageCache: [CursorFeedbackMode: NSImage] = [:]

    /// Returns the cached — or freshly rendered — symbol image for `mode`.
    private func image(for mode: CursorFeedbackMode) -> NSImage? {
        if let cached = imageCache[mode] {
            return cached
        }
        guard let image = makeSymbolImage(for: mode) else { return nil }
        imageCache[mode] = image
        return image
    }

    /// Builds the SF Symbol image for `mode`: semibold 24 pt, tinted with the
    /// mode's palette (or the system multicolor default). Pure factory — no
    /// state — so new modes only need their `CursorFeedbackMode` descriptors.
    private func makeSymbolImage(for mode: CursorFeedbackMode) -> NSImage? {
        makeSymbolImage(symbolName: mode.symbolName, mode: mode)
    }

    /// Renders an arbitrary SF Symbol with the given mode's tint palette. Used
    /// for the base symbols (e.g. empty rectangle) painted just before a
    /// replacement transition fires.
    private func makeSymbolImage(symbolName: String, mode: CursorFeedbackMode) -> NSImage? {
        SymbolImageFactory.make(
            symbolName: symbolName,
            description: mode.accessibilityDescription,
            paletteColors: mode.paletteColors
        )
    }

    private var colorChangeObserver: (any NSObjectProtocol)?
    private var spaceChangeObserver: (any NSObjectProtocol)?
    private var screenChangeObserver: (any NSObjectProtocol)?
    private var wakeObserver: (any NSObjectProtocol)?

    init() {
        // Panel creation is deferred to the first show() call so no
        // NSPanel (and its layer tree) is allocated until feedback is displayed.
        colorChangeObserver = NotificationCenter.default.addObserver(
            forName: NSColor.systemColorsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.imageCache.removeAll()
            }
        }

        // macOS 27: a long-lived all-spaces panel can silently lose its Space
        // membership across Space switches, display reconfigurations and wake,
        // leaving the HUD ordered in but never composited (invisible feedback).
        // Recreating the panel re-admits it on the active Space; the rendered
        // symbol cache survives so the rebuild costs no rasterization.
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard self != nil else { return }
                self?.resetPanel(reason: "space change")
            }
        }
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.resetPanel(reason: "screen parameters changed")
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.resetPanel(reason: "wake")
            }
        }
    }

    deinit {
        if let colorChangeObserver {
            NotificationCenter.default.removeObserver(colorChangeObserver)
        }
        if let spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceChangeObserver)
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }
    }

    /// Drops the backing panel so the next `show()` recreates it on the active
    /// Space. Runs only on space/display/wake transitions, never per gesture.
    private func resetPanel(reason: String) {
        guard panel != nil else { return }
        AppLogger.gesture.debug(
            "CursorFeedbackOverlay: rebuilding panel after \(reason, privacy: .public)"
        )
        dismissWork?.cancel()
        dismissWork = nil
        panel?.orderOut(nil)
        panel = nil
        imageView = nil
    }

    private func setupPanel() {
        let imageRect = NSRect(x: 0, y: 0, width: Self.dimension, height: Self.dimension)
        let imageView = NSImageView(frame: imageRect)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.image = nil

        let container = OverlayBleedContainerView(hostedView: imageView)
        let panel = OverlayPanelFactory.createPanel(
            contentRect: container.frame,
            ignoresMouseEvents: true
        )
        panel.alphaValue = 0.0
        panel.contentView = container

        self.imageView = imageView
        self.panel = panel
    }

    /// Shows the feedback symbol centered on `point` (Quartz/AX screen
    /// coordinates, origin at the top-left). Repeated triggers within the
    /// display window reset the auto-dismiss timer so the symbol persists a
    /// full beat from the most recent action.
    func show(at point: CGPoint, mode: CursorFeedbackMode) {
        if panel == nil {
            setupPanel()
        }
        guard let panel, let imageView else { return }

        // Cancel any pending dismissal so repeated triggers reset the timer.
        dismissWork?.cancel()
        dismissWork = nil

        panel.setFrameOrigin(Self.cocoaAnchorPoint(for: point, panelSize: panel.frame.size))

        guard let feedbackImage = image(for: mode) else { return }

        // Immediately cancel any in-flight animations or transforms from previous retracts
        imageView.layer?.removeAllAnimations()
        imageView.layer?.transform = CATransform3DIdentity

        // Apply symbol entry before making panel visible to eliminate stale frame flicker
        OverlayAnimator.applyEntry(for: mode, imageView: imageView, feedbackImage: feedbackImage)

        panel.orderFrontRegardless()
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        panel.animator().alphaValue = 1.0
        NSAnimationContext.endGrouping()
        panel.alphaValue = 1.0

        scheduleDismiss()
    }

    /// Immediately hides the overlay. Used for cleanup when the app stops.
    func hide() {
        dismissWork?.cancel()
        dismissWork = nil
        panel?.orderOut(nil)
        panel?.alphaValue = 0.0
        imageView?.image = nil
        imageView?.layer?.transform = CATransform3DIdentity
        imageView?.layer?.removeAllAnimations()
    }

    private func scheduleDismiss() {
        let work = DispatchWorkItem { [weak self] in
            guard let self, let panel = self.panel, let imageView = self.imageView else { return }
            self.retract(panel: panel, imageView: imageView)
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + displayDuration - retractLead,
            execute: work
        )
    }

    /// Fades the panel to zero over `retractDuration` and dismisses it.
    private func retract(panel: NSPanel, imageView: NSImageView) {
        OverlayAnimator.performRetract(panel: panel, imageView: imageView, duration: retractDuration) {
            // Dismissal and cleanup finished
        }
    }

    /// Converts a Quartz/AX screen point (origin top-left of the primary
    /// display) into a Cocoa screen origin (bottom-left) that centers a panel
    /// of `panelSize` on the point, clamped so the panel never leaves the
    /// display that contains it.
    static func cocoaAnchorPoint(for point: CGPoint, panelSize: CGSize) -> CGPoint {
        ScreenGeometry.cocoaAnchorPoint(for: point, panelSize: panelSize)
    }
}
