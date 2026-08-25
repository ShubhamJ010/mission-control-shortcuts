import Foundation

// MARK: - Rebindable shortcut model

//
// A keyboard shortcut is *active* exactly when a binding is assigned to its
// action — there is no separate enable flag. Bindings are Command-implied
// (⌘ + key, optionally Shift); Control/Option never participate, mirroring
// `ShortcutActionRouter.shouldHandle(flags:)`.

/// A single key combination bound to an action.
struct ShortcutBinding: Codable, Equatable, Hashable {
    /// Virtual key code (CGEvent `keyCode` domain).
    let keyCode: Int64
    /// Whether the combination also requires Shift (e.g. ⌘⇧D).
    var includesShift: Bool

    init(keyCode: Int64, includesShift: Bool = false) {
        self.keyCode = keyCode
        self.includesShift = includesShift
    }

    /// Human-readable glyph string with per-glyph gaps, e.g. "⌘ W" / "⇧ ⌘→".
    /// Modifiers render in macOS menu order (⇧ before ⌘).
    var displayString: String {
        let shift = includesShift ? "⇧ " : ""
        return shift + "⌘ " + ShortcutKeySymbols.glyph(for: keyCode)
    }
}

// MARK: - Routed actions

/// Every window/app action a keyboard shortcut can be bound to. The raw value
/// is the persistence key in `UserDefaults`.
enum RoutedAction: String, Codable, CaseIterable {
    case close
    case closeTab
    case quit
    case minimize
    case hide
    case fullscreen
    case newTab
    case newWindow
    case closeAllTabs
    case reopenTab
    case fillScreen
    case almostMaximize
    case reasonableSize
    case makeLarger
    case makeSmaller
    case moveNextDesktop
    case movePreviousDesktop
    case minimizeAll
    case unminimizeAll

    /// The canonical binding offered when the legacy boolean toggles flip on,
    /// and the pre-assigned default where the old default was enabled.
    var canonicalBinding: ShortcutBinding {
        switch self {
        case .close: ShortcutBinding(keyCode: 13) // W
        case .closeTab: ShortcutBinding(keyCode: 13) // W
        case .quit: ShortcutBinding(keyCode: 12) // Q
        case .minimize: ShortcutBinding(keyCode: 46) // M
        case .hide: ShortcutBinding(keyCode: 4) // H
        case .fullscreen: ShortcutBinding(keyCode: 3) // F
        case .newTab: ShortcutBinding(keyCode: 17) // T
        case .newWindow: ShortcutBinding(keyCode: 45) // N
        case .closeAllTabs: ShortcutBinding(keyCode: 13, includesShift: true)
        case .reopenTab: ShortcutBinding(keyCode: 17, includesShift: true)
        case .fillScreen: ShortcutBinding(keyCode: 2, includesShift: true) // D
        case .almostMaximize: ShortcutBinding(keyCode: 0, includesShift: true) // A
        case .reasonableSize: ShortcutBinding(keyCode: 15, includesShift: true) // R
        case .makeLarger: ShortcutBinding(keyCode: 37, includesShift: true) // L
        case .makeSmaller: ShortcutBinding(keyCode: 1, includesShift: true) // S
        case .moveNextDesktop: ShortcutBinding(keyCode: 124, includesShift: true) // →
        case .movePreviousDesktop: ShortcutBinding(keyCode: 123, includesShift: true) // ←
        case .minimizeAll: ShortcutBinding(keyCode: 46, includesShift: true) // M
        case .unminimizeAll: ShortcutBinding(keyCode: 32, includesShift: true) // U
        }
    }
}

extension RoutedAction {
    /// Fresh-install bindings: exactly the actions that shipped enabled —
    /// everything else starts unassigned (gesture-only), i.e. disabled.
    static let defaultBindings: [RoutedAction: ShortcutBinding] = [
        .close: RoutedAction.close.canonicalBinding,
        .closeTab: RoutedAction.closeTab.canonicalBinding,
        .quit: RoutedAction.quit.canonicalBinding,
        .minimize: RoutedAction.minimize.canonicalBinding,
        .hide: RoutedAction.hide.canonicalBinding
    ]

    /// Routing precedence when several actions share one combination (e.g.
    /// Close and Close Tab both ship bound to ⌘W and are disambiguated by
    /// hover context). Order mirrors the historical router branch order.
    static let routeOrder: [RoutedAction] = [
        .close, .closeTab, .quit, .minimize, .hide,
        .fullscreen, .newTab, .newWindow,
        .closeAllTabs, .reopenTab,
        .fillScreen, .almostMaximize, .reasonableSize, .makeLarger, .makeSmaller,
        .moveNextDesktop, .movePreviousDesktop,
        .minimizeAll, .unminimizeAll
    ]
}

// MARK: - Key-code glyphs

/// Maps virtual key codes to display glyphs for recorder fields. Pure data —
/// no framework calls, so it stays allocation-free at render time.
enum ShortcutKeySymbols {
    private static let glyphs: [Int64: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=",
        25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]",
        36: "Return", 48: "Tab", 49: "Space", 50: "`", 51: "Delete",
        53: "Esc", 56: "⇧", 57: "Caps Lock", 58: "⌥", 59: "Control",
        60: "⇧", 61: "⌥", 63: "Fn",
        64: "F1", 79: "F1", 80: "F2", 81: "F3", 82: "F4", 83: "F5",
        84: "F6", 85: "F7", 86: "F8", 87: "F9", 88: "F10", 89: "F11",
        91: "F12", 92: "F13", 93: "F14", 94: "F15",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
        103: "F11", 105: "F13", 107: "F14", 109: "F10", 111: "F12",
        113: "Home", 114: "End", 115: "Home", 116: "Page Up",
        117: "Forward Delete", 118: "F4", 119: "End", 120: "F2",
        121: "Page Down", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]

    static func glyph(for keyCode: Int64) -> String {
        if let glyph = glyphs[keyCode] {
            return glyph
        }
        guard let scalar = Unicode.Scalar(UInt32(keyCode)) else { return "Key \(keyCode)" }
        let character = Character(scalar)
        return character.isLetter || character.isNumber ? String(character).uppercased() : "Key \(keyCode)"
    }
}
