import Cocoa

/// Settings pane for floating-window (PiP / always-on-top panel) handling.
///
/// Shows the master toggle plus every floating app seen so far. Each row can be
/// flipped to "Allow" when a floating window should behave like a normal
/// document window again. Overrides persist per bundle identifier through
/// `WindowComponentClassifier`.
final class WindowComponentsPane: MCSCSettingsPane {
    private var ignoreCheckbox: NSButton!
    private var rowsStack: NSStackView!
    /// Bundle ids parallel to the rows currently installed in `rowsStack`,
    /// used to resolve the sender of a row checkbox.
    private var rowBundleIDs: [String] = []

    private var classifier: WindowComponentClassifier {
        viewModel.windowComponentClassifier
    }

    override func loadView() {
        view = NSView()

        let layoutView = SettingsLayoutView()
        layoutView.install(in: view)

        let behavior = layoutView.addColumnSection(label: "Floating Windows", itemColumnMaximumWidth: 380)
        ignoreCheckbox = behavior.addDescribedCheckbox(
            title: "Ignore PiP and Floating Windows",
            description: "Picture-in-picture video and always-on-top panels have no title bar, "
                + "so gestures and Command shortcuts skip them. Turn this off to treat them like normal windows.",
            target: self,
            action: #selector(toggleIgnore(_:))
        )

        layoutView.addSeparatorSection()

        let detected = layoutView.addColumnSection(label: "Detected", itemColumnMaximumWidth: 380)
        rowsStack = NSStackView()
        rowsStack.orientation = .vertical
        rowsStack.alignment = .width
        rowsStack.spacing = 6
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        detected.addCustomView(rowsStack)

        layoutView.addSeparatorSection()

        layoutView.addButtonSection(
            title: "Reset Overrides",
            alignment: .trailing,
            widthMode: .contentBlock,
            target: self,
            action: #selector(resetOverrides(_:))
        )

        sizePaneToFitContent(minimumWidth: Self.minimumPaneWidth)
        refresh()
    }

    override func refresh() {
        // `SettingsWindowController.show()` refreshes every pane before the
        // lazy view is loaded; outlets are nil until then.
        guard isViewLoaded else { return }
        ignoreCheckbox.state = classifier.isEnabled ? .on : .off
        rebuildRows()
    }

    // MARK: - Rows

    private func rebuildRows() {
        rowsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        rowBundleIDs = classifier.detectedComponents.map(\.bundleID)

        guard !classifier.detectedComponents.isEmpty else {
            rowsStack.addArrangedSubview(Self.makeLabel(
                "No floating windows seen yet. Open a video picture-in-picture window to test."
            ))
            return
        }

        for component in classifier.detectedComponents {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8

            let label = Self.makeLabel(
                "\(component.appName) · \(component.kind.rawValue) · layer \(component.layer)"
            )
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let allow = NSButton(checkboxWithTitle: "Allow", target: self, action: #selector(toggleAllow(_:)))
            allow.tag = rowBundleIDs.firstIndex(of: component.bundleID) ?? 0
            allow.state = classifier.userOverrides[component.bundleID] == .allow ? .on : .off

            row.addArrangedSubview(label)
            row.addArrangedSubview(allow)
            rowsStack.addArrangedSubview(row)
        }
    }

    private static func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.lineBreakMode = .byTruncatingTail
        label.textColor = .labelColor
        return label
    }

    // MARK: - Actions

    @objc private func toggleIgnore(_ sender: NSButton) {
        classifier.isEnabled = sender.state == .on
        refresh()
    }

    @objc private func toggleAllow(_ sender: NSButton) {
        guard rowBundleIDs.indices.contains(sender.tag) else { return }
        let bundleID = rowBundleIDs[sender.tag]
        classifier.setBehavior(sender.state == .on ? .allow : .ignore, forBundleID: bundleID)
        refresh()
    }

    @objc private func resetOverrides(_: Any?) {
        classifier.resetOverrides()
        refresh()
    }
}
