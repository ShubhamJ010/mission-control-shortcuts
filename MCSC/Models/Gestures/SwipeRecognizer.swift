import Foundation

/// Detects a two-finger vertical swipe (up or down) on the trackpad.
///
/// State machine:
///   idle → tracking (2 fingers detected, recording start Y)
///        → cooldown (threshold crossed → action fired) → idle
final class SwipeRecognizer: GestureRecognizer {
    struct Config {
        /// Minimum vertical displacement (normalized 0–1) to trigger a swipe.
        var swipeThreshold: Float = 0.08

        /// Maximum time (seconds) the gesture can take.
        var maxGestureDuration: Double = 0.8

        /// Cooldown after a successful gesture.
        var cooldownDuration: Double = 0.8

        /// Dead zone for tap/slide discrimination. Movement within this zone
        /// does not commit to swipe, leaving the result to tap recognizers.
        var tapSlideZone: Float = 0.04
    }

    var config = Config()

    /// Return true if this recognizer should be active.
    var isEnabled: (() -> Bool)?

    /// Return true if swipe-down gesture should fire.
    var isSwipeDownEnabled: (() -> Bool)?

    /// Return true if swipe-up gesture should fire.
    var isSwipeUpEnabled: (() -> Bool)?

    /// Called when a swipe gesture completes. Return true if the Cmd key is held.
    var isCmdHeld: (() -> Bool)?

    // MARK: - State

    private enum State {
        case idle

        case tracking(
            finger1ID: Int32,
            finger2ID: Int32,
            startMidY: Float,
            startMidX: Float,
            startedMoving: Bool,
            startTime: Double
        )

        case cooldown(until: Double)
    }

    private var state: State = .idle

    // MARK: - GestureRecognizer

    func processFrame(_ touches: [TouchPoint], timestamp: Double) -> GestureResult? {
        guard isEnabled?() ?? true else { return nil }

        switch state {
        case .idle:
            if touches.count == 2 {
                let midY = (touches[0].normalizedY + touches[1].normalizedY) / 2.0
                let midX = (touches[0].normalizedX + touches[1].normalizedX) / 2.0
                state = .tracking(
                    finger1ID: touches[0].identifier,
                    finger2ID: touches[1].identifier,
                    startMidY: midY,
                    startMidX: midX,
                    startedMoving: false,
                    startTime: timestamp
                )
            }
            return nil

        case let .tracking(f1ID, f2ID, startMidY, startMidX, startedMoving, startTime):
            if timestamp - startTime > config.maxGestureDuration {
                state = .idle
                return nil
            }

            let f1 = touches.first(where: { $0.identifier == f1ID })
            let f2 = touches.first(where: { $0.identifier == f2ID })

            guard let f1, let f2 else {
                state = .idle
                return nil
            }

            let currentMidY = (f1.normalizedY + f2.normalizedY) / 2.0
            let currentMidX = (f1.normalizedX + f2.normalizedX) / 2.0
            let deltaY = currentMidY - startMidY

            // Tap/slide discrimination: once movement exceeds tap-zone, commit
            var committed = startedMoving
            if !committed {
                committed = abs(deltaY) > config.tapSlideZone
            }

            guard committed else { return nil }

            if abs(deltaY) >= config.swipeThreshold {
                let center: (Float, Float) = (currentMidX, currentMidY)
                let cmdHeld = isCmdHeld?() ?? false

                // NOTE ON MULTITOUCH COORDINATE SYSTEM:
                // In Apple's MultitouchSupport framework, normalizedY = 0.0 is at the bottom of the trackpad
                // (closest to the user) and normalizedY = 1.0 is at the top of the trackpad (closest to the screen).
                // - Moving fingers UP towards the screen: currentMidY > startMidY -> deltaY > 0 -> Swipe Up (.swipeUp / .cmdSwipeUp)
                // - Moving fingers DOWN towards the user: currentMidY < startMidY -> deltaY < 0 -> Swipe Down (.swipeDown / .cmdSwipeDown)
                // Do NOT invert this logic! deltaY > 0 is Swipe Up, deltaY < 0 is Swipe Down.
                let goingUp = deltaY > 0

                let directionEnabled = goingUp ? (isSwipeUpEnabled?() ?? true) : (isSwipeDownEnabled?() ?? true)
                guard directionEnabled else {
                    state = .cooldown(until: timestamp + config.cooldownDuration)
                    return nil
                }

                state = .cooldown(until: timestamp + config.cooldownDuration)

                if goingUp {
                    return cmdHeld ? .cmdSwipeUp(atNormalized: center) : .swipeUp(atNormalized: center)
                } else {
                    return cmdHeld ? .cmdSwipeDown(atNormalized: center) : .swipeDown(atNormalized: center)
                }
            }

            state = .tracking(
                finger1ID: f1ID, finger2ID: f2ID,
                startMidY: startMidY, startMidX: startMidX,
                startedMoving: committed,
                startTime: startTime
            )
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
