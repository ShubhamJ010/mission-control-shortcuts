import Cocoa

/// Decides whether a window is a floating "component" (PiP video, always-on-top
/// panel) that must not be treated as a document window.
///
/// ## Why layer, not titles
/// Measured on macOS 27: Zen PiP reports `AXStandardWindow` with virtual
/// traffic-light buttons, Dia PiP reports `AXSystemDialog`, both have an empty
/// or browser-specific title. The only shared, portable signal is the
/// CoreGraphics window layer: normal windows are `0`, PiP/panels float at `3`.
///
/// ## Configuration
/// CLI-only, no settings UI. Default is enabled. See `WindowComponentDefaults`
/// for the exact `defaults` keys. Keys are read on every query, so a
/// `defaults write` applies without relaunching MCSC.
///
/// ## Cost
/// One `CGWindowListCopyWindowInfo` scan per second at most, plus a pid →
/// bundle-id cache. No timers, no per-frame AX IPC, no verdict cache to
/// invalidate. `purge()` releases everything when MCSC nears its memory
/// ceiling.
@MainActor
final class WindowComponentClassifier {
    /// Minimum fields needed from the CoreGraphics window list.
    private struct Snapshot {
        let layer: Int
        let pid: pid_t
    }

    // MARK: - Tunables

    /// Snapshot freshness. One scan per second covers window churn during a
    /// gesture without measurable cost.
    private static let snapshotTTL: TimeInterval = 1

    /// Bounded cache: MCSC must stay under its 13 MB ceiling.
    private static let maxBundleIDs = 32

    // MARK: - State

    private let defaults: UserDefaults
    private var snapshot: [CGWindowID: Snapshot] = [:]
    private var snapshotStamp: TimeInterval = 0
    private var bundleIDsByPID: [pid_t: String] = [:]
    private var lastLoggedWindowID: CGWindowID = 0
    private var purgeObserver: NSObjectProtocol?

    // MARK: - Settings

    /// Master toggle. Absent from defaults means enabled (default-on).
    var isEnabled: Bool {
        defaults.object(forKey: WindowComponentDefaults.isEnabledKey) as? Bool ?? true
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        purgeObserver = NotificationCenter.default.addObserver(
            forName: .mcscPurgeCaches,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.purge() }
        }
    }

    deinit {
        if let purgeObserver {
            NotificationCenter.default.removeObserver(purgeObserver)
        }
    }

    // MARK: - Queries

    /// `true` when the window id belongs to a floating component that must not
    /// become a gesture/shortcut target.
    func isComponent(windowID: CGWindowID) -> Bool {
        guard isEnabled,
              let window = snapshotIfNeeded()[windowID],
              window.layer >= WindowComponentDefaults.minComponentLayer else {
            return false
        }
        if let bundleID = bundleID(for: window.pid), isAllowed(bundleID) {
            return false
        }
        if windowID != lastLoggedWindowID {
            lastLoggedWindowID = windowID
            AppLogger.components.debug(
                "Ignoring floating window id=\(windowID, privacy: .public) layer=\(window.layer, privacy: .public)"
            )
        }
        return true
    }

    /// AX-entry point: resolves the CoreGraphics window id from an AX window.
    /// Returns `false` when the id cannot be resolved, so unknown windows keep
    /// their normal behavior.
    func isComponent(window: AXUIElement) -> Bool {
        var windowID: CGWindowID = 0
        guard _AXUIElementGetWindow(window, &windowID) == .success else { return false }
        return isComponent(windowID: windowID)
    }

    /// Mission Control entry point: the window dictionary already carries the
    /// layer, so no AX or window-list work is needed.
    func isComponent(windowInfo: [String: Any]) -> Bool {
        guard isEnabled,
              let layer = windowInfo[kCGWindowLayer as String] as? Int,
              layer >= WindowComponentDefaults.minComponentLayer else {
            return false
        }
        let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t ?? 0
        if let bundleID = bundleID(for: pid), isAllowed(bundleID) {
            return false
        }
        return true
    }

    // MARK: - Lifecycle

    /// Releases all caches. Called through `.mcscPurgeCaches` when MCSC nears
    /// its memory ceiling.
    func purge() {
        snapshot.removeAll()
        snapshotStamp = 0
        bundleIDsByPID.removeAll()
        lastLoggedWindowID = 0
    }

    // MARK: - Internals

    private func isAllowed(_ bundleID: String) -> Bool {
        defaults.bool(forKey: WindowComponentDefaults.allowKey(forBundleID: bundleID))
    }

    /// One window-list scan per second, shared by every query in that second.
    private func snapshotIfNeeded() -> [CGWindowID: Snapshot] {
        let now = ProcessInfo.processInfo.systemUptime
        if !snapshot.isEmpty, now - snapshotStamp < Self.snapshotTTL {
            return snapshot
        }
        snapshotStamp = now

        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return snapshot
        }

        var next: [CGWindowID: Snapshot] = [:]
        next.reserveCapacity(list.count)
        for window in list {
            guard let windowID = window[kCGWindowNumber as String] as? CGWindowID,
                  let layer = window[kCGWindowLayer as String] as? Int else { continue }
            next[windowID] = Snapshot(
                layer: layer,
                pid: window[kCGWindowOwnerPID as String] as? pid_t ?? 0
            )
        }
        snapshot = next
        return next
    }

    private func bundleID(for pid: pid_t) -> String? {
        guard pid > 0 else { return nil }
        if let cached = bundleIDsByPID[pid] {
            return cached
        }
        guard let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else {
            return nil
        }
        if bundleIDsByPID.count >= Self.maxBundleIDs {
            bundleIDsByPID.removeAll(keepingCapacity: true)
        }
        bundleIDsByPID[pid] = bundleID
        return bundleID
    }
}
