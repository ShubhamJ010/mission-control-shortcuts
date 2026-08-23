import Cocoa

/// Shortcuts settings pane: per-shortcut enable toggles grouped by category.
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

        buildTabAndAppSections(on: layoutView)

        sizePaneToFitContent(minimumWidth: Self.minimumPaneWidth)
        refresh()
    }

    /// Tab-group and App-group shortcut sections plus the trailing
    /// Restore Defaults button. Split out of `loadView` for readability.
    private func buildTabAndAppSections(on layoutView: SettingsLayoutView) {
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
            .foregroundColor: NSColor.labelColor
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
