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
/// ## Cost
/// One `CGWindowListCopyWindowInfo` scan per second at most, plus a verdict
/// cache keyed by window id. No timers, no per-frame AX IPC. `purge()` releases
/// everything when MCSC nears its memory ceiling.
@MainActor
final class WindowComponentClassifier {
    /// A floating window seen while classifying, shown in Settings.
    struct DetectedComponent: Identifiable, Equatable {
        var id: String {
            bundleID
        }

        let bundleID: String
        let appName: String
        let kind: WindowComponentKind
        let layer: Int
    }

    /// Minimum fields needed from the CoreGraphics window list.
    private struct Snapshot {
        let layer: Int
        let pid: pid_t
        let title: String
    }

    private struct Verdict {
        let isComponent: Bool
        let expires: TimeInterval
    }

    // MARK: - Tunables

    /// Verdict freshness. Long enough to avoid repeated scans while hovering,
    /// short enough to notice a window being re-used for a different purpose.
    private static let verdictTTL: TimeInterval = 5

    /// Snapshot freshness. One scan per second covers window churn during a
    /// gesture without measurable cost.
    private static let snapshotTTL: TimeInterval = 1

    /// Bounded caches: MCSC must stay under its 13 MB ceiling.
    private static let maxVerdicts = 32
    private static let maxDetected = 16
    private static let maxBundleIDs = 32

    // MARK: - State

    private let defaults: UserDefaults
    private var snapshot: [CGWindowID: Snapshot] = [:]
    private var snapshotStamp: TimeInterval = 0
    private var verdicts: [CGWindowID: Verdict] = [:]
    private var verdictOrder: [CGWindowID] = []
    private var bundleIDsByPID: [pid_t: String] = [:]
    private var overrides: [String: WindowComponentBehavior] = [:]
    private var didLoadOverrides = false
    private var purgeObserver: NSObjectProtocol?

    /// Floating windows seen so far, newest app first. Bounded.
    private(set) var detectedComponents: [DetectedComponent] = []

    // MARK: - Settings

    /// Master toggle. Absent from defaults means enabled, so a fresh install
    /// ignores PiP windows with no setup.
    var isEnabled: Bool {
        get { defaults.object(forKey: WindowComponentDefaults.isEnabledKey) as? Bool ?? true }
        set {
            guard newValue != isEnabled else { return }
            defaults.set(newValue, forKey: WindowComponentDefaults.isEnabledKey)
            purge()
            AppLogger.components.info("Floating window ignoring \(newValue ? "enabled" : "disabled", privacy: .public)")
        }
    }

    /// User overrides keyed by bundle identifier.
    var userOverrides: [String: WindowComponentBehavior] {
        loadOverridesIfNeeded()
        return overrides
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
        guard isEnabled else { return false }

        let now = ProcessInfo.processInfo.systemUptime
        if let verdict = verdicts[windowID], verdict.expires > now {
            return verdict.isComponent
        }

        guard let window = snapshotIfNeeded()[windowID],
              window.layer >= WindowComponentDefaults.minComponentLayer else {
            store(false, for: windowID, at: now)
            return false
        }

        let bundleID = bundleID(for: window.pid)
        let isComponent = behavior(for: bundleID) != .allow
        if isComponent {
            recordDetection(bundleID: bundleID, pid: window.pid, title: window.title, layer: window.layer)
        }
        store(isComponent, for: windowID, at: now)
        AppLogger.components.debug(
            "window id=\(windowID, privacy: .public) layer=\(window.layer, privacy: .public) component=\(isComponent, privacy: .public)"
        )
        return isComponent
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
        let bundleID = bundleID(for: pid)
        let isComponent = behavior(for: bundleID) != .allow
        if isComponent {
            let title = windowInfo[kCGWindowName as String] as? String
            recordDetection(bundleID: bundleID, pid: pid, title: title, layer: layer)
        }
        return isComponent
    }

    // MARK: - Overrides

    /// Persists `behavior` for `bundleID`. `.ignore` and `.allow` are both
    /// stored so a user can force either direction.
    func setBehavior(_ behavior: WindowComponentBehavior, forBundleID bundleID: String) {
        loadOverridesIfNeeded()
        overrides[bundleID] = behavior
        saveOverrides()
        purgeVerdicts()
        AppLogger.components.info(
            "Override \(bundleID, privacy: .public) -> \(behavior.rawValue, privacy: .public)"
        )
    }

    /// Removes every user override, restoring built-in detection.
    func resetOverrides() {
        overrides.removeAll()
        defaults.removeObject(forKey: WindowComponentDefaults.rulesKey)
        purgeVerdicts()
        AppLogger.components.info("Floating window overrides reset")
    }

    // MARK: - Lifecycle

    /// Releases all caches. Called from `AccessibilityService.purgeCaches()`
    /// and when the master toggle flips.
    func purge() {
        snapshot.removeAll()
        snapshotStamp = 0
        purgeVerdicts()
        bundleIDsByPID.removeAll()
        detectedComponents.removeAll()
    }

    // MARK: - Internals

    private func behavior(for bundleID: String?) -> WindowComponentBehavior? {
        loadOverridesIfNeeded()
        guard let bundleID else { return nil }
        return overrides[bundleID]
    }

    private func store(_ isComponent: Bool, for windowID: CGWindowID, at now: TimeInterval) {
        if verdicts[windowID] == nil {
            verdictOrder.append(windowID)
        }
        verdicts[windowID] = Verdict(isComponent: isComponent, expires: now + Self.verdictTTL)
        if verdictOrder.count > Self.maxVerdicts {
            let evicted = verdictOrder.removeFirst()
            verdicts.removeValue(forKey: evicted)
        }
    }

    private func purgeVerdicts() {
        verdicts.removeAll()
        verdictOrder.removeAll()
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
                pid: window[kCGWindowOwnerPID as String] as? pid_t ?? 0,
                title: window[kCGWindowName as String] as? String ?? ""
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

    private func recordDetection(bundleID: String?, pid: pid_t, title: String?, layer: Int) {
        guard let bundleID else { return }
        // Hot path: Mission Control polls the window list twice per second.
        // Skip the NSRunningApplication lookup when nothing changed.
        if let existing = detectedComponents.first(where: { $0.bundleID == bundleID }),
           existing.layer == layer {
            return
        }
        let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? bundleID
        let entry = DetectedComponent(
            bundleID: bundleID,
            appName: appName,
            kind: WindowComponentDefaults.kind(bundleID: bundleID, title: title),
            layer: layer
        )
        if let index = detectedComponents.firstIndex(where: { $0.bundleID == bundleID }) {
            detectedComponents[index] = entry
        } else {
            detectedComponents.insert(entry, at: 0)
            if detectedComponents.count > Self.maxDetected {
                detectedComponents.removeLast()
            }
        }
    }

    // MARK: - Persistence

    private func loadOverridesIfNeeded() {
        guard !didLoadOverrides else { return }
        didLoadOverrides = true
        guard let data = defaults.data(forKey: WindowComponentDefaults.rulesKey),
              let rules = try? JSONDecoder().decode([WindowComponentRule].self, from: data) else {
            return
        }
        overrides = Dictionary(uniqueKeysWithValues: rules.map { ($0.bundleID, $0.behavior) })
    }

    private func saveOverrides() {
        let rules = overrides.map { WindowComponentRule(bundleID: $0.key, behavior: $0.value) }
        guard let data = try? JSONEncoder().encode(rules) else { return }
        defaults.set(data, forKey: WindowComponentDefaults.rulesKey)
    }
}
