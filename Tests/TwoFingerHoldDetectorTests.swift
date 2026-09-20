import Foundation
import XCTest

final class TwoFingerHoldDetectorTests: XCTestCase {
    private func makeTouch(id: Int32, x: Float, y: Float) -> TouchPoint {
        TouchPoint(identifier: id, state: 4, normalizedX: x, normalizedY: y, size: 1.0)
    }

    func testHoldActivatesAfterThreshold() {
        var detector = TwoFingerHoldDetector()
        detector.config.holdDuration = 0.4
        detector.config.maxMovement = 0.02

        let t0 = [makeTouch(id: 1, x: 0.5, y: 0.5), makeTouch(id: 2, x: 0.6, y: 0.5)]

        XCTAssertFalse(detector.processFrame(t0, timestamp: 0.0))
        XCTAssertFalse(detector.isHoldActive)

        XCTAssertFalse(detector.processFrame(t0, timestamp: 0.2))
        XCTAssertFalse(detector.isHoldActive)

        // At 0.4s, transitions to held and returns true (just activated)
        XCTAssertTrue(detector.processFrame(t0, timestamp: 0.4))
        XCTAssertTrue(detector.isHoldActive)

        // Subsequent frames while held return false but hold remains active
        XCTAssertFalse(detector.processFrame(t0, timestamp: 0.5))
        XCTAssertTrue(detector.isHoldActive)
    }

    func testHoldAbortsOnMovementBeforeThreshold() {
        var detector = TwoFingerHoldDetector()
        detector.config.holdDuration = 0.4
        detector.config.maxMovement = 0.02

        let t0 = [makeTouch(id: 1, x: 0.5, y: 0.5), makeTouch(id: 2, x: 0.6, y: 0.5)]
        XCTAssertFalse(detector.processFrame(t0, timestamp: 0.0))

        // Finger 1 moves by 0.05 (> 0.02)
        let t1 = [makeTouch(id: 1, x: 0.55, y: 0.5), makeTouch(id: 2, x: 0.6, y: 0.5)]
        XCTAssertFalse(detector.processFrame(t1, timestamp: 0.2))
        XCTAssertFalse(detector.isHoldActive)

        // At 0.4s, hold is not active because it aborted to idle
        XCTAssertFalse(detector.processFrame(t1, timestamp: 0.4))
        XCTAssertFalse(detector.isHoldActive)
    }

    func testHoldAbortsOnFingerLiftBeforeThreshold() {
        var detector = TwoFingerHoldDetector()
        let t0 = [makeTouch(id: 1, x: 0.5, y: 0.5), makeTouch(id: 2, x: 0.6, y: 0.5)]
        XCTAssertFalse(detector.processFrame(t0, timestamp: 0.0))

        // 1 finger lifted
        let t1 = [makeTouch(id: 1, x: 0.5, y: 0.5)]
        XCTAssertFalse(detector.processFrame(t1, timestamp: 0.2))
        XCTAssertFalse(detector.isHoldActive)
    }

    func testHoldAbortsOnThreeFingers() {
        var detector = TwoFingerHoldDetector()
        let t0 = [makeTouch(id: 1, x: 0.5, y: 0.5), makeTouch(id: 2, x: 0.6, y: 0.5)]
        XCTAssertFalse(detector.processFrame(t0, timestamp: 0.0))

        // 3rd finger added
        let t1 = [makeTouch(id: 1, x: 0.5, y: 0.5), makeTouch(id: 2, x: 0.6, y: 0.5), makeTouch(id: 3, x: 0.7, y: 0.5)]
        XCTAssertFalse(detector.processFrame(t1, timestamp: 0.2))
        XCTAssertFalse(detector.isHoldActive)
    }

    func testResetClearsState() {
        var detector = TwoFingerHoldDetector()
        let t0 = [makeTouch(id: 1, x: 0.5, y: 0.5), makeTouch(id: 2, x: 0.6, y: 0.5)]
        _ = detector.processFrame(t0, timestamp: 0.0)
        _ = detector.processFrame(t0, timestamp: 0.4)
        XCTAssertTrue(detector.isHoldActive)

        detector.reset()
        XCTAssertFalse(detector.isHoldActive)
        XCTAssertEqual(detector.state, .idle)
    }

    func testCustomHoldDuration() {
        var detector = TwoFingerHoldDetector()
        detector.config.holdDuration = 0.2

        let t0 = [makeTouch(id: 1, x: 0.5, y: 0.5), makeTouch(id: 2, x: 0.6, y: 0.5)]
        XCTAssertFalse(detector.processFrame(t0, timestamp: 0.0))
        XCTAssertTrue(detector.processFrame(t0, timestamp: 0.2))
        XCTAssertTrue(detector.isHoldActive)
    }

    func testHoldLatchingGracePeriodAfterFingerLift() {
        var detector = TwoFingerHoldDetector()
        detector.config.holdDuration = 0.4
        detector.config.latchDuration = 0.8

        let t0 = [makeTouch(id: 1, x: 0.5, y: 0.5), makeTouch(id: 2, x: 0.6, y: 0.5)]
        _ = detector.processFrame(t0, timestamp: 0.0)
        _ = detector.processFrame(t0, timestamp: 0.4)
        XCTAssertTrue(detector.isHoldActive)

        // Fingers lift (touches become empty)
        detector.handleTouchesEnded(timestamp: 0.45)
        XCTAssertTrue(detector.isHoldActive, "Hold modifier must remain latched within latchDuration")

        // 0.5s later (within 0.8s latchDuration)
        _ = detector.processFrame([], timestamp: 0.95)
        XCTAssertTrue(detector.isHoldActive)

        // After latchDuration expires (> 0.8s after 0.45s = 1.25s)
        _ = detector.processFrame([], timestamp: 1.30)
        XCTAssertFalse(detector.isHoldActive, "Hold modifier must expire after latchDuration")
    }

    func testCancelForCurrentTouchSessionPreventsHoldUntilFingersLift() {
        var detector = TwoFingerHoldDetector()
        detector.config.holdDuration = 0.4

        let t0 = [makeTouch(id: 1, x: 0.5, y: 0.5), makeTouch(id: 2, x: 0.6, y: 0.5)]
        _ = detector.processFrame(t0, timestamp: 0.0)

        // Mouse click occurs at 0.1s -> cancelForCurrentTouchSession()
        detector.cancelForCurrentTouchSession()
        XCTAssertFalse(detector.isHoldActive)
        XCTAssertEqual(detector.state, .cancelled)

        // Fingers linger stationary past 0.4s threshold
        let activated = detector.processFrame(t0, timestamp: 0.5)
        XCTAssertFalse(activated, "Hold must NOT activate while touch session is cancelled")
        XCTAssertFalse(detector.isHoldActive)
        XCTAssertEqual(detector.state, .cancelled)

        // Still cancelled at 1.0s
        _ = detector.processFrame(t0, timestamp: 1.0)
        XCTAssertFalse(detector.isHoldActive)

        // Fingers lift (touches drop to empty)
        _ = detector.processFrame([], timestamp: 1.1)
        detector.handleTouchesEnded(timestamp: 1.1)
        XCTAssertEqual(detector.state, .idle)
        XCTAssertFalse(detector.isHoldActive)

        // Next new touch session can detect hold normally
        let t1 = [makeTouch(id: 3, x: 0.5, y: 0.5), makeTouch(id: 4, x: 0.6, y: 0.5)]
        _ = detector.processFrame(t1, timestamp: 2.0)
        let newlyActivated = detector.processFrame(t1, timestamp: 2.4)
        XCTAssertTrue(newlyActivated)
        XCTAssertTrue(detector.isHoldActive)
    }
}
