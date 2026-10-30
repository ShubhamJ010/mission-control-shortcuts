import Foundation

/// What kind of non-document window MCSC found under the cursor.
///
/// PiP windows are created by browsers; floating panels by media players and
/// utilities. Both are borderless and always-on-top, so the "top 28 pt is the
/// title bar" assumption in `ShortcutViewModel` does not hold for them.
enum WindowComponentKind: String, Codable, Sendable {
    /// Browser picture-in-picture video window (Zen, Dia, Arc, Safari).
    case pip
    /// Always-on-top panel with no title bar (e.g. floatyMPV).
    case floatingPanel
    /// Anything else that floats above normal windows.
    case custom
}

/// How gestures and Command shortcuts treat a component window.
enum WindowComponentBehavior: String, Codable, Sendable {
    /// Never resolve the window as a target. Gestures and shortcuts do nothing.
    case ignore
    /// Treat the window like a normal document window (title-bar actions apply).
    case allow
}

/// A user override for one application's floating windows, persisted in
/// `UserDefaults` as JSON.
///
/// Rules are keyed by bundle identifier only: every floating window of that app
/// gets the same behavior. Built-in detection already covers PiP windows, so a
/// rule is only needed to *allow* an app whose floating panels should stay
/// targetable, or to force-ignore one.
struct WindowComponentRule: Codable, Equatable, Sendable {
    let bundleID: String
    var behavior: WindowComponentBehavior
}

/// Constants and built-in knowledge for floating/PiP window detection.
///
/// Pure data: no UserDefaults access, no AX calls, no AppKit.
enum WindowComponentDefaults {
    /// Windows at this CoreGraphics layer or above float over normal windows.
    /// Measured: Zen PiP = 3, Dia PiP = 3, floatyMPV = 3, normal windows = 0.
    static let minComponentLayer = 3

    /// UserDefaults key for the master toggle. Absent means enabled.
    static let isEnabledKey = "mcsc.windowComponents.ignoreFloating"

    /// UserDefaults key for the JSON-encoded `[WindowComponentRule]` overrides.
    static let rulesKey = "mcsc.windowComponents.rules"

    /// Apps known to create PiP windows. Used only to label detections in
    /// Settings and to log a meaningful kind; detection itself is layer-based
    /// so unlisted apps are still ignored.
    static let pipBundleIDs: Set<String> = [
        "app.zen-browser.zen",
        "company.thebrowser.dia",
        "company.thebrowser.arc",
        "com.apple.Safari",
        "sj010.floatyMPV"
    ]

    /// Window titles browsers use for their PiP window. English only; the
    /// layer check is the portable signal, this is a secondary hint.
    static let pipTitleHints = ["picture-in-picture", "picture in picture"]

    /// `true` when `title` looks like a browser PiP window title.
    static func titleLooksLikePiP(_ title: String?) -> Bool {
        guard let title = title?.lowercased(), !title.isEmpty else { return false }
        return pipTitleHints.contains { title.contains($0) }
    }

    /// Kind label for a detected window.
    static func kind(bundleID: String?, title: String?) -> WindowComponentKind {
        if let bundleID, pipBundleIDs.contains(bundleID) {
            return .pip
        }
        if titleLooksLikePiP(title) {
            return .pip
        }
        return .floatingPanel
    }
}
