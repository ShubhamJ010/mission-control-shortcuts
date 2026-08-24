import Cocoa
import Foundation
import XCTest

/// Budget-based performance tests guarding MCSC's hot paths.
///
/// These are not micro-benchmarks: budgets are deliberately generous so they
/// pass reliably on any machine, but tight enough that an accidental
/// order-of-magnitude regression (the kind that produces the memory/CPU
/// spikes documented in `docs/PERFORMANCE.md`) fails loudly.
///
/// Covered hot paths:
/// - `MultitouchFrameGate` — pre-thread-hop 30 Hz throttle for trackpad frames.
/// - `ShortcutActionRouter.isShortcutCandidate` — keystroke pre-filter that
///   must stay allocation-free and sub-microsecond (it runs on every keyDown).
/// - `MissionControlService.checkMissionControlActive` — 350 ms detection
///   cache that must short-circuit WindowServer IPC between misses.
/// - `WindowSelectionEngine` — fuzzy match / row-major sort over a realistic
///   Mission Control window list (per-keystroke cost while Exposé is open).
final class PerformanceTests: XCTestCase {
    // MARK: - MultitouchFrameGate (pre-hop throttle)

    /// A 120 Hz stream of non-empty frames must be throttled by the gate
    /// *before* crossing to the main thread (previously every raw frame
    /// allocated and hopped, then was dropped by the consumer-side throttle).
    ///
    /// Asserted as bounds, not an exact count: the accept cadence drifts by
    /// ±1 frame around the 33 ms window due to floating-point timestamps.
    /// Lower bound keeps gestures responsive (≥20 forwards/s); upper bound
    /// enforces the 30 Hz cap (≤61 over 2 s including the first frame).
    func testFrameGateThrottles120HzStreamTo30Hz() {
        let gate = MultitouchFrameGate()
        let interval = 1.0 / 120.0

        var forwarded = 0
        for frame in 0 ..< 240 { // 2 seconds of trackpad frames
            let timestamp = Double(frame) * interval
            if gate.shouldForward(timestamp: timestamp) {
                forwarded += 1
            }
        }

        XCTAssertGreaterThanOrEqual(forwarded, 40, "gate must not over-throttle; gestures need ≥20 forwards/s")
        XCTAssertLessThanOrEqual(forwarded, 61, "120 Hz input must be capped at ~30 forwards/s")
    }

    /// Frames spaced wider than the minimum interval must never be dropped —
    /// the gate only coalesces, it does not delay legitimate slow frames.
    func testFrameGatePassesSlowFramesUnthrottled() {
        let gate = MultitouchFrameGate()

        var allPassed = true
        for frame in 0 ..< 50 {
            let timestamp = Double(frame) * 0.1 // 10 Hz
            allPassed = allPassed && gate.shouldForward(timestamp: timestamp)
        }
        XCTAssertTrue(allPassed, "10 Hz frames are below the 30 Hz cap; none may drop")
    }

    /// The gate is touched from the framework's callback thread; concurrent
    /// calls must stay consistent (no torn timestamps, no crashes) and the
    /// accept count must respect the cap regardless of interleaving.
    func testFrameGateIsSafeUnderConcurrentCalls() {
        let gate = MultitouchFrameGate()
        let queue = DispatchQueue.global()
        let group = DispatchGroup()
        let lock = NSLock()
        var forwarded = 0

        for _ in 0 ..< 8 {
            group.enter()
            queue.async {
                for frame in 0 ..< 300 {
                    // All threads share one monotonic timeline so the cap holds.
                    let timestamp = Double(frame) * (1.0 / 240.0)
                    if gate.shouldForward(timestamp: timestamp) {
                        lock.lock()
                        forwarded += 1
                        lock.unlock()
                    }
                }
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)

        // 8 threads × 300 frames over the same 1.25 s timeline: at most one
        // accept per ~33 ms window is legal (~38); assert a sane upper bound.
        XCTAssertLessThanOrEqual(forwarded, 40)
    }

    /// The gate itself must be negligible overhead — it runs inside the
    /// framework's C callback up to 120×/s.
    func testFrameGateThroughput() {
        let gate = MultitouchFrameGate()
        let iterations = 100_000

        let start = CACurrentMediaTime()
        var accepted = 0
        for i in 0 ..< iterations {
            if gate.shouldForward(timestamp: Double(i) * 0.001) {
                accepted += 1
            }
        }
        let elapsed = CACurrentMediaTime() - start

        XCTAssertGreaterThan(accepted, 0)
        XCTAssertLessThan(elapsed, 0.5, "100k gate checks took \(elapsed)s; throttle must stay O(ns)")
    }

    // MARK: - Keystroke pre-filter

    func testShortcutCandidateRejectsPlainTypingAndUntrackedKeys() {
        let cmd = CGEventFlags.maskCommand

        // Plain typing without Cmd can never route.
        XCTAssertFalse(ShortcutActionRouter.isShortcutCandidate(keyCode: 0, flags: []))
        XCTAssertFalse(ShortcutActionRouter.isShortcutCandidate(keyCode: ShortcutActionRouter.kKeyW, flags: []))
        // Untracked key even with Cmd.
        XCTAssertFalse(ShortcutActionRouter.isShortcutCandidate(keyCode: 7 /* X */, flags: cmd))
        // Cmd+Ctrl / Cmd+Option combos are excluded by the router contract.
        XCTAssertFalse(ShortcutActionRouter.isShortcutCandidate(
            keyCode: ShortcutActionRouter.kKeyW, flags: [.maskCommand, .maskControl]
        ))
        XCTAssertFalse(ShortcutActionRouter.isShortcutCandidate(
            keyCode: ShortcutActionRouter.kKeyW, flags: [.maskCommand, .maskAlternate]
        ))
        // Tracked keys with Cmd must pass.
        XCTAssertTrue(ShortcutActionRouter.isShortcutCandidate(
            keyCode: ShortcutActionRouter.kKeyW, flags: cmd
        ))
        XCTAssertTrue(ShortcutActionRouter.isShortcutCandidate(
            keyCode: ShortcutActionRouter.kKeySpace, flags: cmd
        ))
        XCTAssertTrue(ShortcutActionRouter.isShortcutCandidate(
            keyCode: ShortcutActionRouter.kKeyRight, flags: [.maskCommand, .maskShift]
        ))

        // Every kKey constant must be admitted — guards against someone adding
        // a new shortcut constant but forgetting the whitelist.
        let constants: [Int64] = [
            ShortcutActionRouter.kKeyW, ShortcutActionRouter.kKeyQ,
            ShortcutActionRouter.kKeyM, ShortcutActionRouter.kKeyH,
            ShortcutActionRouter.kKeyF, ShortcutActionRouter.kKeyT,
            ShortcutActionRouter.kKeyN, ShortcutActionRouter.kKeySpace,
            ShortcutActionRouter.kKeyD,
            ShortcutActionRouter.kKeyA, ShortcutActionRouter.kKeyR,
            ShortcutActionRouter.kKeyL, ShortcutActionRouter.kKeyS,
            ShortcutActionRouter.kKeyRight, ShortcutActionRouter.kKeyLeft
        ]
        for key in constants {
            XCTAssertTrue(
                ShortcutActionRouter.isShortcutCandidate(keyCode: key, flags: cmd),
                "key code \(key) must remain whitelisted"
            )
        }
    }

    /// Runs on EVERY keyDown system-wide; must stay far below a microsecond.
    func testShortcutCandidateFilterThroughput() {
        let keyCodes: [Int64] = [0, 13, 12, 46, 49, 124, 7]
        let flagSet: [CGEventFlags] = [[], .maskCommand, .maskCommand, [], .maskCommand, .maskCommand, []]
        let iterations = 100_000

        let start = CACurrentMediaTime()
        var hits = 0
        for i in 0 ..< iterations {
            if ShortcutActionRouter.isShortcutCandidate(
                keyCode: keyCodes[i % keyCodes.count],
                flags: flagSet[i % flagSet.count]
            ) {
                hits += 1
            }
        }
        let elapsed = CACurrentMediaTime() - start

        XCTAssertGreaterThan(hits, 0)
        XCTAssertLessThan(elapsed, 0.25, "100k filter calls took \(elapsed)s; pre-filter must be ~free")
    }

    // MARK: - Mission Control detection cache

    /// After the first (real IPC) call, repeated checks within the 350 ms
    /// cache window must short-circuit without another window-list scan.
    /// Measured as wall time: the cached path is a media-time read + branch,
    /// while a re-scan costs milliseconds per call.
    @MainActor
    func testDetectionCacheShortCircuitsRepeatedChecks() {
        let service = MissionControlService()
        _ = service.checkMissionControlActive() // warm the cache (real IPC)

        let iterations = 10000
        let start = CACurrentMediaTime()
        for _ in 0 ..< iterations {
            _ = service.checkMissionControlActive()
        }
        let elapsed = CACurrentMediaTime() - start

        service.stop()
        // 10k cached reads must complete near-instantly; even one extra
        // CGWindowListCopyWindowInfo per call would blow this budget.
        XCTAssertLessThan(elapsed, 0.2, "\(iterations) cached checks took \(elapsed)s; cache is not short-circuiting")
    }

    // MARK: - WindowSelectionEngine (per-keystroke cost in Exposé)

    private func makeWindowList(count: Int) -> [[String: Any]] {
        let owners = ["Safari", "Xcode", "Mail", "Finder", "Terminal",
                      "Slack", "Notes", "Preview", "Music", "Calendar"]

        var windows: [[String: Any]] = []
        windows.reserveCapacity(count)
        for i in 0 ..< count {
            var bounds: [String: CGFloat] = [:]
            bounds["X"] = CGFloat(i * 30)
            bounds["Y"] = CGFloat(i * 20)
            bounds["Width"] = CGFloat(400 + i)
            bounds["Height"] = CGFloat(300 + i)

            var window: [String: Any] = [:]
            window[kCGWindowOwnerName as String] = owners[i % owners.count]
            window[kCGWindowBounds as String] = bounds
            window[kCGWindowNumber as String] = i
            windows.append(window)
        }
        return windows
    }

    /// Typing-to-select recomputes matches once per keystroke over the live
    /// window list. With ~60 windows this must stay well under a millisecond,
    /// otherwise fast typists queue work on the main thread while Exposé is open.
    func testFuzzyMatchThroughputOnRealisticWindowList() {
        let windows = makeWindowList(count: 60)
        let queries = ["sa", "saf", "xcod", "mail", "term", "z"]
        let iterations = 5000

        let start = CACurrentMediaTime()
        var totalMatches = 0
        for i in 0 ..< iterations {
            totalMatches += WindowSelectionEngine.fuzzyMatch(
                query: queries[i % queries.count], in: windows
            ).count
        }
        let elapsed = CACurrentMediaTime() - start

        XCTAssertGreaterThan(totalMatches, 0)
        XCTAssertLessThan(elapsed, 2.0, "\(iterations) fuzzy matches over 60 windows took \(elapsed)s")
    }

    /// Tab cycling with an empty query sorts the whole window list per
    /// keypress; same budget rationale as `testFuzzyMatchThroughput…`.
    func testRowMajorSortThroughputOnRealisticWindowList() {
        let windows = makeWindowList(count: 60)
        let iterations = 5000

        let start = CACurrentMediaTime()
        var totalSorted = 0
        for _ in 0 ..< iterations {
            totalSorted += WindowSelectionEngine.rowMajorSorted(in: windows).count
        }
        let elapsed = CACurrentMediaTime() - start

        XCTAssertEqual(totalSorted, iterations * 60)
        XCTAssertLessThan(elapsed, 2.0, "\(iterations) row-major sorts took \(elapsed)s")
    }
}
