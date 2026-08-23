import Cocoa

/// General settings pane: launch-at-login, hover-close button, dock
/// actions, keyboard navigation and animation mode toggles.
final class GeneralSettingsPane: MCSCSettingsPane {
    private var launchAtLoginCheckbox: NSButton!
    private var autoEjectCheckbox: NSButton!
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

        // Startup — single toggle, no description needed.
        let startup = layoutView.addColumnSection(label: "Startup")
        launchAtLoginCheckbox = startup.addCheckbox(title: "Launch at Login",
                                                    target: self,
                                                    action: #selector(toggleLaunchAtLogin(_:)))

        layoutView.addSeparatorSection()

        // Behavior — core, always-visible toggles.
        let behavior = layoutView.addColumnSection(label: "Behavior", itemColumnMaximumWidth: 340)
        autoEjectCheckbox = behavior.addCheckbox(title: "Auto-Eject Mounted Volumes",
                                                 target: self,
                                                 action: #selector(toggleAutoEject(_:)))
        dockActionsCheckbox = behavior.addDescribedCheckbox(
            title: "Dock Gestures & Shortcuts",
            description: "Gestures & Cmd-shortcuts while hovering Dock icons.",
            target: self,
            action: #selector(toggleDockActions(_:))
        )
        titleBarActionsCheckbox = behavior.addDescribedCheckbox(
            title: "Title Bar Gestures & Shortcuts",
            description: "Gestures & Cmd-shortcuts while hovering the frontmost window's title bar.",
            target: self,
            action: #selector(toggleTitleBarActions(_:))
        )
        hoverCloseCheckbox = behavior.addDescribedCheckbox(
            title: "Hover Close Button",
            description: "Shows a close button when hovering window thumbnails in Mission Control. Click to close; Cmd = quit, Option = minimize.",
            target: self,
            action: #selector(toggleHoverClose(_:))
        )

        layoutView.addSeparatorSection()

        buildMissionControlAndFeedbackSections(on: layoutView)

        sizePaneToFitContent(minimumWidth: Self.minimumPaneWidth)
        refresh()
    }

    /// Mission Control — keyboard navigation & Spotlight fix (moved from the
    /// Shortcuts pane for better grouping) plus the Feedback section and the
    /// Restore Defaults button. Split out of `loadView` for readability.
    private func buildMissionControlAndFeedbackSections(on layoutView: SettingsLayoutView) {
        // Mission Control — keyboard navigation & Spotlight fix (moved from Shortcuts pane for better grouping)
        let missionControl = layoutView.addColumnSection(label: "Mission Control", itemColumnMaximumWidth: 340)
        keyboardNavCheckbox = missionControl.addDescribedCheckbox(
            title: "Keyboard Navigation (Tab / Return)",
            description: "Tab / Shift+Tab cycle the selection between visible thumbnails row-major "
                + "(wrap-around). Return activates the selected window. Typing filters windows fuzzy "
                + "(e.g. “code” matches Xcode + Code) and Tab cycles only the filtered matches.",
            target: self,
            action: #selector(toggleKeyboardNav(_:))
        )
        let mcGapView = NSView(frame: .zero)
        mcGapView.translatesAutoresizingMaskIntoConstraints = false
        mcGapView.heightAnchor.constraint(equalToConstant: 8).isActive = true
        missionControl.addCustomView(mcGapView, verticalAlignment: .centerY)
        mcGapView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        mcGapView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        spotlightFixCheckbox = missionControl.addDescribedCheckbox(
            title: "Restore Spotlight (⌘ + Space) in Mission Control",
            description: "Fixes Mission Control blocking Spotlight. Re-sends ⌘+Space when Mission Control is visible so Spotlight still opens.",
            target: self,
            action: #selector(toggleSpotlightFix(_:))
        )

        layoutView.addSeparatorSection()

        // Feedback — on by default (configurable, previously forced-on).
        let feedback = layoutView.addColumnSection(label: "Feedback", itemColumnMaximumWidth: 340)
        hapticCheckbox = feedback.addDescribedCheckbox(
            title: "Haptic Feedback",
            description: "Plays trackpad haptics on gesture/shortcut actions.",
            target: self,
            action: #selector(toggleHaptics(_:))
        )
        cursorFeedbackCheckbox = feedback.addDescribedCheckbox(
            title: "Cursor Flash Overlay",
            description: "Flashes an icon at the cursor when an action fires.",
            target: self,
            action: #selector(toggleCursorFeedback(_:))
        )
        let feedbackGapView = NSView(frame: .zero)
        feedbackGapView.translatesAutoresizingMaskIntoConstraints = false
        feedbackGapView.heightAnchor.constraint(equalToConstant: 8).isActive = true
        feedback.addCustomView(feedbackGapView, verticalAlignment: .centerY)
        feedbackGapView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        feedbackGapView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        optimizedAnimationsCheckbox = feedback.addDescribedCheckbox(
            title: "Optimized Animation Mode (Requires Restart)",
            description: "Zero-overhead CoreAnimation effects. Uncheck and restart the app to use native Apple SF Symbol Effects.",
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
        alert.informativeText = "Changing the animation mode requires restarting MCSC for the changes to take effect."
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
        viewModel.isDockActionsOutsideMCEnabled = true
        viewModel.isHoverCloseButtonEnabled = true
        viewModel.isKeyboardNavigationEnabled = true
        viewModel.isCmdSpaceEnabled = true
        viewModel.isHapticFeedbackEnabled = true
        viewModel.isCursorFeedbackEnabled = true
        viewModel.isOptimizedAnimationModeEnabled = true
        refreshAllPanes()
    }
}
