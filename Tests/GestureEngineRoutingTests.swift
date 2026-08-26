import Foundation
import XCTest

final class GestureEngineRoutingTests: XCTestCase {
    private var engine: GestureEngine!
    private var pinchRecognizer: PinchInRecognizer!
    private var swipeLeftRecognizer: TwoFingerSwipeLeftRecognizer!
    private var swipeRightRecognizer: TwoFingerSwipeRightRecognizer!
    private var swipeRecognizer: SwipeRecognizer!
    private var tapRecognizer: TwoFingerDoubleTapRecognizer!
    private var recognizedGestures: [GestureResult] = []

    override func setUp() {
        super.setUp()
        engine = GestureEngine()
        recognizedGestures = []

        tapRecognizer = TwoFingerDoubleTapRecognizer()
        tapRecognizer.isCmdHeld = { false }
        tapRecognizer.isEnabled = { true }
        engine.register(tapRecognizer)

        pinchRecognizer = PinchInRecognizer()
        pinchRecognizer.isCmdHeld = { false }
        pinchRecognizer.isEnabled = { true }
        engine.register(pinchRecognizer)

        swipeLeftRecognizer = TwoFingerSwipeLeftRecognizer()
        swipeLeftRecognizer.isCmdHeld = { false }
        swipeLeftRecognizer.isEnabled = { true }
        engine.register(swipeLeftRecognizer)

        swipeRightRecognizer = TwoFingerSwipeRightRecognizer()
        swipeRightRecognizer.isCmdHeld = { false }
        swipeRightRecognizer.isEnabled = { true }
        engine.register(swipeRightRecognizer)

        swipeRecognizer = SwipeRecognizer()
        swipeRecognizer.isCmdHeld = { false }
        swipeRecognizer.isEnabled = { true }
        swipeRecognizer.isSwipeUpEnabled = { true }
        swipeRecognizer.isSwipeDownEnabled = { true }
        engine.register(swipeRecognizer)

        engine.onGestureRecognized = { [weak self] gesture in
            self?.recognizedGestures.append(gesture)
        }
    }

    override func tearDown() {
        engine = nil
        pinchRecognizer = nil
        swipeLeftRecognizer = nil
        swipeRightRecognizer = nil
        swipeRecognizer = nil
        tapRecognizer = nil
        recognizedGestures = []
        super.tearDown()
    }

    func testPinchInTakesPriorityOverSwipeWhenFingersPinch() {
        // Initial touch: 2 fingers at x=0.3 and x=0.7 (distance = 0.4)
        let t1 = TouchPoint(identifier: 1, state: 4, normalizedX: 0.3, normalizedY: 0.5, size: 1.0)
        let t2 = TouchPoint(identifier: 2, state: 4, normalizedX: 0.7, normalizedY: 0.5, size: 1.0)
        engine.processFrame([t1, t2], timestamp: 1.0)

        // Pinch together: fingers move closer (distance = 0.16, 60% decrease) while slightly shifting left
        let t1Next = TouchPoint(identifier: 1, state: 4, normalizedX: 0.42, normalizedY: 0.5, size: 1.0)
        let t2Next = TouchPoint(identifier: 2, state: 4, normalizedX: 0.58, normalizedY: 0.5, size: 1.0)
        engine.processFrame([t1Next, t2Next], timestamp: 1.1)

        XCTAssertEqual(recognizedGestures.count, 1, "Exactly one gesture should be recognized")
        if let first = recognizedGestures.first {
            switch first {
            case .pinchIn:
                break // Success
            default:
                XCTFail("Expected .pinchIn to win over swipe, got: \(first)")
            }
        }
    }

    func testCmdSwipeLeftTriggeredWhenFingersSlideLeftWithCmd() {
        swipeLeftRecognizer.isCmdHeld = { true }

        // Start touch
        let t1 = TouchPoint(identifier: 1, state: 4, normalizedX: 0.5, normalizedY: 0.5, size: 1.0)
        let t2 = TouchPoint(identifier: 2, state: 4, normalizedX: 0.7, normalizedY: 0.5, size: 1.0)
        engine.processFrame([t1, t2], timestamp: 1.0)

        // Slide left: deltaX = -0.15 (crossing swipeThreshold of 0.08) with constant finger distance (0.2)
        let t1Moved = TouchPoint(identifier: 1, state: 4, normalizedX: 0.35, normalizedY: 0.5, size: 1.0)
        let t2Moved = TouchPoint(identifier: 2, state: 4, normalizedX: 0.55, normalizedY: 0.5, size: 1.0)
        engine.processFrame([t1Moved, t2Moved], timestamp: 1.1)

        XCTAssertEqual(recognizedGestures.count, 1)
        if let first = recognizedGestures.first {
            switch first {
            case .cmdSwipeLeft:
                break // Success
            default:
                XCTFail("Expected .cmdSwipeLeft, got: \(first)")
            }
        }
    }

    func testCmdSwipeRightTriggeredWhenFingersSlideRightWithCmd() {
        swipeRightRecognizer.isCmdHeld = { true }

        // Start touch
        let t1 = TouchPoint(identifier: 1, state: 4, normalizedX: 0.3, normalizedY: 0.5, size: 1.0)
        let t2 = TouchPoint(identifier: 2, state: 4, normalizedX: 0.5, normalizedY: 0.5, size: 1.0)
        engine.processFrame([t1, t2], timestamp: 1.0)

        // Slide right: deltaX = +0.15 (crossing swipeThreshold of 0.08) with constant finger distance (0.2)
        let t1Moved = TouchPoint(identifier: 1, state: 4, normalizedX: 0.45, normalizedY: 0.5, size: 1.0)
        let t2Moved = TouchPoint(identifier: 2, state: 4, normalizedX: 0.65, normalizedY: 0.5, size: 1.0)
        engine.processFrame([t1Moved, t2Moved], timestamp: 1.1)

        XCTAssertEqual(recognizedGestures.count, 1)
        if let first = recognizedGestures.first {
            switch first {
            case .cmdSwipeRight:
                break // Success
            default:
                XCTFail("Expected .cmdSwipeRight, got: \(first)")
            }
        }
    }

    func testThreeFingerTouchPoisoningSuppressesGesture() {
        // 3 fingers touch
        let t1 = TouchPoint(identifier: 1, state: 4, normalizedX: 0.2, normalizedY: 0.5, size: 1.0)
        let t2 = TouchPoint(identifier: 2, state: 4, normalizedX: 0.5, normalizedY: 0.5, size: 1.0)
        let t3 = TouchPoint(identifier: 3, state: 4, normalizedX: 0.8, normalizedY: 0.5, size: 1.0)
        engine.processFrame([t1, t2, t3], timestamp: 1.0)

        // Next frame: one finger lifts, leaving 2 fingers that pinch
        let t1Next = TouchPoint(identifier: 1, state: 4, normalizedX: 0.45, normalizedY: 0.5, size: 1.0)
        let t2Next = TouchPoint(identifier: 2, state: 4, normalizedX: 0.55, normalizedY: 0.5, size: 1.0)
        engine.processFrame([t1Next, t2Next], timestamp: 1.1)

        XCTAssertEqual(
            recognizedGestures.count,
            0,
            "Poisoned touch cycle must not fire any gesture until all fingers lift"
        )

        // All fingers lift
        engine.processFrame([], timestamp: 1.2)

        // New clean 2-finger pinch
        let clean1 = TouchPoint(identifier: 1, state: 4, normalizedX: 0.3, normalizedY: 0.5, size: 1.0)
        let clean2 = TouchPoint(identifier: 2, state: 4, normalizedX: 0.7, normalizedY: 0.5, size: 1.0)
        engine.processFrame([clean1, clean2], timestamp: 1.3)

        let clean1Pinch = TouchPoint(identifier: 1, state: 4, normalizedX: 0.45, normalizedY: 0.5, size: 1.0)
        let clean2Pinch = TouchPoint(identifier: 2, state: 4, normalizedX: 0.55, normalizedY: 0.5, size: 1.0)
        engine.processFrame([clean1Pinch, clean2Pinch], timestamp: 1.4)

        XCTAssertEqual(recognizedGestures.count, 1, "After full lift, new clean gesture should fire")
    }

    func testAwaitingLiftGuardPreventsMultipleTriggersWithoutLift() {
        // First pinch-in gesture fires
        let t1 = TouchPoint(identifier: 1, state: 4, normalizedX: 0.2, normalizedY: 0.5, size: 1.0)
        let t2 = TouchPoint(identifier: 2, state: 4, normalizedX: 0.8, normalizedY: 0.5, size: 1.0)
        engine.processFrame([t1, t2], timestamp: 1.0)

        let t1Pinched = TouchPoint(identifier: 1, state: 4, normalizedX: 0.45, normalizedY: 0.5, size: 1.0)
        let t2Pinched = TouchPoint(identifier: 2, state: 4, normalizedX: 0.55, normalizedY: 0.5, size: 1.0)
        engine.processFrame([t1Pinched, t2Pinched], timestamp: 1.1)

        XCTAssertEqual(recognizedGestures.count, 1)

        // Continuous frames while fingers are still down moving
        let t1More = TouchPoint(identifier: 1, state: 4, normalizedX: 0.48, normalizedY: 0.5, size: 1.0)
        let t2More = TouchPoint(identifier: 2, state: 4, normalizedX: 0.52, normalizedY: 0.5, size: 1.0)
        engine.processFrame([t1More, t2More], timestamp: 1.2)
        engine.processFrame([t1More, t2More], timestamp: 1.3)

        XCTAssertEqual(recognizedGestures.count, 1, "Subsequent frames without finger lift must be ignored")
    }

    func testSwipeUpTriggeredWhenFingersSlideUp() {
        // Start touch at mid Y = 0.4
        let t1 = TouchPoint(identifier: 1, state: 4, normalizedX: 0.4, normalizedY: 0.4, size: 1.0)
        let t2 = TouchPoint(identifier: 2, state: 4, normalizedX: 0.6, normalizedY: 0.4, size: 1.0)
        engine.processFrame([t1, t2], timestamp: 1.0)

        // Slide upward toward screen: mid Y = 0.6 (deltaY = +0.2 > 0.08 swipeThreshold)
        let t1Moved = TouchPoint(identifier: 1, state: 4, normalizedX: 0.4, normalizedY: 0.6, size: 1.0)
        let t2Moved = TouchPoint(identifier: 2, state: 4, normalizedX: 0.6, normalizedY: 0.6, size: 1.0)
        engine.processFrame([t1Moved, t2Moved], timestamp: 1.1)

        XCTAssertEqual(recognizedGestures.count, 1)
        if let first = recognizedGestures.first {
            switch first {
            case .swipeUp:
                break // Success
            default:
                XCTFail("Expected .swipeUp when deltaY > 0, got: \(first)")
            }
        }
    }

    func testSwipeDownTriggeredWhenFingersSlideDown() {
        // Start touch at mid Y = 0.6
        let t1 = TouchPoint(identifier: 1, state: 4, normalizedX: 0.4, normalizedY: 0.6, size: 1.0)
        let t2 = TouchPoint(identifier: 2, state: 4, normalizedX: 0.6, normalizedY: 0.6, size: 1.0)
        engine.processFrame([t1, t2], timestamp: 1.0)

        // Slide downward toward user: mid Y = 0.4 (deltaY = -0.2 < -0.08 swipeThreshold)
        let t1Moved = TouchPoint(identifier: 1, state: 4, normalizedX: 0.4, normalizedY: 0.4, size: 1.0)
        let t2Moved = TouchPoint(identifier: 2, state: 4, normalizedX: 0.6, normalizedY: 0.4, size: 1.0)
        engine.processFrame([t1Moved, t2Moved], timestamp: 1.1)

        XCTAssertEqual(recognizedGestures.count, 1)
        if let first = recognizedGestures.first {
            switch first {
            case .swipeDown:
                break // Success
            default:
                XCTFail("Expected .swipeDown when deltaY < 0, got: \(first)")
            }
        }
    }

    func testCmdSwipeUpTriggeredWhenFingersSlideUpWithCmd() {
        swipeRecognizer.isCmdHeld = { true }

        let t1 = TouchPoint(identifier: 1, state: 4, normalizedX: 0.4, normalizedY: 0.3, size: 1.0)
        let t2 = TouchPoint(identifier: 2, state: 4, normalizedX: 0.6, normalizedY: 0.3, size: 1.0)
        engine.processFrame([t1, t2], timestamp: 1.0)

        let t1Moved = TouchPoint(identifier: 1, state: 4, normalizedX: 0.4, normalizedY: 0.55, size: 1.0)
        let t2Moved = TouchPoint(identifier: 2, state: 4, normalizedX: 0.6, normalizedY: 0.55, size: 1.0)
        engine.processFrame([t1Moved, t2Moved], timestamp: 1.1)

        XCTAssertEqual(recognizedGestures.count, 1)
        if let first = recognizedGestures.first {
            switch first {
            case .cmdSwipeUp:
                break // Success
            default:
                XCTFail("Expected .cmdSwipeUp when deltaY > 0 with Cmd held, got: \(first)")
            }
        }
    }

    func testCmdSwipeDownTriggeredWhenFingersSlideDownWithCmd() {
        swipeRecognizer.isCmdHeld = { true }

        let t1 = TouchPoint(identifier: 1, state: 4, normalizedX: 0.4, normalizedY: 0.7, size: 1.0)
        let t2 = TouchPoint(identifier: 2, state: 4, normalizedX: 0.6, normalizedY: 0.7, size: 1.0)
        engine.processFrame([t1, t2], timestamp: 1.0)

        let t1Moved = TouchPoint(identifier: 1, state: 4, normalizedX: 0.4, normalizedY: 0.45, size: 1.0)
        let t2Moved = TouchPoint(identifier: 2, state: 4, normalizedX: 0.6, normalizedY: 0.45, size: 1.0)
        engine.processFrame([t1Moved, t2Moved], timestamp: 1.1)

        XCTAssertEqual(recognizedGestures.count, 1)
        if let first = recognizedGestures.first {
            switch first {
            case .cmdSwipeDown:
                break // Success
            default:
                XCTFail("Expected .cmdSwipeDown when deltaY < 0 with Cmd held, got: \(first)")
            }
        }
    }
}
