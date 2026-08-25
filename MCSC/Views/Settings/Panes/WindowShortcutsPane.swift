import Cocoa

/// Windows shortcuts settings pane: window chrome, tab strip actions and
/// sizing toggles, grouped into Window / Tab / Sizing sections. Each row's
/// recorder field shows its assigned combination; an action is active exactly
/// while a combination is assigned.
final class WindowShortcutsPane: MCSCSettingsPane {
    /// Recorder fields keyed by the action they configure — `refresh()` reads
    /// state back into these.
    private var recorders: [RoutedAction: ShortcutRecorderField] = [:]

    override func loadView() {
        view = NSView()

        let layoutView = SettingsLayoutView()
        layoutView.install(in: view)

        // Group 1: Window — window chrome + desktop moves (Applies to window
        // under cursor / Dock icon).
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
        windowSection
            .addDescriptionLabel(
                "Acts on the window under the cursor. Click a field and press ⌘+Key (⇧ optional) to assign or " +
                    "change a shortcut; Delete clears it and disables the action."
            )

        layoutView.addSeparatorSection()

        buildTabSection(on: layoutView)

        buildSizingSection(on: layoutView)

        sizePaneToFitContent(minimumWidth: Self.minimumPaneWidth)
        refresh()
    }

    private var tabShortcutsCheckbox: NSButton?

    /// Tab-group shortcuts: tab strip actions (Applies to window tab bar).
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
        recorders[.closeAllTabs] = addShortcutRow(
            section: tabSection, mode: .closeAllTabs, title: "Close All Tabs", action: .closeAllTabs
        )
        recorders[.reopenTab] = addShortcutRow(
            section: tabSection, mode: .reopenTab, title: "Reopen Tab", action: .reopenTab
        )
        recorders[.newTab] = addShortcutRow(
            section: tabSection, mode: .newTab, title: "New Tab", action: .newTab
        )
        tabSection
            .addDescriptionLabel(
                "Acts on the tab bar of the window under the cursor."
            )

        layoutView.addSeparatorSection()
    }

    /// Sizing sub-section: resize actions (Fill Screen … Make Smaller).
    private func buildSizingSection(on layoutView: SettingsLayoutView) {
        let sizingSection = layoutView.addColumnSection(label: "Sizing", itemColumnMaximumWidth: 340)
        recorders[.fillScreen] = addShortcutRow(
            section: sizingSection, mode: .maximize, title: "Fill Screen", action: .fillScreen
        )
        recorders[.almostMaximize] = addShortcutRow(
            section: sizingSection, mode: .almost, title: "Almost Maximize", action: .almostMaximize
        )
        recorders[.reasonableSize] = addShortcutRow(
            section: sizingSection, mode: .reasonable, title: "Reasonable Size", action: .reasonableSize
        )
        recorders[.makeLarger] = addShortcutRow(
            section: sizingSection, mode: .maximize, title: "Larger", action: .makeLarger
        )
        recorders[.makeSmaller] = addShortcutRow(
            section: sizingSection, mode: .makeSmaller, title: "Smaller", action: .makeSmaller
        )
        sizingSection
            .addDescriptionLabel(
                "Resizes the window under the cursor. Assign shortcuts here or use them gesture-only."
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
        for (action, recorder) in recorders {
            recorder.binding = viewModel.config.binding(for: action)
        }
    }

    @objc private func toggleTabShortcuts(_ sender: NSButton) {
        viewModel.isTabShortcutsEnabled = sender.state == .on
    }
}
