import Foundation

/// Value type representing user-configurable shortcut and gesture toggles.
struct ShortcutConfiguration {
    // MARK: - Rebindable shortcut bindings

    /// Action → key combination. An action is *active* exactly when it has a
    /// binding; removing the binding disables it. Persisted on every mutation.
    var shortcutBindings: [RoutedAction: ShortcutBinding] = RoutedAction.defaultBindings {
        didSet { persistShortcutBindings() }
    }

    /// `UserDefaults` key holding the JSON-encoded binding map. Exposed so
    /// test suites can reset persisted state between runs.
    static let bindingsStorageKey = "mcsc.shortcuts.bindings"

    // MARK: Legacy boolean toggle API

    //
    // The settings UI now assigns shortcuts through recorder fields, so these
    // used-to-be-stored booleans became views over the binding store: true ⇔
    // the action's canonical default combination is currently assigned.

    /// Close window / tab strip (⌘W flow).
    var isClosingEnabled: Bool {
        get { shortcutBindings[.close] != nil }
        set { setBinding(newValue ? RoutedAction.close.canonicalBinding : nil, for: .close) }
    }

    var isCmdWEnabled: Bool {
        get { shortcutBindings[.closeTab] != nil }
        set { setBinding(newValue ? RoutedAction.closeTab.canonicalBinding : nil, for: .closeTab) }
    }

    var isCmdQEnabled: Bool {
        get { shortcutBindings[.quit] != nil }
        set { shortcutBindings[.quit] = newValue ? RoutedAction.quit.canonicalBinding : nil }
    }

    var isCmdMEnabled: Bool {
        get { shortcutBindings[.minimize] != nil }
        set { shortcutBindings[.minimize] = newValue ? RoutedAction.minimize.canonicalBinding : nil }
    }

    var isCmdHEnabled: Bool {
        get { shortcutBindings[.hide] != nil }
        set { shortcutBindings[.hide] = newValue ? RoutedAction.hide.canonicalBinding : nil }
    }

    var isCmdFEnabled: Bool {
        get { shortcutBindings[.fullscreen] != nil }
        set { shortcutBindings[.fullscreen] = newValue ? RoutedAction.fullscreen.canonicalBinding : nil }
    }

    var isCmdSpaceEnabled = true {
        didSet { UserDefaults.standard.set(isCmdSpaceEnabled, forKey: Self.Keys.cmdSpaceEnabled) }
    }

    var isCmdTEnabled: Bool {
        get { shortcutBindings[.newTab] != nil }
        set { shortcutBindings[.newTab] = newValue ? RoutedAction.newTab.canonicalBinding : nil }
    }

    var isCmdNEnabled: Bool {
        get { shortcutBindings[.newWindow] != nil }
        set { shortcutBindings[.newWindow] = newValue ? RoutedAction.newWindow.canonicalBinding : nil }
    }

    var isCmdShiftWEnabled: Bool {
        get { shortcutBindings[.closeAllTabs] != nil }
        set { shortcutBindings[.closeAllTabs] = newValue ? RoutedAction.closeAllTabs.canonicalBinding : nil }
    }

    var isCmdShiftTEnabled: Bool {
        get { shortcutBindings[.reopenTab] != nil }
        set { shortcutBindings[.reopenTab] = newValue ? RoutedAction.reopenTab.canonicalBinding : nil }
    }

    var isFillScreenEnabled: Bool {
        get { shortcutBindings[.fillScreen] != nil }
        set { shortcutBindings[.fillScreen] = newValue ? RoutedAction.fillScreen.canonicalBinding : nil }
    }

    var isAlmostMaximizeEnabled: Bool {
        get { shortcutBindings[.almostMaximize] != nil }
        set { shortcutBindings[.almostMaximize] = newValue ? RoutedAction.almostMaximize.canonicalBinding : nil }
    }

    var isReasonableSizeEnabled: Bool {
        get { shortcutBindings[.reasonableSize] != nil }
        set { shortcutBindings[.reasonableSize] = newValue ? RoutedAction.reasonableSize.canonicalBinding : nil }
    }

    var isMakeLargerEnabled: Bool {
        get { shortcutBindings[.makeLarger] != nil }
        set { shortcutBindings[.makeLarger] = newValue ? RoutedAction.makeLarger.canonicalBinding : nil }
    }

    var isMakeSmallerEnabled: Bool {
        get { shortcutBindings[.makeSmaller] != nil }
        set { shortcutBindings[.makeSmaller] = newValue ? RoutedAction.makeSmaller.canonicalBinding : nil }
    }

    var isMoveNextDesktopEnabled: Bool {
        get { shortcutBindings[.moveNextDesktop] != nil }
        set { shortcutBindings[.moveNextDesktop] = newValue ? RoutedAction.moveNextDesktop.canonicalBinding : nil }
    }

    var isMovePreviousDesktopEnabled: Bool {
        get { shortcutBindings[.movePreviousDesktop] != nil }
        set {
            shortcutBindings[.movePreviousDesktop] = newValue ? RoutedAction.movePreviousDesktop.canonicalBinding : nil
        }
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
        didSet {
            UserDefaults.standard.set(isOptimizedAnimationModeEnabled, forKey: Self.Keys.optimizedAnimationsEnabled)
        }
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
        loadStoredBindings()
        loadStoredGestureMappings()
    }

    /// Single source of truth for every persisted toggle: its `UserDefaults`
    /// key and default value. Drives loading (`init`), `restoreDefaults()`,
    /// and the defaults-drift unit tests. The stored-property literals above
    /// must match `defaultValue` (enforced by `ShortcutConfigurationTests`).
    ///
    /// Shortcut on/off toggles are no longer here — they became the persisted
    /// binding map (`Keys.shortcutBindings`). Only fixed-behavior toggles
    /// (⌘Space, gestures, feedback, …) remain plain booleans.
    static let toggleDefaults: [(
        keyPath: WritableKeyPath<ShortcutConfiguration, Bool>,
        key: String,
        defaultValue: Bool
    )] = [
        (\.isCmdSpaceEnabled, Keys.cmdSpaceEnabled, true),

        (\.isKeyboardNavigationEnabled, Keys.keyboardNavigation, true),
        (\.isTabShortcutsEnabled, Keys.tabShortcutsEnabled, true),
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
        (\.isOptimizedAnimationModeEnabled, Keys.optimizedAnimationsEnabled, true)
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
        shortcutBindings = RoutedAction.defaultBindings
        resetGestureMappings()
    }

    // MARK: - Binding store

    /// The binding assigned to `action`, if any. Presence ⇔ active.
    func binding(for action: RoutedAction) -> ShortcutBinding? {
        shortcutBindings[action]
    }

    /// When `true`, shortcuts and gestures on the window tab strip close/reopen tabs.
    /// When `false`, tab strip checks are bypassed and fallback window actions execute.
    var isTabShortcutsEnabled = true {
        didSet { UserDefaults.standard.set(isTabShortcutsEnabled, forKey: Self.Keys.tabShortcutsEnabled) }
    }

    /// Assigns (or clears) an action's combination and persists the change.
    ///
    /// Rules:
    /// 1. `.close` and `.closeTab` are linked twins: changing or clearing one
    ///    automatically changes or clears the other.
    /// 2. Except for `.close` and `.closeTab`, every shortcut combination must be
    ///    unique across all actions. Assigning an existing combination to another
    ///    action unassigns it from its previous owner.
    mutating func setBinding(_ binding: ShortcutBinding?, for action: RoutedAction) {
        if action == .close || action == .closeTab {
            if let binding {
                // Clear this combination from any other non-close action
                for (otherAction, otherBinding) in shortcutBindings
                    where otherAction != .close && otherAction != .closeTab {
                    if otherBinding == binding {
                        shortcutBindings.removeValue(forKey: otherAction)
                    }
                }
                shortcutBindings[.close] = binding
                shortcutBindings[.closeTab] = binding
            } else {
                shortcutBindings.removeValue(forKey: .close)
                shortcutBindings.removeValue(forKey: .closeTab)
            }
            return
        }

        if let binding {
            // Displace any existing action claiming this binding (including close/closeTab)
            for (otherAction, otherBinding) in shortcutBindings where otherBinding == binding {
                if otherAction == .close || otherAction == .closeTab {
                    shortcutBindings.removeValue(forKey: .close)
                    shortcutBindings.removeValue(forKey: .closeTab)
                } else {
                    shortcutBindings.removeValue(forKey: otherAction)
                }
            }
            shortcutBindings[action] = binding
        } else {
            shortcutBindings.removeValue(forKey: action)
        }
    }

    /// Every key code currently bound to any action — the keystroke pre-filter's admission set.
    var boundKeyCodes: Set<Int64> {
        Set(shortcutBindings.values.map(\.keyCode))
    }

    /// Actions whose stored binding matches this event, in routing-precedence order (`RoutedAction.routeOrder`).
    func matchedActions(keyCode: Int64, includesShift: Bool) -> [RoutedAction] {
        RoutedAction.routeOrder.filter { action in
            guard let candidate = shortcutBindings[action] else { return false }
            return candidate.keyCode == keyCode && candidate.includesShift == includesShift
        }
    }
}

// MARK: - Persistence & Migration

private extension ShortcutConfiguration {
    struct StoredBinding: Codable {
        let action: String
        let keyCode: Int64
        let includesShift: Bool
    }

    func persistShortcutBindings() {
        let rows = shortcutBindings.map { action, binding in
            StoredBinding(action: action.rawValue, keyCode: binding.keyCode, includesShift: binding.includesShift)
        }
        if let data = try? JSONEncoder().encode(rows) {
            UserDefaults.standard.set(data, forKey: Self.bindingsStorageKey)
        }
    }

    mutating func loadStoredBindings() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.bindingsStorageKey),
           let rows = try? JSONDecoder().decode([StoredBinding].self, from: data) {
            var restored = [RoutedAction: ShortcutBinding]()
            for row in rows {
                guard let action = RoutedAction(rawValue: row.action) else { continue }
                restored[action] = ShortcutBinding(keyCode: row.keyCode, includesShift: row.includesShift)
            }
            shortcutBindings = restored
            return
        }
        migrateLegacyShortcutToggles()
    }

    mutating func migrateLegacyShortcutToggles() {
        let defaults = UserDefaults.standard
        let hasLegacyState = Self.legacyShortcutToggles.contains { defaults.object(forKey: $0.key) != nil }
        guard hasLegacyState else { return }

        var migrated = RoutedAction.defaultBindings
        for entry in Self.legacyShortcutToggles {
            guard defaults.object(forKey: entry.key) != nil else { continue }
            migrated[entry.action] = defaults.bool(forKey: entry.key) ? entry.action.canonicalBinding : nil
        }
        shortcutBindings = migrated
        for entry in Self.legacyShortcutToggles {
            defaults.removeObject(forKey: entry.key)
        }
    }

    static let legacyShortcutToggles: [(key: String, action: RoutedAction)] = [
        (Keys.closingEnabled, .close),
        (Keys.cmdWEnabled, .closeTab),
        (Keys.cmdQEnabled, .quit),
        (Keys.cmdMEnabled, .minimize),
        (Keys.cmdHEnabled, .hide),
        (Keys.cmdFEnabled, .fullscreen),
        (Keys.cmdTEnabled, .newTab),
        (Keys.cmdNEnabled, .newWindow),
        (Keys.cmdShiftWEnabled, .closeAllTabs),
        (Keys.cmdShiftTEnabled, .reopenTab),
        (Keys.fillScreenEnabled, .fillScreen),
        (Keys.almostMaximizeEnabled, .almostMaximize),
        (Keys.reasonableSizeEnabled, .reasonableSize),
        (Keys.makeLargerEnabled, .makeLarger),
        (Keys.makeSmallerEnabled, .makeSmaller),
        (Keys.moveNextDesktopEnabled, .moveNextDesktop),
        (Keys.movePreviousDesktopEnabled, .movePreviousDesktop)
    ]

    static func loadBool(forKey key: String) -> Bool? {
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        return UserDefaults.standard.bool(forKey: key)
    }

    func persistGestureActions() {
        let dict = Dictionary(uniqueKeysWithValues: gestureActions.map { ($0.key.rawValue, $0.value.rawValue) })
        UserDefaults.standard.set(dict, forKey: Self.Keys.gestureActions)
    }

    func persistCmdGestureActions() {
        let dict = Dictionary(uniqueKeysWithValues: cmdGestureActions.map { ($0.key.rawValue, $0.value.rawValue) })
        UserDefaults.standard.set(dict, forKey: Self.Keys.cmdGestureActions)
    }

    enum Keys {
        static let shortcutBindings = "mcsc.shortcuts.bindings"
        static let closingEnabled = "mcsc.shortcuts.closing.enabled"
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
        static let fillScreenEnabled = "mcsc.shortcuts.fillScreen.enabled"
        static let almostMaximizeEnabled = "mcsc.shortcuts.almostMaximize.enabled"
        static let reasonableSizeEnabled = "mcsc.shortcuts.reasonableSize.enabled"
        static let makeLargerEnabled = "mcsc.shortcuts.makeLarger.enabled"
        static let makeSmallerEnabled = "mcsc.shortcuts.makeSmaller.enabled"
        static let moveNextDesktopEnabled = "mcsc.shortcuts.moveNextDesktop.enabled"
        static let movePreviousDesktopEnabled = "mcsc.shortcuts.movePreviousDesktop.enabled"
        static let keyboardNavigation = "mcsc.keyboardNavigation.enabled"
        static let tabShortcutsEnabled = "mcsc.tabShortcuts.enabled"
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
