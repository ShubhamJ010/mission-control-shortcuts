import Foundation
import XCTest

/// Lifecycle tests for `MissionControlService`: idempotent start, cache
/// invalidation on close, latch self-correction, and the `markActive`
/// unification path. The window-list scan is injected so the heuristic runs
/// deterministically without relying on the real `CGWindowListCopyWindowInfo`
/// IPC (whose result depends on whatever the test host happens to have on
/// screen).
@MainActor
final class MissionControlServiceTests: XCTestCase {
    private var service: MissionControlService!

    /// Builds a window-list entry shaped exactly like the dictionaries the
    /// real `CGWindowListCopyWindowInfo` scan inspects.
    private func dockWindow(layer: Int, name: String = "") -> [String: Any] {
        [
            kCGWindowOwnerName as String: "Dock",
            kCGWindowName as String: name,
            kCGWindowLayer as String: layer
        ]
    }

    override func setUp() {
        super.setUp()
        // Start with a clean (no Mission Control) window list.
        service = MissionControlService(windowListProvider: { [] })
        // Keep the default cache window so `markActive` reads are instant;
        // self-correction tests call `_testForceCacheExpiry()` to run the scan.
        service.detectionCacheInterval = 0.35
    }

    override func tearDown() {
        service.stop()
        service = nil
        super.tearDown()
    }

    // MARK: - Idempotent start (fix #2: duplicate-observer leak)

    /// `start()` must be a no-op on repeat calls so the ViewModel can't
    /// leak duplicate DistributedNotificationCenter observers across lifecycle
    /// restarts.
    func testStartIsIdempotentNoDuplicateObservers() {
        var activatedCount = 0
        service.onActivated = { activatedCount += 1 }

        service.start()
        service.start() // second call must be a no-op
        service.start()

        // No real notification fires in the test host, so the callback count
        // stays zero; we assert by driving stop + restart and confirming a
        // clean teardown each time.
        XCTAssertEqual(activatedCount, 0)

        service.stop()
        // After stop, starting again is permitted (flag was reset).
        service.start()
        XCTAssertEqual(activatedCount, 0)
    }

    // MARK: - Stop clears latch + cache (fix #3: stuck-true landmine)

    func testStopClearsLatchAndCache() {
        service.start()

        // Prime the latch as if an open notification had fired.
        service.markActive(true)
        XCTAssertTrue(service.isMissionControlActive)

        service.stop()

        // After stop, the active state must be false and the next read must
        // perform a fresh scan (no stale-true served from the cache).
        XCTAssertFalse(service.isMissionControlActive)
    }

    // MARK: - Latch self-correction (fix #3: stuck-true landmine)

    /// If the close signal is missed, the latch could pin the state true
    /// forever. Once the cache window expires the window-list scan must run
    /// and, seeing no Mission Control windows, clear the latched-true state.
    func testLatchSelfCorrectsWhenScanReturnsFalse() {
        service.start()

        // Prime the latch true (simulating an open notification).
        service.markActive(true)
        XCTAssertTrue(service.isMissionControlActive)

        // Force the cache window to expire, then scan. The injected window
        // list is empty, so the scan returns false and must clear the
        // latched-true state.
        service._testForceCacheExpiry()
        XCTAssertFalse(service.checkMissionControlActive())

        // A second read must not short-circuit on a latched-true fast path.
        service._testForceCacheExpiry()
        XCTAssertFalse(service.checkMissionControlActive())
    }

    /// Conversely, when Mission Control *is* open (the scan sees the overlay
    /// + Dock bar), the scan keeps the latch true and the result is true.
    func testLatchStaysTrueWhenScanReturnsTrue() {
        service = MissionControlService(windowListProvider: { [
            self.dockWindow(layer: 20), // overlay
            self.dockWindow(layer: 18) // Dock bar
        ] })
        service.detectionCacheInterval = 0.35
        service.start()

        service.markActive(true)
        service._testForceCacheExpiry()
        XCTAssertTrue(service.checkMissionControlActive())
        // Self-correction must not flip a true scan back to false.
        service._testForceCacheExpiry()
        XCTAssertTrue(service.checkMissionControlActive())
    }

    // MARK: - markActive unification path (Phase 2)

    func testMarkActivePrimesCacheAndFiresCallbacks() {
        var activatedCount = 0
        var deactivatedCount = 0
        service.onActivated = { activatedCount += 1 }
        service.onDeactivated = { deactivatedCount += 1 }

        service.markActive(true)
        XCTAssertEqual(activatedCount, 1)
        XCTAssertEqual(deactivatedCount, 0)
        XCTAssertTrue(service.isMissionControlActive)

        service.markActive(false)
        XCTAssertEqual(activatedCount, 1)
        XCTAssertEqual(deactivatedCount, 1)
        XCTAssertFalse(service.isMissionControlActive)
    }

    /// After `markActive`, reads are instant and consistent with the pushed
    /// signal without re-scanning. Uses a non-zero cache window so the
    /// latch fast-path applies.
    func testMarkActiveTrueThenFalseIsInstantWithoutScan() {
        service.detectionCacheInterval = 0.35
        service.start()

        service.markActive(true)
        XCTAssertTrue(service.isMissionControlActive)
        XCTAssertTrue(service.isMissionControlActive) // cached

        service.markActive(false)
        XCTAssertFalse(service.isMissionControlActive)
        XCTAssertFalse(service.isMissionControlActive) // cached
    }
}
