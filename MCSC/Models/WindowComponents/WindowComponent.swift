import Foundation

/// Configuration keys and the platform fact needed to spot floating "component"
/// windows (browser picture-in-picture, always-on-top panels).
///
/// Pure data: no UserDefaults access, no AX calls, no AppKit.
///
/// ## Configuration is CLI-only
/// There is no settings pane. The behavior is on by default and can be changed
/// from Terminal:
///
/// ```sh
/// defaults write sj010.MCSC mcsc.windowComponents.ignoreFloating -bool false
/// defaults delete sj010.MCSC mcsc.windowComponents.ignoreFloating
/// defaults write sj010.MCSC "mcsc.windowComponents.allow.app.zen-browser.zen" -bool true
/// ```
enum WindowComponentDefaults {
    /// Windows at this CoreGraphics layer or above float over normal windows.
    /// Measured: Zen PiP = 3, Dia PiP = 3, floatyMPV = 3, normal windows = 0.
    static let minComponentLayer = 3

    /// Master toggle. Absent means enabled, so a fresh install ignores PiP
    /// windows with no setup.
    static let isEnabledKey = "mcsc.windowComponents.ignoreFloating"

    /// Prefix for per-app opt-outs: `mcsc.windowComponents.allow.<bundleID>`.
    /// Absent (or `false`) means the app's floating windows stay ignored.
    static let allowKeyPrefix = "mcsc.windowComponents.allow."

    /// UserDefaults key that restores normal targeting for one application.
    static func allowKey(forBundleID bundleID: String) -> String {
        allowKeyPrefix + bundleID
    }
}
