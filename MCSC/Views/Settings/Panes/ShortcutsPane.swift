import Cocoa

/// Shortcuts settings pane: tab strip, window chrome, app actions, and sizing
/// controls, grouped into Tab, Window, App, and Sizing sections. Each row's
/// recorder field shows its assigned combination. An action is active
/// while a combination is assigned.
final class ShortcutsPane: MCSCSettingsPane {
    /// Recorder fields keyed by the action they configure. `refresh()` reads
    /// state back into these.
    private var recorders: [RoutedAction: ShortcutRecorderField] = [:]
    private var tabShortcutsCheckbox: NSButton?

    override func loadView() {
        view = NSView()

        let layoutView = SettingsLayoutView()
        layoutView.install(in: view)

        buildTabSection(on: layoutView)
        buildWindowSection(on: layoutView)
        buildAppSection(on: layoutView)
        buildSizingSection(on: layoutView)

        sizePaneToFitContent(minimumWidth: Self.minimumPaneWidth)
        refresh()
    }

    /// Tab section: gates tab-targeted shortcuts when hovering a tab strip.
    private func buildTabSection(on layoutView: SettingsLayoutView) {
        let tabSection = layoutView.addColumnSection(label: "Tab", itemColumnMaximumWidth: 340)
        tabShortcutsCheckbox = tabSection.addDescribedCheckbox(
            title: "Enable Tab Shortcuts",
            description: "When enabled, hovering a window's tab strip uses tab-targeted shortcuts instead of closing the entire window.",
            target: self,
            action: #selector(toggleTabShortcuts(_:))
        )

        recorders[.closeTab] = addShortcutRow(
            section: tabSection, mode: .closeTab, title: "Close Tab", action: .closeTab
        )
        recorders[.newTab] = addShortcutRow(
            section: tabSection, mode: .newTab, title: "New Tab", action: .newTab
        )
        recorders[.reopenTab] = addShortcutRow(
            section: tabSection, mode: .reopenTab, title: "Reopen Tab", action: .reopenTab
        )
        tabSection.addDescriptionLabel(
            "Acts on the tab bar of the window under the cursor."
        )

        layoutView.addSeparatorSection()
    }

    /// Window section: window controls and desktop navigation.
    private func buildWindowSection(on layoutView: SettingsLayoutView) {
        let windowSection = layoutView.addColumnSection(label: "Window", itemColumnMaximumWidth: 340)
        recorders[.close] = addShortcutRow(
            section: windowSection, mode: .close, title: "Close", action: .close
        )
        recorders[.minimize] = addShortcutRow(
            section: windowSection, mode: .minimize, title: "Minimize", action: .minimize
        )
        recorders[.fullscreen] = addShortcutRow(
            section: windowSection, mode: .fullscreen, title: "Full Screen", action: .fullscreen
        )
        recorders[.moveNextDesktop] = addShortcutRow(
            section: windowSection, mode: .spaceRight, title: "Next Desktop", action: .moveNextDesktop
        )
        recorders[.movePreviousDesktop] = addShortcutRow(
            section: windowSection, mode: .spaceLeft, title: "Previous Desktop", action: .movePreviousDesktop
        )
        windowSection.addDescriptionLabel(
            "Acts on the window under the cursor. Click a field and press ⌘+Key, with optional Shift. Press Delete to clear."
        )

        layoutView.addSeparatorSection()
    }

    /// App section: app-level actions (quit, hide, unminimize, and new window).
    private func buildAppSection(on layoutView: SettingsLayoutView) {
        let appSection = layoutView.addColumnSection(label: "App", itemColumnMaximumWidth: 340)
        recorders[.quit] = addShortcutRow(
            section: appSection, mode: .quit, title: "Quit", action: .quit
        )
        recorders[.hide] = addShortcutRow(
            section: appSection, mode: .hide, title: "Hide", action: .hide
        )
        recorders[.unminimizeAll] = addShortcutRow(
            section: appSection, mode: .unminimizeAll, title: "Unminimize", action: .unminimizeAll
        )
        recorders[.newWindow] = addShortcutRow(
            section: appSection, mode: .newWindow, title: "New Window", action: .newWindow
        )
        appSection.addDescriptionLabel(
            "Acts on the app under the cursor or Dock icon. Click a field and press ⌘+Key, with optional Shift. Press Delete to clear."
        )

        layoutView.addSeparatorSection()
    }

    /// Sizing section: window resizing shortcuts.
    private func buildSizingSection(on layoutView: SettingsLayoutView) {
        let sizingSection = layoutView.addColumnSection(label: "Sizing", itemColumnMaximumWidth: 340)
        recorders[.fillScreen] = addShortcutRow(
            section: sizingSection, mode: .maximize, title: "Fill Screen", action: .fillScreen
        )
        recorders[.reasonableSize] = addShortcutRow(
            section: sizingSection, mode: .reasonable, title: "Small and Center", action: .reasonableSize
        )
        recorders[.makeLarger] = addShortcutRow(
            section: sizingSection, mode: .maximize, title: "Larger", action: .makeLarger
        )
        recorders[.makeSmaller] = addShortcutRow(
            section: sizingSection, mode: .makeSmaller, title: "Smaller", action: .makeSmaller
        )
        recorders[.leftCycleSnap] = addShortcutRow(
            section: sizingSection, mode: .leftCycleSnap, title: "Left Cycle Snap", action: .leftCycleSnap
        )
        recorders[.rightCycleSnap] = addShortcutRow(
            section: sizingSection, mode: .rightCycleSnap, title: "Right Cycle Snap", action: .rightCycleSnap
        )
        sizingSection.addDescriptionLabel(
            "Resizes the window under the cursor. Assign shortcuts here or trigger them with gestures."
        )

        layoutView.addSeparatorSection()

        layoutView.addButtonSection(title: "Restore Defaults",
                                    alignment: .trailing,
                                    widthMode: .contentBlock,
                                    target: self,
                                    action: #selector(restoreShortcutDefaults(_:)))
    }

    override func refresh() {
        tabShortcutsCheckbox?.state = viewModel.isTabShortcutsEnabled ? .on : .off
        updateTabRecordersEnabledState()
        for (action, recorder) in recorders {
            recorder.binding = viewModel.config.binding(for: action)
        }
    }

    @objc private func toggleTabShortcuts(_ sender: NSButton) {
        viewModel.isTabShortcutsEnabled = sender.state == .on
        updateTabRecordersEnabledState()
    }

    private func updateTabRecordersEnabledState() {
        let isEnabled = viewModel.isTabShortcutsEnabled
        recorders[.closeTab]?.isEnabled = isEnabled
        recorders[.reopenTab]?.isEnabled = isEnabled
        recorders[.newTab]?.isEnabled = isEnabled
    }
}

typealias WindowShortcutsPane = ShortcutsPane
