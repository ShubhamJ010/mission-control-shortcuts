import Foundation

/// Value type representing user-configurable shortcut and gesture toggles.
struct ShortcutConfiguration {
    var isCmdWEnabled = true {
        didSet { UserDefaults.standard.set(isCmdWEnabled, forKey: Self.Keys.cmdWEnabled) }
    }

    var isCmdQEnabled = true {
        didSet { UserDefaults.standard.set(isCmdQEnabled, forKey: Self.Keys.cmdQEnabled) }
    }

    var isCmdMEnabled = true {
        didSet { UserDefaults.standard.set(isCmdMEnabled, forKey: Self.Keys.cmdMEnabled) }
    }

    var isCmdHEnabled = true {
        didSet { UserDefaults.standard.set(isCmdHEnabled, forKey: Self.Keys.cmdHEnabled) }
    }

    var isCmdFEnabled = false {
        didSet { UserDefaults.standard.set(isCmdFEnabled, forKey: Self.Keys.cmdFEnabled) }
    }

    var isCmdSpaceEnabled = true {
        didSet { UserDefaults.standard.set(isCmdSpaceEnabled, forKey: Self.Keys.cmdSpaceEnabled) }
    }

    var isCmdTEnabled = false {
        didSet { UserDefaults.standard.set(isCmdTEnabled, forKey: Self.Keys.cmdTEnabled) }
    }

    var isCmdNEnabled = false {
        didSet { UserDefaults.standard.set(isCmdNEnabled, forKey: Self.Keys.cmdNEnabled) }
    }

    var isCmdShiftWEnabled = false {
        didSet { UserDefaults.standard.set(isCmdShiftWEnabled, forKey: Self.Keys.cmdShiftWEnabled) }
    }

    var isCmdShiftTEnabled = false {
        didSet { UserDefaults.standard.set(isCmdShiftTEnabled, forKey: Self.Keys.cmdShiftTEnabled) }
    }

    /// Window & Tab — additional window/size/desktop shortcuts (off by default, gesture-only previously)
    var isCloseWindowEnabled = false {
        didSet { UserDefaults.standard.set(isCloseWindowEnabled, forKey: Self.Keys.closeWindowEnabled) }
    }

    var isFillScreenEnabled = false {
        didSet { UserDefaults.standard.set(isFillScreenEnabled, forKey: Self.Keys.fillScreenEnabled) }
    }

    var isAlmostMaximizeEnabled = false {
        didSet { UserDefaults.standard.set(isAlmostMaximizeEnabled, forKey: Self.Keys.almostMaximizeEnabled) }
    }

    var isReasonableSizeEnabled = false {
        didSet { UserDefaults.standard.set(isReasonableSizeEnabled, forKey: Self.Keys.reasonableSizeEnabled) }
    }

    var isMakeLargerEnabled = false {
        didSet { UserDefaults.standard.set(isMakeLargerEnabled, forKey: Self.Keys.makeLargerEnabled) }
    }

    var isMakeSmallerEnabled = false {
        didSet { UserDefaults.standard.set(isMakeSmallerEnabled, forKey: Self.Keys.makeSmallerEnabled) }
    }

    var isMoveNextDesktopEnabled = false {
        didSet { UserDefaults.standard.set(isMoveNextDesktopEnabled, forKey: Self.Keys.moveNextDesktopEnabled) }
    }

    var isMovePreviousDesktopEnabled = false {
        didSet { UserDefaults.standard.set(isMovePreviousDesktopEnabled, forKey: Self.Keys.movePreviousDesktopEnabled) }
    }

    var isGesturesEnabled = true {
        didSet { UserDefaults.standard.set(isGesturesEnabled, forKey: Self.Keys.gesturesEnabled) }
    }

    var isPinchInEnabled = true {
        didSet { UserDefaults.standard.set(isPinchInEnabled, forKey: Self.Keys.pinchInEnabled) }
    }

    var isPinchOutEnabled = true {
        didSet { UserDefaults.standard.set(isPinchOutEnabled, forKey: Self.Keys.pinchOutEnabled) }
    }

    var isSwipeLeftEnabled = true {
        didSet { UserDefaults.standard.set(isSwipeLeftEnabled, forKey: Self.Keys.swipeLeftEnabled) }
    }

    var isSwipeRightEnabled = true {
        didSet { UserDefaults.standard.set(isSwipeRightEnabled, forKey: Self.Keys.swipeRightEnabled) }
    }

    var isSwipeDownEnabled = true {
        didSet { UserDefaults.standard.set(isSwipeDownEnabled, forKey: Self.Keys.swipeDownEnabled) }
    }

    var isSwipeUpEnabled = true {
        didSet { UserDefaults.standard.set(isSwipeUpEnabled, forKey: Self.Keys.swipeUpEnabled) }
    }

    var isTwoFingerDoubleTapEnabled = true {
        didSet { UserDefaults.standard.set(isTwoFingerDoubleTapEnabled, forKey: Self.Keys.twoFingerDoubleTapEnabled) }
    }

    var isAutoEjectEnabled = true {
        didSet { UserDefaults.standard.set(isAutoEjectEnabled, forKey: Self.Keys.autoEjectEnabled) }
    }

    /// When `true`, dock-targeted shortcuts and gestures also work while
    /// hovering Dock icons in normal desktop mode (Mission Control closed).
    /// Persisted to `UserDefaults` on every mutation.
    var isDockActionsOutsideMCEnabled = false {
        didSet { UserDefaults.standard.set(isDockActionsOutsideMCEnabled, forKey: Self.Keys.dockActionsOutsideMC) }
    }

    /// When `true`, shortcuts and gestures also work while hovering the title
    /// bar of the frontmost window in normal desktop mode (Mission Control
    /// closed). Persisted to `UserDefaults` on every mutation.
    var isTitleBarActionsOutsideMCEnabled = false {
        didSet {
            UserDefaults.standard.set(isTitleBarActionsOutsideMCEnabled, forKey: Self.Keys.titleBarActionsOutsideMC)
        }
    }

    var isKeyboardNavigationEnabled = true {
        didSet { UserDefaults.standard.set(isKeyboardNavigationEnabled, forKey: Self.Keys.keyboardNavigation) }
    }

    // MARK: - General / Feedback — on by default (restores previous always-on behavior, now configurable).

    /// Haptic pulses for shortcuts/gestures. Previously always-on; now configurable.
    var isHapticFeedbackEnabled = true {
        didSet { UserDefaults.standard.set(isHapticFeedbackEnabled, forKey: Self.Keys.hapticFeedbackEnabled) }
    }

    /// Visual cursor flash overlay on actions. Previously always-on; now configurable.
    var isCursorFeedbackEnabled = true {
        didSet { UserDefaults.standard.set(isCursorFeedbackEnabled, forKey: Self.Keys.cursorFeedbackEnabled) }
    }

    /// When true, uses zero-overhead CoreAnimation effects. When false, uses native Apple SF Symbol Effects.
    var isOptimizedAnimationModeEnabled = true {
        didSet { UserDefaults.standard.set(isOptimizedAnimationModeEnabled, forKey: Self.Keys.optimizedAnimationsEnabled) }
    }

    // MARK: - Gesture action mappings

    /// Plain gesture → action mapping.
    var gestureActions: [GestureKind: GestureAction] = GestureDefaults.plainDefaults {
        didSet { persistGestureActions() }
    }

    /// ⌘-modified gesture → action mapping.
    var cmdGestureActions: [GestureKind: GestureAction] = GestureDefaults.cmdDefaults {
        didSet { persistCmdGestureActions() }
    }

    init() {
        loadStoredToggles()
        loadStoredGestureMappings()
    }

    /// Single source of truth for every persisted toggle: its `UserDefaults`
    /// key and default value. Drives loading (`init`), `restoreDefaults()`,
    /// and the defaults-drift unit tests. The stored-property literals above
    /// must match `defaultValue` (enforced by `ShortcutConfigurationTests`).
    static let toggleDefaults: [(
        keyPath: WritableKeyPath<ShortcutConfiguration, Bool>,
        key: String,
        defaultValue: Bool
    )] = [
        (\.isCmdWEnabled, Keys.cmdWEnabled, true),
        (\.isCmdQEnabled, Keys.cmdQEnabled, true),
        (\.isCmdMEnabled, Keys.cmdMEnabled, true),
        (\.isCmdHEnabled, Keys.cmdHEnabled, true),
        (\.isCmdFEnabled, Keys.cmdFEnabled, false),
        (\.isCmdSpaceEnabled, Keys.cmdSpaceEnabled, true),
        (\.isCmdTEnabled, Keys.cmdTEnabled, false),
        (\.isCmdNEnabled, Keys.cmdNEnabled, false),
        (\.isCmdShiftWEnabled, Keys.cmdShiftWEnabled, false),
        (\.isCmdShiftTEnabled, Keys.cmdShiftTEnabled, false),
        (\.isCloseWindowEnabled, Keys.closeWindowEnabled, false),
        (\.isFillScreenEnabled, Keys.fillScreenEnabled, false),
        (\.isAlmostMaximizeEnabled, Keys.almostMaximizeEnabled, false),
        (\.isReasonableSizeEnabled, Keys.reasonableSizeEnabled, false),
        (\.isMakeLargerEnabled, Keys.makeLargerEnabled, false),
        (\.isMakeSmallerEnabled, Keys.makeSmallerEnabled, false),
        (\.isMoveNextDesktopEnabled, Keys.moveNextDesktopEnabled, false),
        (\.isMovePreviousDesktopEnabled, Keys.movePreviousDesktopEnabled, false),
        (\.isKeyboardNavigationEnabled, Keys.keyboardNavigation, true),
        (\.isDockActionsOutsideMCEnabled, Keys.dockActionsOutsideMC, false),
        (\.isTitleBarActionsOutsideMCEnabled, Keys.titleBarActionsOutsideMC, false),
        (\.isGesturesEnabled, Keys.gesturesEnabled, true),
        (\.isPinchInEnabled, Keys.pinchInEnabled, true),
        (\.isPinchOutEnabled, Keys.pinchOutEnabled, true),
        (\.isSwipeLeftEnabled, Keys.swipeLeftEnabled, true),
        (\.isSwipeRightEnabled, Keys.swipeRightEnabled, true),
        (\.isSwipeDownEnabled, Keys.swipeDownEnabled, true),
        (\.isSwipeUpEnabled, Keys.swipeUpEnabled, true),
        (\.isTwoFingerDoubleTapEnabled, Keys.twoFingerDoubleTapEnabled, true),
        (\.isAutoEjectEnabled, Keys.autoEjectEnabled, true),
        (\.isHapticFeedbackEnabled, Keys.hapticFeedbackEnabled, true),
        (\.isCursorFeedbackEnabled, Keys.cursorFeedbackEnabled, true),
        (\.isOptimizedAnimationModeEnabled, Keys.optimizedAnimationsEnabled, true),
    ]

    private mutating func loadStoredToggles() {
        for entry in Self.toggleDefaults {
            if let value = Self.loadBool(forKey: entry.key) {
                self[keyPath: entry.keyPath] = value
            }
        }
    }

    private mutating func loadStoredGestureMappings() {
        if let dict = UserDefaults.standard.dictionary(forKey: Self.Keys.gestureActions) as? [String: String] {
            for (key, value) in dict {
                if let kind = GestureKind(rawValue: key), let action = GestureAction(rawValue: value) {
                    gestureActions[kind] = action
                }
            }
        }
        if let dict = UserDefaults.standard.dictionary(forKey: Self.Keys.cmdGestureActions) as? [String: String] {
            for (key, value) in dict {
                if let kind = GestureKind(rawValue: key), let action = GestureAction(rawValue: value) {
                    cmdGestureActions[kind] = action
                }
            }
        }
    }

    /// Lookup respecting ⌘ modifier.
    func action(for kind: GestureKind, isCmd: Bool) -> GestureAction {
        if isCmd {
            return cmdGestureActions[kind] ?? GestureDefaults.action(for: kind, isCmd: true)
        }
        return gestureActions[kind] ?? GestureDefaults.action(for: kind, isCmd: false)
    }

    mutating func setAction(_ action: GestureAction, for kind: GestureKind, isCmd: Bool) {
        if isCmd {
            cmdGestureActions[kind] = action
        } else {
            gestureActions[kind] = action
        }
    }

    mutating func resetGestureMappings() {
        gestureActions = GestureDefaults.plainDefaults
        cmdGestureActions = GestureDefaults.cmdDefaults
    }

    /// Resets all toggles to defaults (single source of truth for Restore Defaults).
    mutating func restoreDefaults() {
        for entry in Self.toggleDefaults {
            self[keyPath: entry.keyPath] = entry.defaultValue
        }
        resetGestureMappings()
    }

    // MARK: - Helpers

    private static func loadBool(forKey key: String) -> Bool? {
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        return UserDefaults.standard.bool(forKey: key)
    }

    private func persistGestureActions() {
        let dict = Dictionary(uniqueKeysWithValues: gestureActions.map { ($0.key.rawValue, $0.value.rawValue) })
        UserDefaults.standard.set(dict, forKey: Self.Keys.gestureActions)
    }

    private func persistCmdGestureActions() {
        let dict = Dictionary(uniqueKeysWithValues: cmdGestureActions.map { ($0.key.rawValue, $0.value.rawValue) })
        UserDefaults.standard.set(dict, forKey: Self.Keys.cmdGestureActions)
    }

    private enum Keys {
        static let cmdWEnabled = "mcsc.shortcuts.cmdW.enabled"
        static let cmdQEnabled = "mcsc.shortcuts.cmdQ.enabled"
        static let cmdMEnabled = "mcsc.shortcuts.cmdM.enabled"
        static let cmdHEnabled = "mcsc.shortcuts.cmdH.enabled"
        static let cmdFEnabled = "mcsc.shortcuts.cmdF.enabled"
        static let cmdSpaceEnabled = "mcsc.shortcuts.cmdSpace.enabled"
        static let cmdTEnabled = "mcsc.shortcuts.cmdT.enabled"
        static let cmdNEnabled = "mcsc.shortcuts.cmdN.enabled"
        static let cmdShiftWEnabled = "mcsc.shortcuts.cmdShiftW.enabled"
        static let cmdShiftTEnabled = "mcsc.shortcuts.cmdShiftT.enabled"
        static let closeWindowEnabled = "mcsc.shortcuts.closeWindow.enabled"
        static let fillScreenEnabled = "mcsc.shortcuts.fillScreen.enabled"
        static let almostMaximizeEnabled = "mcsc.shortcuts.almostMaximize.enabled"
        static let reasonableSizeEnabled = "mcsc.shortcuts.reasonableSize.enabled"
        static let makeLargerEnabled = "mcsc.shortcuts.makeLarger.enabled"
        static let makeSmallerEnabled = "mcsc.shortcuts.makeSmaller.enabled"
        static let moveNextDesktopEnabled = "mcsc.shortcuts.moveNextDesktop.enabled"
        static let movePreviousDesktopEnabled = "mcsc.shortcuts.movePreviousDesktop.enabled"
        static let keyboardNavigation = "mcsc.keyboardNavigation.enabled"
        static let dockActionsOutsideMC = "mcsc.dockActionsOutsideMC.enabled"
        static let titleBarActionsOutsideMC = "mcsc.titleBarActionsOutsideMC.enabled"
        static let gesturesEnabled = "mcsc.gestures.enabled"
        static let pinchInEnabled = "mcsc.gestures.pinchIn.enabled"
        static let pinchOutEnabled = "mcsc.gestures.pinchOut.enabled"
        static let swipeLeftEnabled = "mcsc.gestures.swipeLeft.enabled"
        static let swipeRightEnabled = "mcsc.gestures.swipeRight.enabled"
        static let swipeDownEnabled = "mcsc.gestures.swipeDown.enabled"
        static let swipeUpEnabled = "mcsc.gestures.swipeUp.enabled"
        static let twoFingerDoubleTapEnabled = "mcsc.gestures.twoFingerDoubleTap.enabled"
        static let autoEjectEnabled = "mcsc.autoEject.enabled"
        static let hapticFeedbackEnabled = "mcsc.feedback.haptics.enabled"
        static let cursorFeedbackEnabled = "mcsc.feedback.cursor.enabled"
        static let optimizedAnimationsEnabled = "mcsc.feedback.optimizedAnimations.enabled"
        static let gestureActions = "mcsc.gestures.actions"
        static let cmdGestureActions = "mcsc.gestures.cmdActions"
    }
}
