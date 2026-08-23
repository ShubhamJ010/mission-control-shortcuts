import Cocoa

/// Base class for MCSC settings panes: holds the view model and refreshes
/// checkbox states every time the settings window is shown.
class MCSCSettingsPane: SettingsPaneViewController {
    let viewModel: ShortcutViewModel

    init(viewModel: ShortcutViewModel,
         tabName: String,
         tabImage: NSImage?,
         tabIdentifier: String) {
        self.viewModel = viewModel
        super.init(tabName: tabName,
                   tabImage: tabImage,
                   tabIdentifier: tabIdentifier)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    /// Re-read state from the view model into the controls.
    func refresh() {}

    /// The narrowest width every pane is laid out for. Matches the clone demo's 500pt (ref:
    /// DemoViewControllers.swift:56).
    static let minimumPaneWidth: CGFloat = 500
}

// MARK: - Shared helpers

extension SettingsColumnSectionView {
    /// Adds a checkbox with a description label beneath it — the dominant
    /// toggle pattern across panes. Returns the checkbox for outlet storage.
    @discardableResult
    func addDescribedCheckbox(title: String, description: String, target: AnyObject?, action: Selector?) -> NSButton {
        let checkbox = addCheckbox(title: title, target: target, action: action)
        addDescriptionLabel(description)
        return checkbox
    }
}

// MARK: - General

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

        sizePaneToFitContent(minimumWidth: Self.minimumPaneWidth)
        refresh()
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

// MARK: - Shortcuts

final class ShortcutSettingsPane: MCSCSettingsPane {
    // Existing core
    private var cmdWCheckbox: NSButton!
    private var cmdQCheckbox: NSButton!
    private var cmdMCheckbox: NSButton!
    private var cmdHCheckbox: NSButton!
    private var cmdFCheckbox: NSButton!
    private var cmdTCheckbox: NSButton!
    private var cmdNCheckbox: NSButton!
    private var cmdShiftWCheckbox: NSButton!
    private var cmdShiftTCheckbox: NSButton!
    // New — window/size/desktop (off by default, gesture-only previously)
    private var closeWindowCheckbox: NSButton!
    private var fillScreenCheckbox: NSButton!
    private var almostMaximizeCheckbox: NSButton!
    private var reasonableSizeCheckbox: NSButton!
    private var makeLargerCheckbox: NSButton!
    private var makeSmallerCheckbox: NSButton!
    private var moveNextDesktopCheckbox: NSButton!
    private var movePreviousDesktopCheckbox: NSButton!

    override func loadView() {
        view = NSView()

        let layoutView = SettingsLayoutView()
        layoutView.install(in: view)

        // Group 2: Window — window chrome + size + desktop (Applies to window under cursor / Dock icon)
        let windowSection = layoutView.addColumnSection(label: "Window", itemColumnMaximumWidth: 340)
        closeWindowCheckbox = addShortcutCheckbox(
            section: windowSection,
            mode: .close,
            title: "⌘ + ⇧ + E  — Close Window",
            action: #selector(toggleCloseWindow(_:))
        )
        cmdMCheckbox = addShortcutCheckbox(
            section: windowSection,
            mode: .minimize,
            title: "⌘ + M  — Minimize",
            action: #selector(toggleCmdM(_:))
        )
        cmdFCheckbox = addShortcutCheckbox(
            section: windowSection,
            mode: .fullscreen,
            title: "⌘ + F  — Toggle Fullscreen",
            action: #selector(toggleCmdF(_:))
        )
        fillScreenCheckbox = addShortcutCheckbox(
            section: windowSection,
            mode: .maximize,
            title: "⌘ + ⇧ + D  — Fill Screen",
            action: #selector(toggleFillScreen(_:))
        )
        almostMaximizeCheckbox = addShortcutCheckbox(
            section: windowSection,
            mode: .almost,
            title: "⌘ + ⇧ + A  — Almost Maximize",
            action: #selector(toggleAlmostMaximize(_:))
        )
        reasonableSizeCheckbox = addShortcutCheckbox(
            section: windowSection,
            mode: .reasonable,
            title: "⌘ + ⇧ + R  — Reasonable Size",
            action: #selector(toggleReasonableSize(_:))
        )
        makeLargerCheckbox = addShortcutCheckbox(
            section: windowSection,
            mode: .maximize,
            title: "⌘ + ⇧ + L  — Make Larger",
            action: #selector(toggleMakeLarger(_:))
        )
        makeSmallerCheckbox = addShortcutCheckbox(
            section: windowSection,
            mode: .makeSmaller,
            title: "⌘ + ⇧ + S  — Make Smaller",
            action: #selector(toggleMakeSmaller(_:))
        )
        moveNextDesktopCheckbox = addShortcutCheckbox(
            section: windowSection,
            mode: .spaceRight,
            title: "⌘ + ⇧ + →  — Move to Next Desktop",
            action: #selector(toggleMoveNextDesktop(_:))
        )
        movePreviousDesktopCheckbox = addShortcutCheckbox(
            section: windowSection,
            mode: .spaceLeft,
            title: "⌘ + ⇧ + ←  — Move to Previous Desktop",
            action: #selector(toggleMovePreviousDesktop(_:))
        )
        windowSection
            .addDescriptionLabel(
                "Acts on the window under the cursor. Size/Desktop shortcuts are gesture-only by default — enable to create a keyboard shortcut."
            )

        layoutView.addSeparatorSection()

        // Group 3: Tab — tab strip actions (Applies to window tab bar)
        let tabSection = layoutView.addColumnSection(label: "Tab", itemColumnMaximumWidth: 340)
        cmdWCheckbox = addShortcutCheckbox(
            section: tabSection,
            mode: .closeTab,
            title: "⌘ + W  — Close Tab",
            action: #selector(toggleCmdW(_:))
        )
        cmdShiftWCheckbox = addShortcutCheckbox(
            section: tabSection,
            mode: .closeAllTabs,
            title: "⌘ + ⇧ + W  — Close All Tabs",
            action: #selector(toggleCmdShiftW(_:))
        )
        cmdShiftTCheckbox = addShortcutCheckbox(
            section: tabSection,
            mode: .reopenTab,
            title: "⌘ + ⇧ + T  — Reopen Tab",
            action: #selector(toggleCmdShiftT(_:))
        )
        cmdTCheckbox = addShortcutCheckbox(
            section: tabSection,
            mode: .newTab,
            title: "⌘ + T  — New Tab",
            action: #selector(toggleCmdT(_:))
        )
        tabSection
            .addDescriptionLabel(
                "Acts on the tab bar of the window under the cursor (falls back to Cmd+W/Cmd+T keystroke when no tab strip)."
            )

        layoutView.addSeparatorSection()

        // Group 4: App — app-targeted actions (Dock)
        let appShortcuts = layoutView.addColumnSection(label: "App", itemColumnMaximumWidth: 340)
        cmdQCheckbox = addShortcutCheckbox(
            section: appShortcuts,
            mode: .quit,
            title: "⌘ + Q  — Quit App",
            action: #selector(toggleCmdQ(_:))
        )
        cmdHCheckbox = addShortcutCheckbox(
            section: appShortcuts,
            mode: .hide,
            title: "⌘ + H  — Hide App",
            action: #selector(toggleCmdH(_:))
        )
        cmdNCheckbox = addShortcutCheckbox(
            section: appShortcuts,
            mode: .newWindow,
            title: "⌘ + N  — New Window",
            action: #selector(toggleCmdN(_:))
        )
        appShortcuts.addDescriptionLabel("Acts on the app owning the window / Dock icon under the cursor.")

        layoutView.addSeparatorSection()

        layoutView.addButtonSection(title: "Restore Defaults",
                                    alignment: .trailing,
                                    widthMode: .contentBlock,
                                    target: self,
                                    action: #selector(restoreDefaults(_:)))

        sizePaneToFitContent(minimumWidth: Self.minimumPaneWidth)
        refresh()
    }

    private func addShortcutCheckbox(
        section: SettingsColumnSectionView,
        mode: CursorFeedbackOverlay.Mode,
        title: String,
        action: Selector
    ) -> NSButton {
        let checkbox = section.addCheckbox(title: title, target: self, action: action)
        checkbox.attributedTitle = makeAttributedTitle(mode: mode, title: title)
        return checkbox
    }

    private func makeAttributedTitle(mode: CursorFeedbackOverlay.Mode, title: String) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let attrString = NSMutableAttributedString()

        if let image = SymbolImageFactory.make(
            symbolName: mode.symbolName,
            description: mode.accessibilityDescription,
            paletteColors: mode.paletteColors,
            pointSize: 13,
            weight: .medium
        ) {
            let attachment = NSTextAttachment()
            attachment.image = image
            let imageSize = image.size
            let yOffset = (font.capHeight - imageSize.height) / 2.0
            attachment.bounds = CGRect(x: 0, y: yOffset.rounded(), width: imageSize.width, height: imageSize.height)
            attrString.append(NSAttributedString(attachment: attachment))
            attrString.append(NSAttributedString(string: "  ", attributes: [.font: font]))
        }

        attrString.append(NSAttributedString(string: title, attributes: [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ]))

        return attrString
    }

    override func refresh() {
        cmdWCheckbox?.state = viewModel.isCmdWEnabled ? .on : .off
        cmdQCheckbox?.state = viewModel.isCmdQEnabled ? .on : .off
        cmdMCheckbox?.state = viewModel.isCmdMEnabled ? .on : .off
        cmdHCheckbox?.state = viewModel.isCmdHEnabled ? .on : .off
        cmdFCheckbox?.state = viewModel.isCmdFEnabled ? .on : .off
        cmdTCheckbox?.state = viewModel.isCmdTEnabled ? .on : .off
        cmdNCheckbox?.state = viewModel.isCmdNEnabled ? .on : .off
        cmdShiftWCheckbox?.state = viewModel.isCmdShiftWEnabled ? .on : .off
        cmdShiftTCheckbox?.state = viewModel.isCmdShiftTEnabled ? .on : .off
        closeWindowCheckbox?.state = viewModel.isCloseWindowEnabled ? .on : .off
        fillScreenCheckbox?.state = viewModel.isFillScreenEnabled ? .on : .off
        almostMaximizeCheckbox?.state = viewModel.isAlmostMaximizeEnabled ? .on : .off
        reasonableSizeCheckbox?.state = viewModel.isReasonableSizeEnabled ? .on : .off
        makeLargerCheckbox?.state = viewModel.isMakeLargerEnabled ? .on : .off
        makeSmallerCheckbox?.state = viewModel.isMakeSmallerEnabled ? .on : .off
        moveNextDesktopCheckbox?.state = viewModel.isMoveNextDesktopEnabled ? .on : .off
        movePreviousDesktopCheckbox?.state = viewModel.isMovePreviousDesktopEnabled ? .on : .off
    }

    @objc private func toggleCmdW(_ sender: NSButton) {
        viewModel.isCmdWEnabled.toggle()
        sender.state = viewModel.isCmdWEnabled ? .on : .off
    }

    @objc private func toggleCmdQ(_ sender: NSButton) {
        viewModel.isCmdQEnabled.toggle()
        sender.state = viewModel.isCmdQEnabled ? .on : .off
    }

    @objc private func toggleCmdM(_ sender: NSButton) {
        viewModel.isCmdMEnabled.toggle()
        sender.state = viewModel.isCmdMEnabled ? .on : .off
    }

    @objc private func toggleCmdH(_ sender: NSButton) {
        viewModel.isCmdHEnabled.toggle()
        sender.state = viewModel.isCmdHEnabled ? .on : .off
    }

    @objc private func toggleCmdF(_ sender: NSButton) {
        viewModel.isCmdFEnabled.toggle()
        sender.state = viewModel.isCmdFEnabled ? .on : .off
    }

    @objc private func toggleCmdT(_ sender: NSButton) {
        viewModel.isCmdTEnabled.toggle()
        sender.state = viewModel.isCmdTEnabled ? .on : .off
    }

    @objc private func toggleCmdN(_ sender: NSButton) {
        viewModel.isCmdNEnabled.toggle()
        sender.state = viewModel.isCmdNEnabled ? .on : .off
    }

    @objc private func toggleCmdShiftW(_ sender: NSButton) {
        viewModel.isCmdShiftWEnabled.toggle()
        sender.state = viewModel.isCmdShiftWEnabled ? .on : .off
    }

    @objc private func toggleCmdShiftT(_ sender: NSButton) {
        viewModel.isCmdShiftTEnabled.toggle()
        sender.state = viewModel.isCmdShiftTEnabled ? .on : .off
    }

    @objc private func toggleCloseWindow(_ sender: NSButton) {
        viewModel.isCloseWindowEnabled.toggle()
        sender.state = viewModel.isCloseWindowEnabled ? .on : .off
    }

    @objc private func toggleFillScreen(_ sender: NSButton) {
        viewModel.isFillScreenEnabled.toggle()
        sender.state = viewModel.isFillScreenEnabled ? .on : .off
    }

    @objc private func toggleAlmostMaximize(_ sender: NSButton) {
        viewModel.isAlmostMaximizeEnabled.toggle()
        sender.state = viewModel.isAlmostMaximizeEnabled ? .on : .off
    }

    @objc private func toggleReasonableSize(_ sender: NSButton) {
        viewModel.isReasonableSizeEnabled.toggle()
        sender.state = viewModel.isReasonableSizeEnabled ? .on : .off
    }

    @objc private func toggleMakeLarger(_ sender: NSButton) {
        viewModel.isMakeLargerEnabled.toggle()
        sender.state = viewModel.isMakeLargerEnabled ? .on : .off
    }

    @objc private func toggleMakeSmaller(_ sender: NSButton) {
        viewModel.isMakeSmallerEnabled.toggle()
        sender.state = viewModel.isMakeSmallerEnabled ? .on : .off
    }

    @objc private func toggleMoveNextDesktop(_ sender: NSButton) {
        viewModel.isMoveNextDesktopEnabled.toggle()
        sender.state = viewModel.isMoveNextDesktopEnabled ? .on : .off
    }

    @objc private func toggleMovePreviousDesktop(_ sender: NSButton) {
        viewModel.isMovePreviousDesktopEnabled.toggle()
        sender.state = viewModel.isMovePreviousDesktopEnabled ? .on : .off
    }

    @objc private func restoreDefaults(_: NSButton) {
        viewModel.isCmdWEnabled = true
        viewModel.isCmdQEnabled = true
        viewModel.isCmdMEnabled = true
        viewModel.isCmdHEnabled = true
        viewModel.isCmdFEnabled = false
        viewModel.isCmdTEnabled = false
        viewModel.isCmdNEnabled = false
        viewModel.isCmdShiftWEnabled = false
        viewModel.isCmdShiftTEnabled = false
        viewModel.isCloseWindowEnabled = false
        viewModel.isFillScreenEnabled = false
        viewModel.isAlmostMaximizeEnabled = false
        viewModel.isReasonableSizeEnabled = false
        viewModel.isMakeLargerEnabled = false
        viewModel.isMakeSmallerEnabled = false
        viewModel.isMoveNextDesktopEnabled = false
        viewModel.isMovePreviousDesktopEnabled = false
        refreshAllPanes()
    }
}

// MARK: - Gestures

final class GestureSettingsPane: MCSCSettingsPane {
    /// Demo General pane caps the item column — keeps pop-ups from stretching edge-to-edge.
    private static let itemColumnMaximumWidth: CGFloat = 250

    private var layoutView: SettingsLayoutView?
    private var gesturesMasterCheckbox: NSButton!

    private struct GestureRow {
        let kind: GestureKind
        let section: SettingsColumnSectionView
        let actionPopup: NSPopUpButton
        let cmdActionPopup: NSPopUpButton
        let enableSwitch: NSSwitch
    }

    private var gestureRows: [GestureRow] = []

    override func loadView() {
        view = NSView()
        buildSections()
        sizePaneToFitContent(minimumWidth: Self.minimumPaneWidth)
        refresh()
    }

    private func buildSections() {
        let layoutView = SettingsLayoutView()
        layoutView.install(in: view)
        self.layoutView = layoutView

        // Master switch — full-width checkbox with description, like DemoViewControllers General "Startup"
        let master = layoutView.addCheckboxSection(title: "Enable Gestures",
                                                   description: "Master switch for all trackpad gesture recognition. Individual gestures can be toggled below.",
                                                   identifier: .init("Master"),
                                                   target: self,
                                                   action: #selector(toggleGestures(_:)))
        gesturesMasterCheckbox = master.checkbox

        layoutView.addSeparatorSection(identifier: .init("Sep.Master"))

        // One column section per gesture — label in the label column, popup + checkbox accessory in the item column,
        // ⌘ variant as a second stacked item. Splitting into Pinch / Swipe / Tap groups with
        // separators mirrors the demo's section grouping and breaks up the 7-row wall (Guide/#sections).
        var gestureIndex = 0
        func addGestureRow(kind: GestureKind) {
            let isFirst = (gestureIndex == 0)
            let section = layoutView.addColumnSection(label: kind.displayName,
                                                      itemColumnMaximumWidth: isFirst ? Self
                                                          .itemColumnMaximumWidth : nil,
                                                      identifier: .init(kind.rawValue))

            // Primary action — only natural actions for this gesture kind
            let popup = section.addPopUpButton(
                controlSize: .regular,
                target: self,
                action: #selector(actionChanged(_:))
            )
            for action in kind.naturalActions {
                popup.addItem(withTitle: action.menuTitle)
                popup.lastItem?.representedObject = action.rawValue
            }
            popup.tag = gestureIndex

            // Toggle switch
            let toggle = NSSwitch()
            toggle.target = self
            toggle.action = #selector(toggleGestureEnabled(_:))
            toggle.controlSize = .regular
            toggle.tag = gestureIndex
            section.addAccessoryView(toggle, to: popup, spacing: 12)

            let gapView = NSView(frame: .zero)
            gapView.translatesAutoresizingMaskIntoConstraints = false
            gapView.heightAnchor.constraint(equalToConstant: 4).isActive = true
            section.addCustomView(gapView, verticalAlignment: .centerY)
            gapView.setContentHuggingPriority(.defaultLow, for: .horizontal)
            gapView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            // ⌘ variant — second stacked item, regular size
            let cmdRow = NSStackView()
            cmdRow.orientation = .horizontal
            cmdRow.spacing = 6
            cmdRow.alignment = .centerY

            let cmdLabel = NSTextField(labelWithString: "⌘")
            cmdLabel.font = .systemFont(ofSize: 18, weight: .semibold)
            cmdLabel.textColor = .secondaryLabelColor
            cmdLabel.setContentHuggingPriority(.required, for: .horizontal)

            let cmdPopup = NSPopUpButton(frame: .zero, pullsDown: false)
            cmdPopup.controlSize = .regular
            SettingsSectionView.applyControlSize(.regular, to: cmdPopup)
            cmdPopup.target = self
            cmdPopup.action = #selector(cmdActionChanged(_:))
            cmdPopup.tag = gestureIndex
            for action in kind.naturalActions {
                cmdPopup.addItem(withTitle: action.menuTitle)
                cmdPopup.lastItem?.representedObject = action.rawValue
            }

            cmdRow.addArrangedSubview(cmdLabel)
            cmdRow.addArrangedSubview(cmdPopup)
            cmdPopup.setContentHuggingPriority(.defaultHigh, for: .horizontal)

            section.addCustomView(cmdRow, verticalAlignment: .centerY)

            gestureRows.append(GestureRow(
                kind: kind,
                section: section,
                actionPopup: popup,
                cmdActionPopup: cmdPopup,
                enableSwitch: toggle
            ))
            gestureIndex += 1
        }

        // Group: Pinch (2)
        addGestureRow(kind: .pinchIn)
        addGestureRow(kind: .pinchOut)
        layoutView.addSeparatorSection(identifier: .init("Sep.Pinch"))
        // Group: Swipe (4) — the bulk of the pane
        addGestureRow(kind: .swipeLeft)
        addGestureRow(kind: .swipeRight)
        addGestureRow(kind: .swipeDown)
        addGestureRow(kind: .swipeUp)
        layoutView.addSeparatorSection(identifier: .init("Sep.Swipe"))
        // Group: Tap (1)
        addGestureRow(kind: .twoFingerDoubleTap)

        layoutView.addSeparatorSection(identifier: .init("Sep.Restore"))

        layoutView.addButtonSection(title: "Restore Defaults",
                                    controlSize: .regular,
                                    alignment: .trailing,
                                    widthMode: .contentBlock,
                                    identifier: .init("RestoreDefaults"),
                                    target: self,
                                    action: #selector(restoreDefaults(_:)))
    }

    override func refresh() {
        gesturesMasterCheckbox?.state = viewModel.isGesturesEnabled ? .on : .off

        let masterOn = viewModel.isGesturesEnabled
        for row in gestureRows {
            let kindEnabled: Bool = switch row.kind {
            case .pinchIn: viewModel.isPinchInEnabled
            case .pinchOut: viewModel.isPinchOutEnabled
            case .swipeLeft: viewModel.isSwipeLeftEnabled
            case .swipeRight: viewModel.isSwipeRightEnabled
            case .swipeDown: viewModel.isSwipeDownEnabled
            case .swipeUp: viewModel.isSwipeUpEnabled
            case .twoFingerDoubleTap: viewModel.isTwoFingerDoubleTapEnabled
            }
            let rowEnabled = masterOn && kindEnabled
            row.enableSwitch.state = kindEnabled ? .on : .off
            row.enableSwitch.isEnabled = masterOn
            row.actionPopup.isEnabled = rowEnabled
            row.cmdActionPopup.isEnabled = rowEnabled

            var plainAction = viewModel.gestureAction(for: row.kind, isCmd: false)
            var cmdAction = viewModel.gestureAction(for: row.kind, isCmd: true)
            // Stale persisted bindings (from when all actions were offered) are
            // reset to the factory default — keeps popups always showing a valid selection.
            if !row.kind.naturalActions.contains(plainAction) {
                plainAction = GestureDefaults.action(for: row.kind, isCmd: false)
                viewModel.setGestureAction(plainAction, for: row.kind, isCmd: false)
            }
            if !row.kind.naturalActions.contains(cmdAction) {
                cmdAction = GestureDefaults.action(for: row.kind, isCmd: true)
                viewModel.setGestureAction(cmdAction, for: row.kind, isCmd: true)
            }
            if let idx = row.actionPopup.itemArray
                .firstIndex(where: { ($0.representedObject as? String) == plainAction.rawValue }) {
                row.actionPopup.selectItem(at: idx)
            }
            if let idx = row.cmdActionPopup.itemArray
                .firstIndex(where: { ($0.representedObject as? String) == cmdAction.rawValue }) {
                row.cmdActionPopup.selectItem(at: idx)
            }
        }
    }

    private func setGestureEnabled(_ kind: GestureKind, enabled: Bool) {
        switch kind {
        case .pinchIn: viewModel.isPinchInEnabled = enabled
        case .pinchOut: viewModel.isPinchOutEnabled = enabled
        case .swipeLeft: viewModel.isSwipeLeftEnabled = enabled
        case .swipeRight: viewModel.isSwipeRightEnabled = enabled
        case .swipeDown: viewModel.isSwipeDownEnabled = enabled
        case .swipeUp: viewModel.isSwipeUpEnabled = enabled
        case .twoFingerDoubleTap: viewModel.isTwoFingerDoubleTapEnabled = enabled
        }
    }

    @objc private func toggleGestures(_ sender: NSButton) {
        viewModel.isGesturesEnabled.toggle()
        sender.state = viewModel.isGesturesEnabled ? .on : .off
        refresh()
    }

    @objc private func toggleGestureEnabled(_ sender: NSSwitch) {
        guard let kind = GestureKind.allCases[safe: sender.tag] else { return }
        let enabled = (sender.state == .on)
        setGestureEnabled(kind, enabled: enabled)
        refresh()
    }

    @objc private func actionChanged(_ sender: NSPopUpButton) {
        guard let kind = GestureKind.allCases[safe: sender.tag],
              let raw = sender.selectedItem?.representedObject as? String,
              let action = GestureAction(rawValue: raw) else { return }
        viewModel.setGestureAction(action, for: kind, isCmd: false)
    }

    @objc private func cmdActionChanged(_ sender: NSPopUpButton) {
        guard let kind = GestureKind.allCases[safe: sender.tag],
              let raw = sender.selectedItem?.representedObject as? String,
              let action = GestureAction(rawValue: raw) else { return }
        viewModel.setGestureAction(action, for: kind, isCmd: true)
    }

    @objc private func restoreDefaults(_: NSButton) {
        viewModel.isGesturesEnabled = true
        viewModel.isPinchInEnabled = true
        viewModel.isPinchOutEnabled = true
        viewModel.isSwipeLeftEnabled = true
        viewModel.isSwipeRightEnabled = true
        viewModel.isSwipeDownEnabled = true
        viewModel.isSwipeUpEnabled = true
        viewModel.isTwoFingerDoubleTapEnabled = true
        viewModel.resetGestureMappings()
        refreshAllPanes()
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Shared helpers

extension MCSCSettingsPane {
    /// Re-syncs every visible pane after a Restore Defaults action.
    func refreshAllPanes() {
        tabViewController?.panes.forEach { ($0 as? MCSCSettingsPane)?.refresh() }
    }
}
