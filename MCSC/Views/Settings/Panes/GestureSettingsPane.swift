import Cocoa

/// Gestures settings pane: grouped cards with trackpad gesture mappings,
/// modifier options, SF Symbol badges, action popups, and toggle switches.
final class GestureSettingsPane: MCSCSettingsPane {
    private static let preferredPaneWidth: CGFloat = 630

    private var gesturesToggleCheckbox: NSSwitch!
    private var holdModifierCheckbox: NSSwitch!

    private struct GestureRow {
        let kind: GestureKind
        let actionPopup: NSPopUpButton
        let cmdActionPopup: NSPopUpButton
        let enableSwitch: NSSwitch
        let cmdEnableSwitch: NSSwitch
    }

    private var gestureRows: [GestureRow] = []

    override func loadView() {
        view = NSView()
        buildUI()
        sizePaneToFitContent(minimumWidth: Self.preferredPaneWidth)
        refresh()
    }

    // MARK: - UI Construction

    private func buildUI() {
        let container = NSStackView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.orientation = .vertical
        container.alignment = .width
        container.spacing = 10
        view.addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14)
        ])

        // Card 1: Gesture Recognition
        let recognitionCard = buildRecognitionCard()
        container.addArrangedSubview(recognitionCard)

        // Card 2: Pinch Gestures
        let pinchCard = buildGestureCard(
            title: "Pinch Gestures",
            subtitle: "Zoom in or out with two fingers.",
            kinds: [
                (.pinchIn, "Pinch In"),
                (.pinchOut, "Pinch Out")
            ]
        )
        container.addArrangedSubview(pinchCard)

        // Card 3: Swipe Gestures
        let swipeCard = buildGestureCard(
            title: "Swipe Gestures",
            subtitle: "Swipe with two fingers in any direction.",
            kinds: [
                (.swipeLeft, "Swipe Left"),
                (.swipeRight, "Swipe Right"),
                (.swipeDown, "Swipe Down"),
                (.swipeUp, "Swipe Up")
            ]
        )
        container.addArrangedSubview(swipeCard)

        // Card 4: Two-Finger Double Tap
        let doubleTapCard = buildGestureCard(
            title: "Two-Finger Double Tap",
            subtitle: "Double tap with two fingers.",
            kinds: [
                (.twoFingerDoubleTap, "2-Finger Double Tap")
            ]
        )
        container.addArrangedSubview(doubleTapCard)

        // Bottom Bar: Restore Defaults Button
        let bottomBar = makeBottomBar()
        container.addArrangedSubview(bottomBar)
    }

    // MARK: - Bottom Bar

    private func makeBottomBar() -> NSView {
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false

        let restoreButton = NSButton(
            title: "Restore Defaults",
            target: self,
            action: #selector(restoreDefaults(_:))
        )
        restoreButton.bezelStyle = .rounded
        restoreButton.controlSize = .regular
        restoreButton.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(restoreButton)

        NSLayoutConstraint.activate([
            restoreButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            restoreButton.topAnchor.constraint(equalTo: bar.topAnchor),
            restoreButton.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 24)
        ])

        return bar
    }

    // MARK: - Card 1: Gesture Recognition

    private func buildRecognitionCard() -> NSView {
        let card = SettingsCardView()

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])

        // Header
        let cardHeader = makeCardHeader(
            title: "Gesture Recognition",
            subtitle: "Master switch for trackpad gesture recognition and modifier options."
        )
        stack.addArrangedSubview(cardHeader)
        stack.addArrangedSubview(SettingsDivider())

        // Row 1: Enable Gestures
        let enableSwitch = NSSwitch()
        enableSwitch.controlSize = .regular
        enableSwitch.target = self
        enableSwitch.action = #selector(toggleGestures(_:))
        gesturesToggleCheckbox = enableSwitch

        let enableRow = makeToggleRow(
            title: "Enable Gestures",
            subtitle: "Master switch for all trackpad gesture recognition.",
            toggle: enableSwitch
        )
        stack.addArrangedSubview(enableRow)
        stack.addArrangedSubview(SettingsDivider())

        // Row 2: Two-Finger Hold for Command (⌘)
        let holdSwitch = NSSwitch()
        holdSwitch.controlSize = .regular
        holdSwitch.target = self
        holdSwitch.action = #selector(toggleHoldModifier(_:))
        holdModifierCheckbox = holdSwitch

        let holdRow = makeToggleRow(
            title: "Two-Finger Hold for Command (⌘)",
            subtitle: "Hold two fingers still to activate ⌘ modifier for gesture chaining.",
            toggle: holdSwitch
        )
        stack.addArrangedSubview(holdRow)

        return card
    }

    // MARK: - Cards 2, 3, 4: Gesture Cards

    private func buildGestureCard(
        title: String,
        subtitle: String,
        kinds: [(GestureKind, String)]
    ) -> NSView {
        let card = SettingsCardView()

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])

        // Header
        let cardHeader = makeCardHeader(title: title, subtitle: subtitle)
        stack.addArrangedSubview(cardHeader)
        stack.addArrangedSubview(SettingsDivider())

        // Rows
        for (index, item) in kinds.enumerated() {
            let (kind, rowTitle) = item
            let rowIndex = gestureRows.count

            let rowView = makeGestureRow(kind: kind, rowTitle: rowTitle, index: rowIndex)
            stack.addArrangedSubview(rowView)

            if index < kinds.count - 1 {
                stack.addArrangedSubview(SettingsDivider())
            }
        }

        return card
    }

    private func makeGestureRow(kind: GestureKind, rowTitle: String, index: Int) -> NSView {
        // Plain PopUpButton
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.controlSize = .regular
        popup.target = self
        popup.action = #selector(actionChanged(_:))
        popup.tag = index
        for action in kind.naturalActions {
            popup.addItem(withTitle: action.menuTitle)
            popup.lastItem?.representedObject = action.rawValue
        }

        // Plain Switch
        let plainSwitch = NSSwitch()
        plainSwitch.controlSize = .regular
        plainSwitch.target = self
        plainSwitch.action = #selector(toggleGestureEnabled(_:))
        plainSwitch.tag = index

        // Cmd PopUpButton
        let cmdPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        cmdPopup.controlSize = .regular
        cmdPopup.target = self
        cmdPopup.action = #selector(cmdActionChanged(_:))
        cmdPopup.tag = index
        for action in kind.naturalActions {
            cmdPopup.addItem(withTitle: action.menuTitle)
            cmdPopup.lastItem?.representedObject = action.rawValue
        }

        // Cmd Switch
        let cmdSwitch = NSSwitch()
        cmdSwitch.controlSize = .regular
        cmdSwitch.target = self
        cmdSwitch.action = #selector(toggleCmdGestureEnabled(_:))
        cmdSwitch.tag = index

        let rowView = makeGestureRowView(
            kind: kind,
            rowTitle: rowTitle,
            actionPopup: popup,
            enableSwitch: plainSwitch,
            cmdActionPopup: cmdPopup,
            cmdEnableSwitch: cmdSwitch
        )

        gestureRows.append(GestureRow(
            kind: kind,
            actionPopup: popup,
            cmdActionPopup: cmdPopup,
            enableSwitch: plainSwitch,
            cmdEnableSwitch: cmdSwitch
        ))

        return rowView
    }

    // MARK: - Component Builders

    private func makeCardHeader(title: String, subtitle: String) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(titleLabel)
        container.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -14),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -14),
            subtitleLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])

        return container
    }

    private func makeToggleRow(title: String, subtitle: String, toggle: NSSwitch) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        toggle.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView()
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .labelColor

        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor

        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)

        row.addSubview(toggle)
        row.addSubview(textStack)

        NSLayoutConstraint.activate([
            toggle.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            textStack.leadingAnchor.constraint(equalTo: toggle.trailingAnchor, constant: 12),
            textStack.topAnchor.constraint(equalTo: row.topAnchor, constant: 8),
            textStack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -8),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -14),

            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 40)
        ])

        return row
    }

    private func makeGestureRowView(
        kind: GestureKind,
        rowTitle: String,
        actionPopup: NSPopUpButton,
        enableSwitch: NSSwitch,
        cmdActionPopup: NSPopUpButton,
        cmdEnableSwitch: NSSwitch
    ) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let iconBadge = GestureIconBadgeView(kind: kind)

        let nameLabel = NSTextField(labelWithString: rowTitle)
        nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        nameLabel.textColor = .labelColor
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        actionPopup.translatesAutoresizingMaskIntoConstraints = false
        enableSwitch.translatesAutoresizingMaskIntoConstraints = false
        cmdActionPopup.translatesAutoresizingMaskIntoConstraints = false
        cmdEnableSwitch.translatesAutoresizingMaskIntoConstraints = false

        let vertSep = VerticalSeparator()

        let cmdLabel = NSTextField(labelWithString: "⌘")
        cmdLabel.font = .systemFont(ofSize: 14, weight: .regular)
        cmdLabel.textColor = .secondaryLabelColor
        cmdLabel.alignment = .center
        cmdLabel.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(iconBadge)
        row.addSubview(nameLabel)
        row.addSubview(actionPopup)
        row.addSubview(enableSwitch)
        row.addSubview(vertSep)
        row.addSubview(cmdLabel)
        row.addSubview(cmdActionPopup)
        row.addSubview(cmdEnableSwitch)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 38),

            iconBadge.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            iconBadge.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            nameLabel.leadingAnchor.constraint(equalTo: iconBadge.trailingAnchor, constant: 10),
            nameLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            nameLabel.widthAnchor.constraint(equalToConstant: 125),

            actionPopup.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 10),
            actionPopup.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            actionPopup.widthAnchor.constraint(equalToConstant: 135),

            enableSwitch.leadingAnchor.constraint(equalTo: actionPopup.trailingAnchor, constant: 8),
            enableSwitch.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            vertSep.leadingAnchor.constraint(equalTo: enableSwitch.trailingAnchor, constant: 12),
            vertSep.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            cmdLabel.leadingAnchor.constraint(equalTo: vertSep.trailingAnchor, constant: 12),
            cmdLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            cmdLabel.widthAnchor.constraint(equalToConstant: 14),

            cmdActionPopup.leadingAnchor.constraint(equalTo: cmdLabel.trailingAnchor, constant: 8),
            cmdActionPopup.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            cmdActionPopup.widthAnchor.constraint(equalToConstant: 135),

            cmdEnableSwitch.leadingAnchor.constraint(equalTo: cmdActionPopup.trailingAnchor, constant: 8),
            cmdEnableSwitch.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            cmdEnableSwitch.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14)
        ])

        return row
    }

    // MARK: - State Refresh

    override func refresh() {
        let gesturesEnabled = viewModel.isGesturesEnabled
        gesturesToggleCheckbox?.state = gesturesEnabled ? .on : .off

        let holdEnabled = viewModel.isTwoFingerHoldEnabled
        holdModifierCheckbox?.state = holdEnabled ? .on : .off
        holdModifierCheckbox?.isEnabled = gesturesEnabled

        for row in gestureRows {
            let plainEnabled = isGestureEnabled(row.kind, isCmd: false)
            let cmdEnabled = isGestureEnabled(row.kind, isCmd: true)

            row.enableSwitch.state = plainEnabled ? .on : .off
            row.enableSwitch.isEnabled = gesturesEnabled

            row.cmdEnableSwitch.state = cmdEnabled ? .on : .off
            row.cmdEnableSwitch.isEnabled = gesturesEnabled

            row.actionPopup.isEnabled = gesturesEnabled && plainEnabled
            row.cmdActionPopup.isEnabled = gesturesEnabled && cmdEnabled

            var plainAction = viewModel.gestureAction(for: row.kind, isCmd: false)
            var cmdAction = viewModel.gestureAction(for: row.kind, isCmd: true)

            // Reset stale bindings to factory default
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

    // MARK: - Actions & Toggles

    private func isGestureEnabled(_ kind: GestureKind, isCmd: Bool) -> Bool {
        if isCmd {
            switch kind {
            case .pinchIn: viewModel.isCmdPinchInEnabled
            case .pinchOut: viewModel.isCmdPinchOutEnabled
            case .swipeLeft: viewModel.isCmdSwipeLeftEnabled
            case .swipeRight: viewModel.isCmdSwipeRightEnabled
            case .swipeDown: viewModel.isCmdSwipeDownEnabled
            case .swipeUp: viewModel.isCmdSwipeUpEnabled
            case .twoFingerDoubleTap: viewModel.isCmdTwoFingerDoubleTapEnabled
            }
        } else {
            switch kind {
            case .pinchIn: viewModel.isPinchInEnabled
            case .pinchOut: viewModel.isPinchOutEnabled
            case .swipeLeft: viewModel.isSwipeLeftEnabled
            case .swipeRight: viewModel.isSwipeRightEnabled
            case .swipeDown: viewModel.isSwipeDownEnabled
            case .swipeUp: viewModel.isSwipeUpEnabled
            case .twoFingerDoubleTap: viewModel.isTwoFingerDoubleTapEnabled
            }
        }
    }

    private func setGestureEnabled(_ kind: GestureKind, isCmd: Bool, enabled: Bool) {
        if isCmd {
            switch kind {
            case .pinchIn: viewModel.isCmdPinchInEnabled = enabled
            case .pinchOut: viewModel.isCmdPinchOutEnabled = enabled
            case .swipeLeft: viewModel.isCmdSwipeLeftEnabled = enabled
            case .swipeRight: viewModel.isCmdSwipeRightEnabled = enabled
            case .swipeDown: viewModel.isCmdSwipeDownEnabled = enabled
            case .swipeUp: viewModel.isCmdSwipeUpEnabled = enabled
            case .twoFingerDoubleTap: viewModel.isCmdTwoFingerDoubleTapEnabled = enabled
            }
        } else {
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
    }

    @objc private func toggleGestures(_ sender: NSSwitch) {
        viewModel.isGesturesEnabled.toggle()
        sender.state = viewModel.isGesturesEnabled ? .on : .off
        refresh()
    }

    @objc private func toggleHoldModifier(_ sender: NSSwitch) {
        viewModel.isTwoFingerHoldEnabled.toggle()
        sender.state = viewModel.isTwoFingerHoldEnabled ? .on : .off
        refresh()
    }

    @objc private func toggleGestureEnabled(_ sender: NSSwitch) {
        guard let kind = GestureKind.allCases[safe: sender.tag] else { return }
        setGestureEnabled(kind, isCmd: false, enabled: sender.state == .on)
        refresh()
    }

    @objc private func toggleCmdGestureEnabled(_ sender: NSSwitch) {
        guard let kind = GestureKind.allCases[safe: sender.tag] else { return }
        setGestureEnabled(kind, isCmd: true, enabled: sender.state == .on)
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
        viewModel.isTwoFingerHoldEnabled = true
        viewModel.twoFingerHoldDuration = 0.4
        for kind in GestureKind.allCases {
            setGestureEnabled(kind, isCmd: false, enabled: true)
            setGestureEnabled(kind, isCmd: true, enabled: true)
        }
        viewModel.resetGestureMappings()
        refreshAllPanes()
    }
}

// MARK: - Supporting Views

private final class SettingsCardView: NSView {
    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        super.updateLayer()
        updateColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isDark {
            layer?.backgroundColor = NSColor(white: 0.16, alpha: 0.95).cgColor
            layer?.borderColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        } else {
            layer?.backgroundColor = NSColor(white: 0.98, alpha: 0.95).cgColor
            layer?.borderColor = NSColor(white: 0.0, alpha: 0.08).cgColor
        }
    }
}

private final class SettingsDivider: NSView {
    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 1).isActive = true
        wantsLayer = true
        updateColor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }

    private func updateColor() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = isDark
            ? NSColor(white: 1.0, alpha: 0.07).cgColor
            : NSColor(white: 0.0, alpha: 0.07).cgColor
    }
}

private final class GestureIconBadgeView: NSView {
    private let imageView = NSImageView()

    init(kind: GestureKind) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = .labelColor

        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        let primaryName = kind.symbolName
        if let img = NSImage(systemSymbolName: primaryName, accessibilityDescription: kind.displayName) {
            imageView.image = img.withSymbolConfiguration(config)
        } else {
            let fallbackName: String = switch kind {
            case .pinchIn: "arrow.down.right.and.arrow.up.left"
            case .pinchOut: "arrow.up.left.and.arrow.down.right"
            default: primaryName
            }
            imageView.image = NSImage(systemSymbolName: fallbackName, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
        }
        addSubview(imageView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 26),
            heightAnchor.constraint(equalToConstant: 26),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 14),
            imageView.heightAnchor.constraint(equalToConstant: 14)
        ])
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isDark {
            layer?.backgroundColor = NSColor(white: 0.26, alpha: 0.85).cgColor
            layer?.borderColor = NSColor(white: 1.0, alpha: 0.15).cgColor
        } else {
            layer?.backgroundColor = NSColor(white: 0.88, alpha: 0.85).cgColor
            layer?.borderColor = NSColor(white: 0.0, alpha: 0.12).cgColor
        }
    }
}

private final class VerticalSeparator: NSView {
    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 1),
            heightAnchor.constraint(equalToConstant: 18)
        ])
        updateColor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }

    private func updateColor() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = isDark
            ? NSColor(white: 1.0, alpha: 0.15).cgColor
            : NSColor(white: 0.0, alpha: 0.15).cgColor
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
