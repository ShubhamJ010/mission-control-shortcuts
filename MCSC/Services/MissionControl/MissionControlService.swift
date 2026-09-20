import Cocoa
import CoreGraphics
import Foundation

/// Detects whether Mission Control (or Exposé) is currently active and can
/// inject a "fix" key sequence when Cmd+Space is pressed while Mission
/// Control has swallowed the Spotlight shortcut.
///
/// On macOS 27, Mission Control composition is owned by `com.apple.WindowManager`
/// (layer 19 overlay), cached for `detectionCacheInterval` so gesture
/// frames never pay for a repeated `CGWindowListCopyWindowInfo` scan.
/// Transitions are automatically broadcast via `onActivated` / `onDeactivated`.
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
    /// Guards `start()` so repeated calls are idempotent.
    private var isStarted = false

    // MARK: - Detection tuning

    /// Layer of Mission Control's full-screen Dock overlay window.
    private let missionControlOverlayLayer = 20
    /// Mission Control also shows the Dock bar at/below this layer.
    private let dockBarLayerThreshold = 18
    /// Layer of Mission Control's full-screen WindowManager overlay window.
    private let windowManagerOverlayLayer = 19
    /// Layer of Mission Control's spaces bar window in WindowManager.
    private let windowManagerSpacesBarLayer = 14

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
                        if event.hasPrefix("com.apple.showdesktop.") || event.contains("stop") {
                            self?.markActive(false)
                        } else if event.contains("start") {
                            self?.markActive(true)
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
        guard _isMissionControlActive != active else { return }
        _isMissionControlActive = active
        cachedIsActive = active
        lastDetectionTime = CACurrentMediaTime()
        AppLogger.missionControl.info("Mission Control active state changed: \(active, privacy: .public)")
        if active {
            onActivated?()
        } else {
            onDeactivated?()
        }
    }

    /// Returns `true` only while Mission Control is open.
    func checkMissionControlActive() -> Bool {
        let now = CACurrentMediaTime()

        // Latch fast-path: trust the notification/AXObserver signal while the
        // cache window is fresh.
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

        // Collect Dock & WindowManager layers
        var emptyNamedDockLayers: [Int] = []
        var hasWindowManagerOverlay = false
        if let windowList = windowListProvider() {
            for window in windowList {
                let owner = window[kCGWindowOwnerName as String] as? String ?? ""
                let layer = window[kCGWindowLayer as String] as? Int ?? 0
                let name = window[kCGWindowName as String] as? String ?? ""
                if owner == "Dock", name.isEmpty {
                    emptyNamedDockLayers.append(layer)
                } else if owner == "WindowManager", layer == windowManagerOverlayLayer {
                    hasWindowManagerOverlay = true
                }
            }
        }

        let isDockMC = emptyNamedDockLayers.contains(missionControlOverlayLayer)
            && emptyNamedDockLayers.contains { $0 <= dockBarLayerThreshold }
        let isActive = hasWindowManagerOverlay || isDockMC

        let previousActive = _isMissionControlActive
        cachedIsActive = isActive
        lastDetectionTime = now
        _isMissionControlActive = isActive

        // Notify state transitions when detected via the window-list scan
        if isActive != previousActive {
            if isActive {
                onActivated?()
            } else {
                onDeactivated?()
            }
        }

        return isActive
    }

    func executeFixSequence() {
        AppLogger.missionControl.info("Executing Mission Control Spotlight fix sequence (Escape -> Cmd+Space)")
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
