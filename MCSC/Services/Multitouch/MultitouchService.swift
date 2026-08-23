import Foundation
import os

/// Snapshot of a single touch point per frame, in normalized trackpad
/// coordinates (0.0–1.0) that are independent of device resolution.
struct TouchPoint {
    /// Stable per-finger identifier across frames within a touch cycle.
    let identifier: Int32
    /// Raw Multitouch state: 2=starting, 3=hovering, 4=touching, 5=staying, 7=lifting.
    let state: Int32
    let normalizedX: Float
    let normalizedY: Float
    /// Contact size, higher = firmer press.
    let size: Float
}

/// Thin wrapper around MultitouchSupport.framework.
/// - Starts/stops the trackpad device(s)
/// - Converts raw `Finger` structs into clean `TouchPoint` values
/// - Forwards frames via `onFrame` (no gesture logic lives here)
///
/// Threading: the framework's C callback may be invoked on an arbitrary
/// framework thread, so frames are re-dispatched to the main queue before
/// reaching consumers.
///
/// Cleanup: `stop()` intentionally defers the underlying `deviceStop` call
/// (see `pendingStop`) because stopping a device synchronously inside the
/// framework's thread can crash. A stale deferred stop is cancelled by the
/// next `start()` (e.g. after sleep/wake) so it cannot tear down freshly
/// re-created devices.
final class MultitouchService {
    typealias FrameCallback = ([TouchPoint], Double) -> Void

    private var devices: [MTDeviceRef] = []
    private var isRunning = false

    /// Set before calling start(). Uses weak-safe pattern via ViewModel.
    var onFrame: FrameCallback?

    /// Static ref to self for C callback (only one instance ever exists)
    fileprivate static var shared: MultitouchService?

    /// A deferred `deviceStop` is scheduled by `stop()` because stopping a
    /// device synchronously can crash the framework's internal thread. We
    /// keep a reference so `start()` can cancel a *stale* stop that was
    /// scheduled before sleep and would otherwise fire *after* we have
    /// already re-created the (same) trackpad devices on wake — silently
    /// tearing them back down and killing gesture delivery.
    private var pendingStop: DispatchWorkItem?

    func start() {
        // Cancel any in-flight deferred stop from a previous stop()/sleep
        // cycle. Without this, a delayed deviceStop scheduled before sleep
        // can fire after we restart the listener on wake and shut down the
        // freshly re-created trackpad devices.
        pendingStop?.cancel()
        pendingStop = nil

        // If we woke up without a preceding sleep notification, the service
        // can be left "running" against a now-stale device handle. Tear it
        // down and rebuild it. stop() defers its deviceStop, but we cancel
        // that pending work immediately afterwards so it can't kill the
        // devices we are about to re-create.
        if isRunning {
            stop()
            pendingStop?.cancel()
            pendingStop = nil
        }

        guard !isRunning else { return }
        beginListening()
    }

    private func beginListening() {
        let bridge = MultitouchBridge.shared
        bridge.ensureLoaded()
        guard bridge.isLoaded else {
            AppLogger.multitouch.error("Cannot start, MultitouchBridge is not loaded")
            return
        }

        MultitouchService.shared = self
        // Fresh gate per listening session: the framework's timestamp base can
        // differ after wake, and a stale high-water mark would drop frames.
        multitouchFrameGate.reset()

        guard let listRef = bridge.deviceCreateList?() else {
            AppLogger.multitouch.error("Failed to create device list")
            return
        }
        let deviceList = listRef.takeRetainedValue() as NSArray

        for device in deviceList {
            let ref = Unmanaged<AnyObject>.passUnretained(device as AnyObject).toOpaque()
            let mtRef = UnsafeMutableRawPointer(ref)
            devices.append(mtRef)
            bridge.registerContactFrameCallback?(mtRef, multitouchCallback)
            bridge.deviceStart?(mtRef, 0)
        }
        isRunning = true
        AppLogger.multitouch.info("Started listening on \(self.devices.count, privacy: .public) trackpad device(s)")
    }

    func stop() {
        guard isRunning else { return }

        // Cancel any deferred stop from an earlier cycle before scheduling
        // a new one (e.g. a quick sleep/wake/sleep).
        pendingStop?.cancel()
        pendingStop = nil

        let bridge = MultitouchBridge.shared
        for device in devices {
            bridge.unregisterContactFrameCallback?(device, multitouchCallback)
        }

        // Delay stop to avoid crash in framework's internal thread, then unload framework
        let devicesToStop = devices
        let work = DispatchWorkItem {
            for device in devicesToStop {
                MultitouchBridge.shared.deviceStop?(device)
            }
            MultitouchBridge.shared.unloadFramework()
        }
        pendingStop = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)

        devices.removeAll()
        isRunning = false
        MultitouchService.shared = nil
        // NOTE: Do NOT null out `onFrame` here. It is configured once by the
        // ViewModel and must survive a stop()/start() cycle so gestures keep
        // working after the system wakes from sleep. (The closure captures
        // the ViewModel weakly, so there is no retain cycle.)
        AppLogger.multitouch.info("Stopped listening")
    }
}

// MARK: - C Callback (free function, bridges back to instance)

/// Shared throttle gate for the framework's C callback. Process-global because
/// the callback is a free function; reset whenever listening starts so a stale
/// pre-sleep timestamp cannot drop fresh post-wake frames.
let multitouchFrameGate = MultitouchFrameGate()

/// Lock-protected timestamp gate used to throttle high-frequency trackpad
/// frames *before* they cross to the main thread.
///
/// The MultitouchSupport framework fires its callback at 60-120 Hz on a
/// framework thread. Previously every raw frame allocated an array + closure
/// and hopped to the main queue, where a second 30 Hz throttle dropped most of
/// them. Gating here removes ~60-90 main-queue wakeups and allocations per
/// second during any trackpad contact. Frames with no active touches are
/// always forwarded so gesture state machines see the end of a touch cycle
/// promptly.
///
/// Thread-safety: the framework callback can run on arbitrary threads, so the
/// last-forwarded timestamp is guarded by a lock. Internal (not private) so
/// `PerformanceTests` can verify the rate-limit behavior directly.
final class MultitouchFrameGate {
    /// Matches the consumer-side throttle in `ShortcutViewModel` (30 Hz).
    static let minimumInterval: Double = 1.0 / 30.0

    private var lastForwardTime: Double = 0
    private var hasAcceptedFrame = false
    private let lock = NSLock()

    /// Returns `true` when a non-empty frame at `timestamp` should be
    /// forwarded; records the timestamp on acceptance.
    func shouldForward(timestamp: Double) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        // Always accept the first frame of a session: the timestamp base is
        // arbitrary (mach uptime), so comparing against the zero-initialized
        // high-water mark could spuriously drop the opening frames.
        guard hasAcceptedFrame else {
            hasAcceptedFrame = true
            lastForwardTime = timestamp
            return true
        }
        guard timestamp - lastForwardTime >= Self.minimumInterval else {
            return false
        }
        lastForwardTime = timestamp
        return true
    }

    func reset() {
        lock.lock()
        lastForwardTime = 0
        hasAcceptedFrame = false
        lock.unlock()
    }
}

private nonisolated func multitouchCallback(
    device _: MTDeviceRef?,
    fingers: UnsafeMutableRawPointer?,
    count: Int32,
    timestamp: Double,
    frame _: Int32
) -> Int32 {
    guard let fingers, count > 0 else { return 0 }

    let fingerPtr = fingers.assumingMemoryBound(to: Finger.self)
    var points: [TouchPoint] = []
    points.reserveCapacity(Int(count))

    for i in 0 ..< Int(count) {
        let f = fingerPtr[i]
        // Only include fingers that are actively touching/hovering
        if f.state >= 4 {
            points.append(TouchPoint(
                identifier: f.identifier,
                state: f.state,
                normalizedX: f.normalizedX,
                normalizedY: f.normalizedY,
                size: f.size
            ))
        }
    }

    // Throttle BEFORE the main-queue hop: only ~30 non-empty frames/s cross
    // threads. Empty frames bypass the gate so recognizers observe finger-lift
    // immediately (end-of-gesture state must not be delayed by up to 33 ms).
    if !points.isEmpty, !multitouchFrameGate.shouldForward(timestamp: timestamp) {
        return 0
    }

    DispatchQueue.main.async {
        if let service = MultitouchService.shared {
            service.onFrame?(points, timestamp)
        }
    }
    return 0
}
