import Cocoa

/// macOS-style keyboard shortcut recorder, modeled on the System Settings
/// "Keyboard Shortcut" field: click to arm, press ⌘(+⇧)+key to assign,
/// Delete or the trailing ✕ clears the binding, Escape cancels. An assigned
/// combination renders with per-glyph gaps ("⌘ W" / "⇧ ⌘ S") and a ✕ button
/// appears after the field to remove the assignment.
///
/// An action is active exactly while its field shows a shortcut — there is no
/// separate checkbox. Pure AppKit (a container hosting two buttons), no timers
/// on the hot path, so it respects the project's memory-first mandate.
final class ShortcutRecorderField: NSView {
    /// Called whenever the user assigns or clears a combination.
    var onChange: ((ShortcutBinding?) -> Void)?

    /// The assigned combination; `nil` renders the placeholder state and
    /// hides the clear button.
    var binding: ShortcutBinding? {
        didSet {
            guard binding != oldValue else { return }
            updateDisplay()
            onChange?(binding)
        }
    }

    private var isRecording = false
    /// Token invalidating a stale transient hint (e.g. "Use ⌘+Key") if the
    /// field state changes before the restore fires.
    private var hintRestoreToken = UUID()

    private let recordButton = RecordButton()
    private let clearButton = NSButton()
    /// Full-width trailing pin, active only while the ✕ button is hidden.
    private var recordTrailingConstraint: NSLayoutConstraint!
    private var clearTrailingConstraint: NSLayoutConstraint!
    private var recordToClearConstraint: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        configureRecordButton()
        configureClearButton()
        installConstraints()
        // `[weak self]`: buttons never outlive their container, but the
        // closures must not extend its lifetime either way.
        recordButton.onArm = { [weak self] in
            guard let self else { return }
            isRecording = true
            updateDisplay()
        }
        recordButton.onResign = { [weak self] in
            guard let self else { return }
            isRecording = false
            updateDisplay()
        }
        recordButton.onKeyEvent = { [weak self] event in
            self?.handleKeyEvent(event)
        }
        updateDisplay()
    }

    private func configureRecordButton() {
        recordButton.setButtonType(.momentaryPushIn)
        recordButton.bezelStyle = .rounded
        recordButton.isBordered = true
        recordButton.focusRingType = .default
        // The glyph string must never truncate or squeeze out of view.
        recordButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        recordButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        recordButton.toolTip = "Click, then press a key combination with ⌘. Press Delete or the ✕ button to clear. Esc cancels."
    }

    private func configureClearButton() {
        clearButton.setButtonType(.momentaryPushIn)
        clearButton.bezelStyle = .rounded
        clearButton.controlSize = .small
        clearButton.image = NSImage(systemSymbolName: "xmark",
                                    accessibilityDescription: "Clear shortcut")
        clearButton.imagePosition = .imageOnly
        clearButton.setAccessibilityLabel("Clear shortcut")
        clearButton.toolTip = "Remove shortcut"
        clearButton.target = self
        clearButton.action = #selector(clearBinding(_:))
        clearButton.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func installConstraints() {
        for button in [recordButton, clearButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
            addSubview(button)
        }
        NSLayoutConstraint.activate([
            recordButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            recordButton.topAnchor.constraint(equalTo: topAnchor),
            recordButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        recordTrailingConstraint = recordButton.trailingAnchor.constraint(equalTo: trailingAnchor)
        clearTrailingConstraint = clearButton.trailingAnchor.constraint(equalTo: trailingAnchor)
        recordToClearConstraint = clearButton.leadingAnchor.constraint(
            equalTo: recordButton.trailingAnchor, constant: Self.clearSpacing
        )
    }

    // MARK: - Recording session

    private func handleKeyEvent(_ event: NSEvent) {
        let keyCode = Int64(event.keyCode)
        switch keyCode {
        case Self.escapeKeyCode:
            endRecording()
        case Self.deleteKeyCode, Self.forwardDeleteKeyCode:
            binding = nil
            endRecording()
        default:
            assign(from: event, keyCode: keyCode)
        }
    }

    private func assign(from event: NSEvent, keyCode: Int64) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Bare modifier presses carry no routable key.
        guard !Self.modifierKeyCodes.contains(keyCode) else { return }
        // MCSC shortcuts never use Control or Option (router contract).
        guard !modifiers.contains(.control), !modifiers.contains(.option) else {
            flashTransientHint("No ⌃/⌥")
            return
        }
        guard modifiers.contains(.command) else {
            flashTransientHint("Use ⌘+Key")
            return
        }
        binding = ShortcutBinding(keyCode: keyCode, includesShift: modifiers.contains(.shift))
        endRecording()
    }

    private func endRecording() {
        recordButton.window?.makeFirstResponder(nil)
        isRecording = false
        updateDisplay()
    }

    /// Removes the assignment, deactivating the action — the keyboard
    /// equivalent of pressing Delete while recording.
    @objc private func clearBinding(_: NSButton) {
        recordButton.window?.makeFirstResponder(nil)
        binding = nil
    }

    // MARK: - Display states

    private func updateDisplay() {
        cancelPendingHint()
        let assigned = binding != nil
        // Swap the trailing pin: field stretches full-width when unassigned,
        // makes room for the ✕ button once a combination is set.
        recordTrailingConstraint.isActive = !assigned
        clearTrailingConstraint.isActive = assigned
        recordToClearConstraint.isActive = assigned
        clearButton.isHidden = !assigned
        recordButton.attributedTitle = isRecording ? recordingTitle : idleTitle
        recordButton.needsDisplay = true
    }

    private var idleTitle: NSAttributedString {
        if let binding {
            return NSAttributedString(string: binding.displayString, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ])
        }
        return NSAttributedString(string: "Record Shortcut", attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
    }

    private var recordingTitle: NSAttributedString {
        let text = binding?.displayString ?? "Type Shortcut"
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ])
    }

    /// Briefly shows guidance for an ignored keystroke, then restores the
    /// previous display. One-shot async hop — never a repeating timer.
    private func flashTransientHint(_ hint: String) {
        cancelPendingHint()
        let token = UUID()
        hintRestoreToken = token
        recordButton.attributedTitle = NSAttributedString(string: hint, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.systemOrange
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, self.hintRestoreToken == token else { return }
            updateDisplay()
        }
    }

    private func cancelPendingHint() {
        hintRestoreToken = UUID()
    }

    // MARK: - Constants

    private static let clearSpacing: CGFloat = 6
    private static let escapeKeyCode: Int64 = 53
    private static let deleteKeyCode: Int64 = 51
    private static let forwardDeleteKeyCode: Int64 = 117
    /// Modifier-only presses that must not be recorded as bindings.
    private static let modifierKeyCodes: Set<Int64> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
}

/// The rounded recorder surface: arms on focus, forwards every keystroke to
/// the container, and never fires a target/action of its own.
private final class RecordButton: NSButton {
    var onArm: (() -> Void)?
    var onResign: (() -> Void)?
    var onKeyEvent: ((NSEvent) -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            onArm?()
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        onResign?()
        return super.resignFirstResponder()
    }

    override func mouseDown(with _: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        onKeyEvent?(event)
    }
}
