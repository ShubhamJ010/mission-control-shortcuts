import Foundation

/// Detects a two-finger double tap on the trackpad.
///
/// State machine:
///   idle → tap1Down (2 fingers detected)
///        → tap1Up (all 2 lifted, waiting for second tap)
///        → cooldown (second tap detected → action fired) → idle
final class TwoFingerDoubleTapRecognizer: GestureRecognizer {
    struct Config {
        /// Maximum time between first lift and second touch (seconds).
        var doubleTapWindow: Double = 0.35

        /// Maximum duration of a single tap (finger-down to finger-up).
        var maxTapDuration: Double = 0.22

        /// Cooldown after a successful gesture.
        var cooldownDuration: Double = 0.8

        /// Maximum normalized finger displacement allowed during a tap.
        var maxTapDisplacement: Float = 0.025
    }

    var config = Config()

    /// Return true if this recognizer should be active.
    var isEnabled: (() -> Bool)?

    /// Called when gesture completes. Return true if Cmd is held.
    var isCmdHeld: (() -> Bool)?

    /// Called whenever the double-tap sequence enters or exits an in-progress state
    /// (e.g. during active taps, inter-tap window, or post-gesture cooldown).
    var onStateChanged: ((_ isInProgress: Bool) -> Void)?

    var isGestureInProgress: Bool {
        state.isInProgress
    }

    // MARK: - State

    private enum State {
        case idle
        case tap1Down(startTime: Double, startTouches: [TouchPoint])
        case tap1Up(liftTime: Double)
        case cooldown(until: Double)

        var isInProgress: Bool {
            switch self {
            case .idle:
                false
            case .tap1Down, .tap1Up, .cooldown:
                true
            }
        }
    }

    private var state: State = .idle {
        didSet {
            let wasInProgress = oldValue.isInProgress
            let nowInProgress = state.isInProgress
            if wasInProgress != nowInProgress {
                onStateChanged?(nowInProgress)
            }
        }
    }

    // MARK: - GestureRecognizer

    func processFrame(_ touches: [TouchPoint], timestamp: Double) -> GestureResult? {
        guard isEnabled?() ?? true else { return nil }

        switch state {
        case .idle:
            if touches.count >= 2 {
                state = .tap1Down(startTime: timestamp, startTouches: touches)
            }
            return nil

        case let .tap1Down(startTime, startTouches):
            // Timeout: fingers held too long — not a tap
            if timestamp - startTime > config.maxTapDuration {
                state = .idle
                return nil
            }
            // Movement guard: if fingers slid, this is a swipe/scroll, not a tap
            for touch in touches {
                if let start = startTouches.first(where: { $0.identifier == touch.identifier }) {
                    let dx = touch.normalizedX - start.normalizedX
                    let dy = touch.normalizedY - start.normalizedY
                    if sqrt(dx * dx + dy * dy) > config.maxTapDisplacement {
                        state = .idle
                        return nil
                    }
                }
            }
            // All 2 fingers lifted → first tap complete
            if touches.isEmpty {
                state = .tap1Up(liftTime: timestamp)
            }
            return nil

        case let .tap1Up(liftTime):
            // Timeout: second tap didn't come in time
            if timestamp - liftTime > config.doubleTapWindow {
                state = .idle
                return nil
            }
            // Second tap: 2 fingers touch down again
            if touches.count >= 2 {
                let cmdHeld = isCmdHeld?() ?? false
                state = .cooldown(until: timestamp + config.cooldownDuration)
                return cmdHeld ? .cmdTwoFingerDoubleTap : .twoFingerDoubleTap
            }
            return nil

        case let .cooldown(until):
            if timestamp > until {
                state = .idle
            }
            return nil
        }
    }

    func reset() {
        state = .idle
    }
}
