import Cocoa

/// Reference to Accessibility settings (Reduce Motion).
private enum SystemAccessibility {
    static var allowsMotion: Bool {
        !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

/// Settings window styled after the macOS System Settings window.
///
/// Only a close button by default, the active pane name becomes the window
/// title (also on the Window menu), and the frame autosaves through
/// UserDefaults. Reimplemented from usagimaru/MacAppSettingsUI.
final class SettingsWindow: NSWindow {
    /// The standard window title, used when no pane is selected.
    var defaultWindowTitle = "Settings"

    /// True while the window is being resized programmatically during a pane
    /// transition (as opposed to a user drag).
    private(set) var isWindowResizing = false

    init(contentViewController: NSTabViewController) {
        super.init(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        self.contentViewController = contentViewController
        titlebarSeparatorStyle = .automatic
        toolbarStyle = .preference
    }

    /// Enable the traditional zoom button instead of the full screen button.
    func setZoomButton() {
        collectionBehavior = .fullScreenAuxiliary
    }

    /// Set window title in the title bar, Window menu and Dock tile title.
    func setWindowTitle(with tabViewItem: NSTabViewItem?) {
        title = tabViewItem?.label ?? defaultWindowTitle

        let windowTitle: String = if let tabTitle = tabViewItem?.label {
            "\(defaultWindowTitle) — \(tabTitle)"
        } else {
            defaultWindowTitle
        }

        if isVisible {
            NSApp.changeWindowsItem(self, title: windowTitle, filename: false)
        } else {
            NSApp.removeWindowsItem(self)
        }
        miniwindowTitle = windowTitle
    }

    /// Set fitting size to window, keeping the top edge in place.
    func setWindowSize(_ size: NSSize, animateIfPossible: Bool, completion: (() -> Void)? = nil) {
        let contentFrame = frameRect(forContentRect: NSRect(origin: .zero, size: size))
        let heightDiff = frame.height - contentFrame.height
        let newFrame = NSRect(x: frame.origin.x,
                              y: frame.origin.y + heightDiff,
                              width: contentFrame.width,
                              height: contentFrame.height)

        func postprocess() {
            isWindowResizing = false
            completion?()
        }

        if animateIfPossible, SystemAccessibility.allowsMotion {
            isWindowResizing = true
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.allowsImplicitAnimation = true
                ctx.duration = animationResizeTime(newFrame)
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                setFrame(newFrame, display: true)
            } completionHandler: {
                postprocess()
            }
        } else {
            isWindowResizing = true
            setFrame(newFrame, display: true)
            postprocess()
        }
    }

    /// Animation duration derived from the frame size difference (0.2s – 0.7s).
    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval {
        let minDuration: TimeInterval = 0.2
        let maxDuration: TimeInterval = 0.7

        let maxDiff = max(abs(newFrame.width - frame.width), abs(newFrame.height - frame.height))
        let referenceLength = NSScreen.main?.frame.height ?? 800
        let ratio = min(maxDiff / referenceLength, 1.0)

        return minDuration + (maxDuration - minDuration) * ratio
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let disabled: [Selector] = [
            #selector(toggleFullScreen(_:)),
            #selector(selectPreviousTab(_:)),
            #selector(moveTabToNewWindow(_:)),
            #selector(mergeAllWindows(_:)),
            #selector(toggleTabBar(_:)),
            #selector(toggleTabOverview(_:)),
            #selector(toggleToolbarShown(_:)),
            #selector(runToolbarCustomizationPalette(_:)),
        ]
        guard let action = menuItem.action else { return super.validateMenuItem(menuItem) }
        if disabled.contains(action) {
            return false
        }
        return super.validateMenuItem(menuItem)
    }
}

/// Window controller for `SettingsWindow`.
///
/// Restores the last window frame via an autosave name, centers on first
/// launch, closes on Escape / Cmd-Period (`cancel(_:)`), and owns the
/// `SettingsTabViewController` that manages the panes.
final class SettingsWindowController: NSWindowController {
    private enum Keys {
        static let lastWindowFrame = "MCSC.SettingsWindow.lastFrame"
    }

    /// Always center instead of restoring the saved frame.
    var centersWindowPositionAlways = false
    /// Close the window with Escape / Cmd-Period.
    var closesWindowWithEscapeKey = true

    private(set) var tabViewController: SettingsTabViewController!

    override var shouldCascadeWindows: Bool {
        get { false }
        set { super.shouldCascadeWindows = false }
    }

    private var settingsWindow: SettingsWindow? {
        window as? SettingsWindow
    }

    /// Builds the settings window from the given panes.
    init(panes: [SettingsPaneViewController],
         centersWindowPositionAlways: Bool = false,
         closesWindowWithEscapeKey: Bool = true) {
        let tabVC = SettingsTabViewController()
        let win = SettingsWindow(contentViewController: tabVC)
        super.init(window: win)

        self.centersWindowPositionAlways = centersWindowPositionAlways
        self.closesWindowWithEscapeKey = closesWindowWithEscapeKey

        tabViewController = tabVC
        initialWindowSetup()
        tabViewController.set(panes: panes)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    /// Callback invoked when the window is closing to allow releasing controller and views.
    var onWindowWillClose: (() -> Void)?

    private func initialWindowSetup() {
        shouldCascadeWindows = false
        windowFrameAutosaveName = Keys.lastWindowFrame
        window?.styleMask = [.titled, .closable]
        window?.delegate = self
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)

        // Restore the saved frame; fall back to centered on first launch.
        if centersWindowPositionAlways || window?.setFrameUsingName(windowFrameAutosaveName) == false {
            window?.center()
        }
        settingsWindow?.setZoomButton()

        // Update the window menu item title for the active pane.
        if window?.isVisible == true {
            tabViewController.updateWindowTitleWithSelectedTab()
        }
    }

    /// Closes the window via Escape key or Cmd-Period.
    @objc func cancel(_: Any?) {
        if closesWindowWithEscapeKey {
            close()
        }
    }

    func removeAutosavedWindowFrame() {
        NSWindow.removeFrame(usingName: Keys.lastWindowFrame)
    }

    // MARK: - MCSC

    /// Builds the settings window with the standard MCSC panes.
    convenience init(viewModel: ShortcutViewModel) {
        self.init(panes: [
            GeneralSettingsPane(viewModel: viewModel,
                                tabName: "General",
                                tabImage: NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil),
                                tabIdentifier: "general"),
            ShortcutSettingsPane(viewModel: viewModel,
                                 tabName: "Shortcuts",
                                 tabImage: NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil),
                                 tabIdentifier: "shortcuts"),
            GestureSettingsPane(viewModel: viewModel,
                                tabName: "Gestures",
                                tabImage: NSImage(systemSymbolName: "hand.draw", accessibilityDescription: nil),
                                tabIdentifier: "gestures"),
        ])
        window?.title = "MCSC Settings"
        settingsWindow?.defaultWindowTitle = "MCSC Settings"
    }

    /// Re-syncs pane controls from the view model, then shows the window.
    func show() {
        tabViewController?.panes.forEach { ($0 as? MCSCSettingsPane)?.refresh() }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_: Notification) {
        onWindowWillClose?()
    }
}
