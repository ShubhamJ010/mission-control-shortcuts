import Cocoa

/// Gestures settings pane: master enable toggle plus one row per
/// gesture kind with plain / Cmd action pickers.
final class GestureSettingsPane: MCSCSettingsPane {
    /// Demo General pane caps the item column — keeps pop-ups from stretching edge-to-edge.
    private static let itemColumnMaximumWidth: CGFloat = 250

    private var layoutView: SettingsLayoutView?
    private var gesturesToggleCheckbox: NSButton!
    private var holdModifierCheckbox: NSButton?

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

        // Master toggle
        let toggleSection = layoutView.addCheckboxSection(
            title: "Enable Gestures",
            description: "Master switch for all trackpad gesture recognition.",
            identifier: .init("Master"),
            target: self,
            action: #selector(toggleGestures(_:))
        )
        gesturesToggleCheckbox = toggleSection.checkbox

        // Two-Finger Hold modifier toggle
        let holdSection = layoutView.addCheckboxSection(
            title: "Two-Finger Hold for Command (⌘)",
            description: "Hold two fingers still to activate ⌘ modifier for gesture chaining.",
            identifier: .init("HoldModifier"),
            target: self,
            action: #selector(toggleHoldModifier(_:))
        )
        holdModifierCheckbox = holdSection.checkbox

        layoutView.addSeparatorSection(identifier: .init("Sep.Master"))

        // One column section per gesture — label in the label column, popup + checkbox accessory in the item column,
        // Cmd variant as a second stacked item. Pinch / Swipe / Tap groups with separators mirror the demo's
        // section grouping and break up the 7-row wall (Guide/#sections).
        let ordered: [GestureKind] = [
            .pinchIn, .pinchOut,
            .swipeLeft, .swipeRight, .swipeDown, .swipeUp,
            .twoFingerDoubleTap
        ]
        for (index, kind) in ordered.enumerated() {
            switch kind {
            case .swipeLeft:
                layoutView.addSeparatorSection(identifier: .init("Sep.Pinch"))
            case .twoFingerDoubleTap:
                layoutView.addSeparatorSection(identifier: .init("Sep.Swipe"))
            default:
                break
            }
            makeGestureRow(for: kind, index: index, on: layoutView)
        }

        layoutView.addSeparatorSection(identifier: .init("Sep.Restore"))

        layoutView.addButtonSection(title: "Restore Defaults",
                                     controlSize: .regular,
                                     alignment: .trailing,
                                     widthMode: .contentBlock,
                                     identifier: .init("RestoreDefaults"),
                                     target: self,
                                     action: #selector(restoreDefaults(_:)))
    }

    /// Builds one gesture row: primary-action popup + enable switch accessory,
    /// then the Cmd-variant popup stacked underneath.
    private func makeGestureRow(for kind: GestureKind, index: Int, on layoutView: SettingsLayoutView) {
        let isFirst = (index == 0)
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
        popup.tag = index

        // Toggle switch
        let toggle = NSSwitch()
        toggle.target = self
        toggle.action = #selector(toggleGestureEnabled(_:))
        toggle.controlSize = .regular
        toggle.tag = index
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
        cmdPopup.tag = index
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
    }

    override func refresh() {
        gesturesToggleCheckbox?.state = viewModel.isGesturesEnabled ? .on : .off

        let gesturesEnabled = viewModel.isGesturesEnabled
        holdModifierCheckbox?.state = viewModel.isTwoFingerHoldEnabled ? .on : .off
        holdModifierCheckbox?.isEnabled = gesturesEnabled

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
            let rowEnabled = gesturesEnabled && kindEnabled
            row.enableSwitch.state = kindEnabled ? .on : .off
            row.enableSwitch.isEnabled = gesturesEnabled
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

    @objc private func toggleHoldModifier(_ sender: NSButton) {
        viewModel.isTwoFingerHoldEnabled.toggle()
        sender.state = viewModel.isTwoFingerHoldEnabled ? .on : .off
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
        viewModel.isTwoFingerHoldEnabled = true
        viewModel.twoFingerHoldDuration = 0.4
        viewModel.resetGestureMappings()
        refreshAllPanes()
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
