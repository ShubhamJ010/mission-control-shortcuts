import Cocoa

// MARK: - Shared shortcut-pane helpers

//
// Both shortcut panes (Windows + App) edit bindings on the same
// `ShortcutViewModel`, so the recorder-row builder and the Restore Defaults
// action live here once as an extension instead of being duplicated per pane.
// An action is active exactly while its field shows a shortcut; there are no
// checkboxes anymore.

extension MCSCSettingsPane {
    /// Adds a row with the mode's SF Symbol prefix, a bold ALL-CAPS action
    /// name, and a trailing shortcut-recorder field bound to `action` in the
    /// view model's configuration. Assigning a combination activates the
    /// action; clearing it deactivates — no separate enable toggle.
    @discardableResult
    func addShortcutRow(
        section: SettingsColumnSectionView,
        mode: CursorFeedbackOverlay.Mode,
        title: String,
        action: RoutedAction
    ) -> ShortcutRecorderField {
        let titleLabel = NSTextField(labelWithString: "")
        titleLabel.attributedStringValue = makeAttributedTitle(mode: mode, title: title)
        section.addCustomView(titleLabel)

        let recorder = ShortcutRecorderField()
        recorder.setAccessibilityLabel("\(title) shortcut")
        recorder.binding = viewModel.config.binding(for: action)
        // `[weak self]`: the field never outlives its pane, but the closure
        // must not extend the pane's lifetime either way.
        recorder.onChange = { [weak self] binding in
            self?.viewModel.config.setBinding(binding, for: action)
            self?.refreshAllPanes()
        }
        section.addAccessoryView(recorder, to: titleLabel)
        return recorder
    }

    private func makeAttributedTitle(mode: CursorFeedbackOverlay.Mode, title: String) -> NSAttributedString {
        let regularFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let boldFont = NSFontManager.shared.convert(regularFont, toHaveTrait: .boldFontMask)
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
            let yOffset = (regularFont.capHeight - imageSize.height) / 2.0
            attachment.bounds = CGRect(x: 0, y: yOffset.rounded(), width: imageSize.width, height: imageSize.height)
            attrString.append(NSAttributedString(attachment: attachment))
            attrString.append(NSAttributedString(string: "  ", attributes: [.font: regularFont]))
        }

        attrString.append(NSAttributedString(string: title.uppercased(), attributes: [
            .font: boldFont,
            .foregroundColor: NSColor.labelColor
        ]))

        return attrString
    }

    // MARK: Restore Defaults

    /// Resets every shortcut to its default binding (the actions that shipped
    /// enabled keep their combinations; everything else clears). Both shortcut
    /// panes host this button; `refreshAllPanes()` re-syncs whichever panes
    /// are visible.
    @objc func restoreShortcutDefaults(_: NSButton) {
        viewModel.config.restoreDefaults()
        refreshAllPanes()
    }
}
