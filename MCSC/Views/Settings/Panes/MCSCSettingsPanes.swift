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
