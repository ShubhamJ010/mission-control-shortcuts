import Foundation

/// Detects a stationary two-finger hold on the trackpad.
///
/// Functions as a Command (⌘) modifier when sustained, enabling
/// subsequent gestures (swipes, pinches, double taps) to emit their ⌘-modified
/// variants. Latching maintains the modifier for a grace window after release
/// so gestures like double-tap and pinch can execute cleanly.
struct TwoFingerHoldDetector {
    struct Config: Equatable {
        /// Minimum duration (in seconds) the two fingers must remain stationary to activate hold.
        var holdDuration: Double = 0.4

        /// Maximum displacement (normalized 0.0–1.0) allowed for either finger during the hold phase.
        var maxMovement: Float = 0.02

        /// Grace period (in seconds) after release where the Command modifier remains latched.
        /// Allows follow-up gestures like Two-Finger Double Tap and Pinch to be chained without maintaining contact.
        var latchDuration: Double = 0.8
    }

    enum State: Equatable {
        case idle
        case pending(
            finger1ID: Int32,
            finger2ID: Int32,
            startX1: Float,
            startY1: Float,
            startX2: Float,
            startY2: Float,
            startTime: Double
        )
        case held(
            finger1ID: Int32,
            finger2ID: Int32
        )
        case latched(
            releaseTime: Double
        )
    }

    var config = Config()
    private(set) var state: State = .idle
    private var lastTimestamp: Double = 0

    /// `true` when two fingers have met the hold duration and remain touching or are within the latch grace period.
    var isHoldActive: Bool {
        switch state {
        case .held:
            return true
        case let .latched(releaseTime):
            let now = lastTimestamp > 0 ? lastTimestamp : ProcessInfo.processInfo.systemUptime
            return (now - releaseTime) <= config.latchDuration
        case .idle, .pending:
            return false
        }
    }

    /// Process a multitouch frame.
    /// - Returns: `true` if the hold state *just* transitioned from pending to held in this frame (useful for haptic & visual feedback).
    mutating func processFrame(_ touches: [TouchPoint], timestamp: Double) -> Bool {
        lastTimestamp = timestamp
        if case let .latched(releaseTime) = state, timestamp - releaseTime > config.latchDuration {
            state = .idle
        }
        switch state {
        case .idle:
            if touches.count == 2 {
                let f1 = touches[0]
                let f2 = touches[1]
                state = .pending(
                    finger1ID: f1.identifier,
                    finger2ID: f2.identifier,
                    startX1: f1.normalizedX,
                    startY1: f1.normalizedY,
                    startX2: f2.normalizedX,
                    startY2: f2.normalizedY,
                    startTime: timestamp
                )
            }
            return false

        case let .pending(f1ID, f2ID, startX1, startY1, startX2, startY2, startTime):
            guard touches.count == 2 else {
                state = .idle
                return false
            }

            guard let f1 = touches.first(where: { $0.identifier == f1ID }),
                  let f2 = touches.first(where: { $0.identifier == f2ID }) else {
                state = .idle
                return false
            }

            let d1x = f1.normalizedX - startX1
            let d1y = f1.normalizedY - startY1
            let d2x = f2.normalizedX - startX2
            let d2y = f2.normalizedY - startY2

            let dist1 = sqrt(d1x * d1x + d1y * d1y)
            let dist2 = sqrt(d2x * d2x + d2y * d2y)

            if dist1 > config.maxMovement || dist2 > config.maxMovement {
                state = .idle
                return false
            }

            if timestamp - startTime >= config.holdDuration {
                state = .held(finger1ID: f1ID, finger2ID: f2ID)
                return true
            }

            return false

        case let .held(f1ID, f2ID):
            if touches.isEmpty {
                state = .latched(releaseTime: timestamp)
                return false
            }
            guard touches.count == 2,
                  touches.contains(where: { $0.identifier == f1ID }),
                  touches.contains(where: { $0.identifier == f2ID }) else {
                state = .latched(releaseTime: timestamp)
                return false
            }
            return false

        case let .latched(releaseTime):
            if timestamp - releaseTime > config.latchDuration {
                state = .idle
            }
            return false
        }
    }

    mutating func handleTouchesEnded(timestamp: Double) {
        lastTimestamp = timestamp
        if case .held = state {
            state = .latched(releaseTime: timestamp)
        }
    }

    mutating func reset() {
        state = .idle
        lastTimestamp = 0
    }
}
