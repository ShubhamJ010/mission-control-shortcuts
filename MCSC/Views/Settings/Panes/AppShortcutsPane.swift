import Cocoa

/// App shortcuts settings pane: app-targeted actions (Quit / Hide / New
/// Window) that act on the app owning the hovered window or Dock icon. Each
/// row's recorder field shows its assigned combination; an action is active
/// exactly while a combination is assigned.
final class AppShortcutsPane: MCSCSettingsPane {
    /// Recorder fields keyed by the action they configure — `refresh()` reads
    /// state back into these.
    private var recorders: [RoutedAction: ShortcutRecorderField] = [:]

    override func loadView() {
        view = NSView()

        let layoutView = SettingsLayoutView()
        layoutView.install(in: view)

        // App — app-targeted actions (Dock)
        let appShortcuts = layoutView.addColumnSection(label: "App", itemColumnMaximumWidth: 340)
        recorders[.quit] = addShortcutRow(
            section: appShortcuts, mode: .quit, title: "Quit", action: .quit
        )
        recorders[.hide] = addShortcutRow(
            section: appShortcuts, mode: .hide, title: "Hide", action: .hide
        )
        recorders[.unminimizeAll] = addShortcutRow(
            section: appShortcuts, mode: .unminimizeAll, title: "Unminimize", action: .unminimizeAll
        )
        recorders[.newWindow] = addShortcutRow(
            section: appShortcuts, mode: .newWindow, title: "New Window", action: .newWindow
        )
        appShortcuts.addDescriptionLabel(
            "Acts on the app owning the window / Dock icon under the cursor. Click a field and press ⌘+Key to " +
                "assign or change a shortcut; Delete clears it and disables the action."
        )

        layoutView.addSeparatorSection()

        // Dock — explains window gesture & shortcut translation over Dock
        let dockSection = layoutView.addColumnSection(label: "Dock", itemColumnMaximumWidth: 340)
        dockSection.addDescriptionLabel(
            "When performed over a Dock icon, window gestures and shortcuts translate across the whole app:\n" +
                "• Close / Minimize / Full Screen / Resize: Applies to all windows of the app.\n" +
                "• Tab Actions (Close / Reopen): Targets the active tab on the app's frontmost window.\n" +
                "• New Tab / New Window: Opens a new window for the app (⌘N).\n" +
                "• Desktop Navigation: Moves the app's focused window across spaces."
        )

        layoutView.addSeparatorSection()

        layoutView.addButtonSection(title: "Restore Defaults",
                                    alignment: .trailing,
                                    widthMode: .contentBlock,
                                    target: self,
                                    action: #selector(restoreShortcutDefaults(_:)))

        sizePaneToFitContent(minimumWidth: Self.minimumPaneWidth)
        refresh()
    }

    override func refresh() {
        for (action, recorder) in recorders {
            recorder.binding = viewModel.config.binding(for: action)
        }
    }
}
