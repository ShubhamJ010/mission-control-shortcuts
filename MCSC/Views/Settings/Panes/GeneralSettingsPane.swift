import Cocoa

/// General settings pane: launch at login, window and dock behavior,
/// Mission Control, and feedback options.
final class GeneralSettingsPane: MCSCSettingsPane {
    private var launchAtLoginCheckbox: NSButton!
    private var autoEjectCheckbox: NSButton!
    private var quitAppIfNoWindowsCheckbox: NSButton!
    private var dockActionsCheckbox: NSButton!
    private var titleBarActionsCheckbox: NSButton!
    private var hoverCloseCheckbox: NSButton!
    private var keyboardNavCheckbox: NSButton!
    private var spotlightFixCheckbox: NSButton!
    private var hapticCheckbox: NSButton!
    private var cursorFeedbackCheckbox: NSButton!
    private var optimizedAnimationsCheckbox: NSButton!

    override func loadView() {
        view = NSView()

        let layoutView = SettingsLayoutView()
        layoutView.install(in: view)

        // Startup
        let startup = layoutView.addColumnSection(label: "Startup")
        launchAtLoginCheckbox = startup.addDescribedCheckbox(
            title: "Launch at Login",
            description: "Open MCSC automatically when you log in.",
            target: self,
            action: #selector(toggleLaunchAtLogin(_:))
        )

        layoutView.addSeparatorSection()

        // Behavior
        let behavior = layoutView.addColumnSection(label: "Behavior", itemColumnMaximumWidth: 340)
        autoEjectCheckbox = behavior.addDescribedCheckbox(
            title: "Auto-Eject Mounted Volumes",
            description: "Ejects the volume when you close its Finder window.",
            target: self,
            action: #selector(toggleAutoEject(_:))
        )
        behavior.addSpacing(6)
        quitAppIfNoWindowsCheckbox = behavior.addDescribedCheckbox(
            title: "Quit App When Last Window Closes",
            description: "Quits an application when you close its last open window.",
            target: self,
            action: #selector(toggleQuitAppIfNoWindows(_:))
        )
        behavior.addSpacing(6)
        dockActionsCheckbox = behavior.addDescribedCheckbox(
            title: "Dock Gestures and Shortcuts",
            description: "Enables gestures and Command shortcuts while hovering over Dock icons.",
            target: self,
            action: #selector(toggleDockActions(_:))
        )
        behavior.addSpacing(6)
        titleBarActionsCheckbox = behavior.addDescribedCheckbox(
            title: "Title Bar Gestures and Shortcuts",
            description: "Enables gestures and Command shortcuts while hovering over a window title bar.",
            target: self,
            action: #selector(toggleTitleBarActions(_:))
        )

        layoutView.addSeparatorSection()

        buildMissionControlAndFeedbackSections(on: layoutView)

        sizePaneToFitContent(minimumWidth: Self.minimumPaneWidth)
        refresh()
    }

    /// Mission Control, Feedback, and Restore Defaults sections.
    private func buildMissionControlAndFeedbackSections(on layoutView: SettingsLayoutView) {
        // Mission Control
        let missionControl = layoutView.addColumnSection(label: "Mission Control", itemColumnMaximumWidth: 340)
        hoverCloseCheckbox = missionControl.addDescribedCheckbox(
            title: "Hover Close Button",
            description: "Shows a close button on window thumbnails in Mission Control. Click to close, hold Command to quit, or hold Option to minimize.",
            target: self,
            action: #selector(toggleHoverClose(_:))
        )
        missionControl.addSpacing(6)
        keyboardNavCheckbox = missionControl.addDescribedCheckbox(
            title: "Keyboard Navigation",
            description: "Cycle through thumbnails with Tab and Shift-Tab, then press Return to activate. Type to filter windows by title.",
            target: self,
            action: #selector(toggleKeyboardNav(_:))
        )
        missionControl.addSpacing(6)
        spotlightFixCheckbox = missionControl.addDescribedCheckbox(
            title: "Spotlight Shortcut (⌘Space)",
            description: "Allows ⌘Space to open Spotlight while Mission Control is open.",
            target: self,
            action: #selector(toggleSpotlightFix(_:))
        )

        layoutView.addSeparatorSection()

        // Feedback
        let feedback = layoutView.addColumnSection(label: "Feedback", itemColumnMaximumWidth: 340)
        hapticCheckbox = feedback.addDescribedCheckbox(
            title: "Haptic Feedback",
            description: "Provides trackpad haptics when gestures or shortcuts trigger.",
            target: self,
            action: #selector(toggleHaptics(_:))
        )
        feedback.addSpacing(6)
        cursorFeedbackCheckbox = feedback.addDescribedCheckbox(
            title: "Cursor Feedback Overlay",
            description: "Briefly displays an icon next to the cursor when an action runs.",
            target: self,
            action: #selector(toggleCursorFeedback(_:))
        )
        feedback.addSpacing(6)
        optimizedAnimationsCheckbox = feedback.addDescribedCheckbox(
            title: "Reduced Animation Overhead",
            description: "Uses lightweight CoreAnimation effects instead of native symbol effects. Requires restarting MCSC.",
            target: self,
            action: #selector(toggleOptimizedAnimations(_:))
        )

        layoutView.addSeparatorSection()

        layoutView.addButtonSection(title: "Restore Defaults",
                                    alignment: .trailing,
                                    widthMode: .contentBlock,
                                    target: self,
                                    action: #selector(restoreDefaults(_:)))
    }

    override func refresh() {
        launchAtLoginCheckbox?.state = viewModel.isLaunchAtLoginEnabled ? .on : .off
        autoEjectCheckbox?.state = viewModel.isAutoEjectEnabled ? .on : .off
        quitAppIfNoWindowsCheckbox?.state = viewModel.isQuitAppIfNoWindowsEnabled ? .on : .off
        dockActionsCheckbox?.state = viewModel.isDockActionsOutsideMCEnabled ? .on : .off
        titleBarActionsCheckbox?.state = viewModel.isTitleBarActionsOutsideMCEnabled ? .on : .off
        hoverCloseCheckbox?.state = viewModel.isHoverCloseButtonEnabled ? .on : .off
        keyboardNavCheckbox?.state = viewModel.isKeyboardNavigationEnabled ? .on : .off
        spotlightFixCheckbox?.state = viewModel.isCmdSpaceEnabled ? .on : .off
        hapticCheckbox?.state = viewModel.isHapticFeedbackEnabled ? .on : .off
        cursorFeedbackCheckbox?.state = viewModel.isCursorFeedbackEnabled ? .on : .off
        optimizedAnimationsCheckbox?.state = viewModel.isOptimizedAnimationModeEnabled ? .on : .off
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
        viewModel.toggleLaunchAtLogin()
        sender.state = viewModel.isLaunchAtLoginEnabled ? .on : .off
    }

    @objc private func toggleAutoEject(_ sender: NSButton) {
        viewModel.isAutoEjectEnabled.toggle()
        sender.state = viewModel.isAutoEjectEnabled ? .on : .off
    }

    @objc private func toggleQuitAppIfNoWindows(_ sender: NSButton) {
        viewModel.isQuitAppIfNoWindowsEnabled.toggle()
        sender.state = viewModel.isQuitAppIfNoWindowsEnabled ? .on : .off
    }

    @objc private func toggleDockActions(_ sender: NSButton) {
        viewModel.isDockActionsOutsideMCEnabled.toggle()
        sender.state = viewModel.isDockActionsOutsideMCEnabled ? .on : .off
    }

    @objc private func toggleTitleBarActions(_ sender: NSButton) {
        viewModel.isTitleBarActionsOutsideMCEnabled.toggle()
        sender.state = viewModel.isTitleBarActionsOutsideMCEnabled ? .on : .off
    }

    @objc private func toggleHoverClose(_ sender: NSButton) {
        viewModel.isHoverCloseButtonEnabled.toggle()
        sender.state = viewModel.isHoverCloseButtonEnabled ? .on : .off
    }

    @objc private func toggleHaptics(_ sender: NSButton) {
        viewModel.isHapticFeedbackEnabled.toggle()
        sender.state = viewModel.isHapticFeedbackEnabled ? .on : .off
    }

    @objc private func toggleCursorFeedback(_ sender: NSButton) {
        viewModel.isCursorFeedbackEnabled.toggle()
        sender.state = viewModel.isCursorFeedbackEnabled ? .on : .off
    }

    @objc private func toggleOptimizedAnimations(_ sender: NSButton) {
        viewModel.isOptimizedAnimationModeEnabled.toggle()
        sender.state = viewModel.isOptimizedAnimationModeEnabled ? .on : .off

        let alert = NSAlert()
        alert.messageText = "Restart MCSC?"
        alert.informativeText = "MCSC must restart for this change to take effect."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Restart Now")
        alert.addButton(withTitle: "Later")

        if let window = view.window {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    Self.relaunchApp()
                }
            }
        } else {
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                Self.relaunchApp()
            }
        }
    }

    private static func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    @objc private func toggleKeyboardNav(_ sender: NSButton) {
        viewModel.isKeyboardNavigationEnabled.toggle()
        sender.state = viewModel.isKeyboardNavigationEnabled ? .on : .off
    }

    @objc private func toggleSpotlightFix(_ sender: NSButton) {
        viewModel.isCmdSpaceEnabled.toggle()
        sender.state = viewModel.isCmdSpaceEnabled ? .on : .off
    }

    @objc private func restoreDefaults(_: NSButton) {
        viewModel.isAutoEjectEnabled = true
        viewModel.isQuitAppIfNoWindowsEnabled = false
        viewModel.isDockActionsOutsideMCEnabled = false
        viewModel.isTitleBarActionsOutsideMCEnabled = false
        viewModel.isHoverCloseButtonEnabled = true
        viewModel.isKeyboardNavigationEnabled = true
        viewModel.isCmdSpaceEnabled = true
        viewModel.isHapticFeedbackEnabled = true
        viewModel.isCursorFeedbackEnabled = true
        viewModel.isOptimizedAnimationModeEnabled = true
        refreshAllPanes()
    }
}
