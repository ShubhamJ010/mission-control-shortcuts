import Foundation

// MARK: - Kind

/// The seven physical trackpad gestures recognised by the engine.
/// Each kind has both a plain and a ⌘-modified variant; the mapping is
/// `kind + isCmd → action`.
enum GestureKind: String, CaseIterable {
    case pinchIn
    case pinchOut
    case swipeLeft
    case swipeRight
    case swipeDown
    case swipeUp
    case twoFingerDoubleTap

    /// Short human name shown in the settings pane.
    var displayName: String {
        switch self {
        case .pinchIn: "Pinch In"
        case .pinchOut: "Pinch Out"
        case .swipeLeft: "Swipe Left"
        case .swipeRight: "Swipe Right"
        case .swipeDown: "Swipe Down"
        case .swipeUp: "Swipe Up"
        case .twoFingerDoubleTap: "2-Finger Double Tap"
        }
    }

    /// SF Symbol used next to the name in the gesture rows.
    var symbolName: String {
        switch self {
        case .pinchIn: "arrow.inward"
        case .pinchOut: "arrow.outward"
        case .swipeLeft: "arrow.left"
        case .swipeRight: "arrow.right"
        case .swipeDown: "arrow.down"
        case .swipeUp: "arrow.up"
        case .twoFingerDoubleTap: "hand.tap"
        }
    }

    /// Whether this kind triggers `activateApp` when fired on a window/dock target.
    /// Mirrors legacy behaviour: only swipe-left auto-activates the target app.
    var activatesApp: Bool {
        self == .swipeLeft
    }

    /// Haptic type for this kind; two-finger tap varies by modifier.
    func haptic(isCmd: Bool) -> HapticType {
        switch self {
        case .pinchIn: .pinchIn
        case .pinchOut: .pinchOut
        case .swipeLeft: .swipeLeft
        case .swipeRight: .swipeRight
        case .swipeDown: .swipeDown
        case .swipeUp: .swipeUp
        case .twoFingerDoubleTap: isCmd ? .cmdTwoFingerDoubleTap : .twoFingerDoubleTap
        }
    }

    /// Actions semantically natural for this gesture — drives the filtered popups
    /// in `GestureSettingsPane`. Keeping the lists short makes the UX natural:
    /// only actions that feel like the gesture are offered.
    var naturalActions: [GestureAction] {
        switch self {
        case .pinchIn:
            [.closeWindow, .quitApp, .closeTab, .closeAllTabs, .makeSmaller]
        case .pinchOut:
            [.toggleFullscreen, .fillScreen, .almostMaximize, .makeLarger, .newWindow]
        case .swipeLeft:
            [.closeTab, .closeAllTabs, .closeWindow, .quitApp, .movePreviousDesktop]
        case .swipeRight:
            [.reopenTab, .newTab, .newWindow, .moveNextDesktop]
        case .swipeUp:
            [.unminimizeAll, .minimize, .hideApp, .makeSmaller]
        case .swipeDown:
            [.minimizeAll, .fillScreen, .almostMaximize, .makeLarger, .makeSmaller, .reasonableSize]
        case .twoFingerDoubleTap:
            [.reasonableSize, .almostMaximize, .toggleFullscreen, .makeSmaller, .makeLarger]
        }
    }
}

// MARK: - Action

/// The window/app action a gesture can be bound to.
/// Raw values are persisted to UserDefaults, so never rename or delete — only append.
enum GestureAction: String, CaseIterable {
    case closeWindow
    case quitApp
    case closeTab
    case closeAllTabs
    case reopenTab
    case newTab
    case newWindow
    case toggleFullscreen
    case fillScreen
    case almostMaximize
    case makeLarger
    case makeSmaller
    case reasonableSize
    case minimize
    case hideApp
    case moveNextDesktop
    case movePreviousDesktop
    case minimizeAll
    case unminimizeAll

    /// Label shown in the popup menu.
    var menuTitle: String {
        switch self {
        case .closeWindow: "Close Window"
        case .quitApp: "Quit App"
        case .closeTab: "Close Tab"
        case .closeAllTabs: "Close All Tabs"
        case .reopenTab: "Reopen Tab"
        case .newTab: "New Tab"
        case .newWindow: "New Window"
        case .toggleFullscreen: "Toggle Fullscreen"
        case .fillScreen: "Fill Screen"
        case .almostMaximize: "Almost Maximize"
        case .makeLarger: "Make Larger (+33%)"
        case .makeSmaller: "Make Smaller (−33%)"
        case .reasonableSize: "Reasonable Size"
        case .minimize: "Minimize"
        case .hideApp: "Hide App"
        case .moveNextDesktop: "Move to Next Desktop"
        case .movePreviousDesktop: "Move to Previous Desktop"
        case .minimizeAll: "Minimize All"
        case .unminimizeAll: "Unminimize All"
        }
    }

    /// Short subtitle hint used only in docs/tests if needed.
    var shortDescription: String {
        menuTitle
    }
}

// MARK: - Defaults

/// Factory defaults matching the legacy hardcoded GestureActionRouter mappings.
enum GestureDefaults {
    static func action(for kind: GestureKind, isCmd: Bool) -> GestureAction {
        switch (kind, isCmd) {
        case (.pinchIn, false): .closeWindow
        case (.pinchIn, true): .quitApp
        case (.pinchOut, false): .toggleFullscreen
        case (.pinchOut, true): .newWindow
        case (.swipeLeft, false): .closeTab
        case (.swipeLeft, true): .closeAllTabs
        case (.swipeRight, false): .reopenTab
        case (.swipeRight, true): .newTab
        case (.swipeDown, false): .fillScreen
        case (.swipeDown, true): .makeLarger
        case (.swipeUp, false): .minimize
        case (.swipeUp, true): .hideApp
        case (.twoFingerDoubleTap, false): .reasonableSize
        case (.twoFingerDoubleTap, true): .almostMaximize
        }
    }

    static var plainDefaults: [GestureKind: GestureAction] {
        Dictionary(uniqueKeysWithValues: GestureKind.allCases.map { ($0, action(for: $0, isCmd: false)) })
    }

    static var cmdDefaults: [GestureKind: GestureAction] {
        Dictionary(uniqueKeysWithValues: GestureKind.allCases.map { ($0, action(for: $0, isCmd: true)) })
    }
}

// MARK: - GestureResult → kind projection

extension GestureResult {
    /// Decomposes a result into its kind + whether ⌘ was held.
    var kindAndModifier: (kind: GestureKind, isCmd: Bool) {
        switch self {
        case .pinchIn: (.pinchIn, false)
        case .cmdPinchIn: (.pinchIn, true)
        case .pinchOut: (.pinchOut, false)
        case .cmdPinchOut: (.pinchOut, true)
        case .swipeLeft: (.swipeLeft, false)
        case .cmdSwipeLeft: (.swipeLeft, true)
        case .swipeRight: (.swipeRight, false)
        case .cmdSwipeRight: (.swipeRight, true)
        case .swipeDown: (.swipeDown, false)
        case .cmdSwipeDown: (.swipeDown, true)
        case .swipeUp: (.swipeUp, false)
        case .cmdSwipeUp: (.swipeUp, true)
        case .twoFingerDoubleTap: (.twoFingerDoubleTap, false)
        case .cmdTwoFingerDoubleTap: (.twoFingerDoubleTap, true)
        }
    }
}
