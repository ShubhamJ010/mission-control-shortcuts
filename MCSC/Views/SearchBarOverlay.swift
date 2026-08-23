import Cocoa

/// Dock-style floating pill that displays the Mission Control type-to-select
/// query. Non-interactive (ignores mouse) and positioned just above the Dock
/// with HUD material and continuous squircle corners. Shows the uppercase
/// query, dynamically sizing to the text length while staying within
/// `screen.frame` minus `horizontalMargin`. Installed lazily by
/// `MissionControlHoverService` only while a type-to-select session is active.
@MainActor
final class SearchBarOverlay {
    nonisolated static let barHeight: CGFloat = 52
    nonisolated static let minWidth: CGFloat = 120
    nonisolated static let horizontalMargin: CGFloat = 200
    nonisolated static let dockGap: CGFloat = 24
    nonisolated static let defaultDockTopOffset: CGFloat = 155
    nonisolated static let horizontalPadding: CGFloat = 36
    nonisolated static let fontSize: CGFloat = 22
    nonisolated static let cornerRadius: CGFloat = 16

    private var panel: NSPanel?
    private var textField: NSTextField?

    private(set) var isVisible = false

    init() {
        // Panel creation is deferred to the first show(query:) call so no
        // NSPanel is created until a search query is typed.
    }

    /// Cocoa frame for the query pill on `screen`. Extracted so tests can
    /// verify placement without ordering a panel on screen.
    ///
    /// Dock-aware: `visibleFrame` already excludes the Dock and menu bar. For
    /// a bottom Dock `visibleFrame.minY` is above `frame.minY`; for a
    /// side/hidden Dock they are equal. Using `visibleFrame.minY + dockGap`
    /// handles all configurations and corrects a multi-screen offset bug where
    /// `frame.minY` was added twice for secondary displays. `dockGap` (24 pt)
    /// lifts the pill above the Dock, with `defaultDockTopOffset` (155 pt) as
    /// a fallback when the Dock is hidden or the visible frame equals the
    /// full frame. Width is measured from the uppercase query string in
    /// `fontSize` heavy weight, padded by `horizontalPadding`, clamped between
    /// `minWidth` and `screen.frame.width - horizontalMargin` and centered via
    /// `midX`.
    static func panelFrame(
        query: String,
        screen: NSScreen,
        barHeight: CGFloat = barHeight
    ) -> NSRect {
        let display = query.uppercased()
        let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
        let textWidth = (display as NSString).size(withAttributes: [.font: font]).width
        let maxWidth = max(minWidth, screen.frame.width - horizontalMargin)
        let width = min(max(textWidth + horizontalPadding * 2, minWidth), maxWidth)
        let x = screen.frame.midX - width / 2.0
        let dockTop = screen.visibleFrame.minY + dockGap
        let fallbackTop = screen.frame.minY + defaultDockTopOffset
        let y = max(dockTop, fallbackTop)
        return NSRect(x: x, y: y, width: width, height: barHeight)
    }

    func show(query: String) {
        if panel == nil {
            setupPanel()
        }
        guard let panel else { return }
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        textField?.stringValue = query.uppercased()
        panel.setFrame(Self.panelFrame(query: query, screen: screen), display: true)

        if !isVisible {
            panel.orderFrontRegardless()
            isVisible = true
        }
    }

    func hide() {
        guard isVisible else { return }
        panel?.orderOut(nil)
        isVisible = false
        textField?.stringValue = ""
    }

    private func setupPanel() {
        let contentRect = NSRect(x: 0, y: 0, width: Self.minWidth, height: Self.barHeight)
        let panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.screenSaverWindow)))
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        let effectView = NSVisualEffectView(frame: contentRect)
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = Self.cornerRadius
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderWidth = 0.5
        effectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        effectView.autoresizingMask = [.width, .height]

        let field = NSTextField(labelWithString: "")
        field.font = NSFont.systemFont(ofSize: Self.fontSize, weight: .heavy)
        field.textColor = .labelColor
        field.alignment = .center
        field.drawsBackground = false
        field.isBezeled = false
        field.isEditable = false
        field.isSelectable = false
        field.focusRingType = .none
        field.translatesAutoresizingMaskIntoConstraints = false

        effectView.addSubview(field)
        NSLayoutConstraint.activate([
            field.centerXAnchor.constraint(equalTo: effectView.centerXAnchor),
            field.centerYAnchor.constraint(equalTo: effectView.centerYAnchor),
            field.leadingAnchor.constraint(greaterThanOrEqualTo: effectView.leadingAnchor, constant: 16),
            field.trailingAnchor.constraint(lessThanOrEqualTo: effectView.trailingAnchor, constant: -16),
        ])

        panel.contentView = effectView
        self.textField = field
        self.panel = panel
    }
}
