import Cocoa
import CoreGraphics
import Foundation

/// Detects whether Mission Control (or Exposé) is currently active and can
/// inject a "fix" key sequence when Cmd+Space is pressed while Mission
/// Control has swallowed the Spotlight shortcut.
///
/// Detection is two-pronged:
/// 1. Distributed Dock notifications (`com.apple.MissionControl.start` etc.) —
///    unreliable on modern macOS for standalone processes.
/// 2. A window-list heuristic that recognises Mission Control's full-screen
///    overlay + Dock bar, cached for `detectionCacheInterval` so gesture
///    frames never pay for a repeated `CGWindowListCopyWindowInfo` scan.
///
/// The authoritative signal is the Dock AXObserver in
/// `MissionControlHoverService`, pushed in via `markActive(_:)`. The
/// window-list scan is a time-bounded fallback: the latch is trusted only
/// while the cache window is fresh, after which the scan self-corrects a
/// missed close notification (fix: stuck-true landmine).
@MainActor
protocol MissionControlServiceProtocol: AnyObject {
    var isMissionControlActive: Bool { get }
    var isSimulating: Bool { get set }
    var onActivated: (() -> Void)? { get set }
    var onDeactivated: (() -> Void)? { get set }
    func checkMissionControlActive() -> Bool
    func executeFixSequence()
    func start()
    func stop()
    /// Push the authoritative Dock AXObserver transition into the service so
    /// `isMissionControlActive` mirrors the instant signal instead of the
    /// lagging 350 ms window-list scan.
    func markActive(_ active: Bool)
}

@MainActor
final class MissionControlService: MissionControlServiceProtocol {
    private var _isMissionControlActive = false
    var isMissionControlActive: Bool {
        checkMissionControlActive()
    }

    var isSimulating = false

    /// Fires when Mission Control (or Expose) activates. Used for gesture cooldown.
    var onActivated: (() -> Void)?

    /// Fires when Mission Control (or Expose) deactivates. Mirrors
    /// `onActivated`; driven by the Dock AXObserver close transition via
    /// `markActive(false)`.
    var onDeactivated: (() -> Void)?

    /// Maintain notification observers for cleanup
    private var observers: [NSObjectProtocol] = []
    /// Guards `start()` so repeated calls do not register duplicate Dock
    /// notification observers.
    private var isStarted = false

    // MARK: - Detection tuning (verified on macOS 15.7.3)

    /// Layer of Mission Control's full-screen Dock overlay window.
    private let missionControlOverlayLayer = 20
    /// Mission Control also shows the Dock bar at/below this layer; a Finder
    /// folder stack shows only the overlay and lacks this, so it is excluded.
    private let dockBarLayerThreshold = 18

    // MARK: - Cached detection (coalesced; polled at most every 350ms)

    /// Cache window for the detection scan. A `var` so tests can set it to 0
    /// to force cache misses and exercise the latch self-correction path.
    var detectionCacheInterval: Double = 0.35
    private var cachedIsActive: Bool?
    private var lastDetectionTime: Double = 0
    /// Guards `CGWindowListCopyWindowInfo` from re-entrancy when two HID
    /// sources (event tap + multitouch) miss the cache on the same runloop
    /// turn. Set while the WindowServer IPC is in flight.
    private var isDetecting = false

    /// Test-only: force the cache window to expire so the next
    /// `checkMissionControlActive()` runs the scan instead of serving the
    /// latched value. Used to exercise the latch self-correction path
    /// without waiting for `detectionCacheInterval` of wall time.
    func _testForceCacheExpiry() {
        lastDetectionTime = 0
    }

    /// Injectable window-list scan so tests can drive the heuristic
    /// deterministically without the real `CGWindowListCopyWindowInfo` IPC.
    /// Defaults to the real scan.
    private let windowListProvider: () -> [[String: Any]]?

    init(windowListProvider: @escaping () -> [[String: Any]]? = {
        CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]]
    }) {
        self.windowListProvider = windowListProvider
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        setupNotifications()
    }

    private func setupNotifications() {
        let center = DistributedNotificationCenter.default()

        let events = [
            "com.apple.expose.start", "com.apple.expose.stop",
            "com.apple.showdesktop.start", "com.apple.showdesktop.stop",
            "com.apple.expose.front.start", "com.apple.expose.front.stop",
            "com.apple.MissionControl.start", "com.apple.MissionControl.stop",
            "com.apple.dashboard.start", "com.apple.dashboard.stop"
        ]

        for event in events {
            let observer = center
                .addObserver(forName: NSNotification.Name(event), object: nil,
                             queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        if event.contains("start") {
                            self?.markActive(true)
                        }
                        if event.contains("stop") {
                            self?.markActive(false)
                        }
                    }
                }
            observers.append(observer)
        }
    }

    func stop() {
        let center = DistributedNotificationCenter.default()
        for observer in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
        _isMissionControlActive = false
        cachedIsActive = false
        lastDetectionTime = CACurrentMediaTime()
        isStarted = false
    }

    /// Push the authoritative Dock AXObserver transition into the service so
    /// the active state mirrors the instant signal instead of the lagging
    /// 350 ms window-list scan. Primes the cache so subsequent reads of
    /// `isMissionControlActive` are immediate and consistent. On close
    /// (`active == false`) the cache is set to `false` (not `nil`) so the
    /// next read returns instantly without a re-scan.
    func markActive(_ active: Bool) {
        _isMissionControlActive = active
        cachedIsActive = active
        lastDetectionTime = CACurrentMediaTime()
        if active {
            onActivated?()
        } else {
            onDeactivated?()
        }
    }

    /// Returns `true` only while Mission Control is open.
    ///
    /// The latch (`_isMissionControlActive`, set by `markActive` or Dock
    /// notifications) is trusted only while the cache window is fresh. After
    /// it expires the window-list scan runs and self-corrects a latched-true
    /// if no Mission Control windows are found, so a missed close
    /// notification can't pin the state true forever.
    ///
    /// Mission Control exposes an empty-named, full-screen Dock window at
    /// `missionControlOverlayLayer` *and* the Dock bar itself (empty-named
    /// windows at `dockBarLayerThreshold` or below). Launchpad uses higher
    /// layers (27–29) and a Finder folder stack shows only the overlay without
    /// the Dock bar, so both are excluded. The result is cached for
    /// `detectionCacheInterval` to avoid polling the window list on every
    /// trackpad frame.
    func checkMissionControlActive() -> Bool {
        let now = CACurrentMediaTime()

        // Latch fast-path: trust the notification/AXObserver signal while the
        // cache window is fresh. After it expires, fall through to the scan
        // so a missed close notification self-corrects (fix: stuck-true
        // landmine). Previously the latch was unconditional, pinning the state
        // true forever if the close notification was missed.
        if _isMissionControlActive, now - lastDetectionTime < detectionCacheInterval {
            return true
        }

        if now - lastDetectionTime < detectionCacheInterval, let cached = cachedIsActive {
            return cached
        }
        // Coalesce concurrent callers (event tap + multitouch) on same turn.
        if isDetecting, let cached = cachedIsActive {
            return cached
        }

        isDetecting = true
        defer { isDetecting = false }

        // Collect the layers of all empty-named Dock windows.
        var emptyNamedDockLayers: [Int] = []
        if let windowList = windowListProvider() {
            for window in windowList {
                guard (window[kCGWindowOwnerName as String] as? String) == "Dock" else { continue }
                let name = window[kCGWindowName as String] as? String ?? ""
                let layer = window[kCGWindowLayer as String] as? Int ?? 0
                if name.isEmpty {
                    emptyNamedDockLayers.append(layer)
                }
            }
        }

        let isActive = emptyNamedDockLayers.contains(missionControlOverlayLayer)
            && emptyNamedDockLayers.contains { $0 <= dockBarLayerThreshold }

        cachedIsActive = isActive
        lastDetectionTime = now

        // Self-correct a latched-true: if the scan sees no Mission Control
        // windows, clear the latch so a missed close notification can't pin
        // the state true forever. This keeps the latch a *hint* (instant
        // reads within the cache window) rather than a permanent override.
        if !isActive {
            _isMissionControlActive = false
        }

        return isActive
    }

    func executeFixSequence() {
        isSimulating = true

        // Step 1: Simulating Escape (Key code 53)
        postKeyEvent(keyCode: 53, flags: [])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            // Step 2: Simulating Cmd+Space (Key code 49)
            self?.postKeyEvent(keyCode: 49, flags: .maskCommand)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.isSimulating = false
            }
        }
    }

    private func postKeyEvent(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) else { return }
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }

        keyDown.flags = flags
        keyUp.flags = flags

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
