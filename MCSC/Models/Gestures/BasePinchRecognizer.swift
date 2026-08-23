import Foundation

/// Shared state-machine and geometry for pinch gestures.
///
/// `PinchInRecognizer` and `PinchOutRecognizer` differ only in the direction of
/// the distance ratio and the `GestureResult` they emit. This base class holds
/// the common `Config`, `State`, timing, and geometry so the two subclasses
/// stay trivial and the 40% threshold / 1.5s / 0.8s constants live in one place.
class BasePinchRecognizer: GestureRecognizer {
    enum Direction {
        case inward // distance decreases
        case outward // distance increases
    }

    struct Config {
        /// Minimum ratio of distance change to trigger (0.0–1.0).
        /// e.g. 0.4 means 40% shrink (inward) or 40% growth (outward).
        var pinchRatioThreshold: Float = 0.4
        var maxGestureDuration: Double = 1.5
        var cooldownDuration: Double = 0.8
    }

    var config = Config()
    var isEnabled: (() -> Bool)?
    var isCmdHeld: (() -> Bool)?

    private let direction: Direction

    private enum State {
        case idle
        case tracking(
            finger1ID: Int32,
            finger2ID: Int32,
            initialDistance: Float,
            startTime: Double,
            lastDistance: Float,
            lastCenterNormalized: (Float, Float)
        )
        case cooldown(until: Double)
    }

    private var state: State = .idle

    init(direction: Direction) {
        self.direction = direction
    }

    func processFrame(_ touches: [TouchPoint], timestamp: Double) -> GestureResult? {
        guard isEnabled?() ?? true else { return nil }
        switch state {
        case .idle:
            if touches.count == 2 {
                let d = TouchGeometry.distance(touches[0], touches[1])
                let center = TouchGeometry.midpoint(touches[0], touches[1])
                state = .tracking(
                    finger1ID: touches[0].identifier,
                    finger2ID: touches[1].identifier,
                    initialDistance: d,
                    startTime: timestamp,
                    lastDistance: d,
                    lastCenterNormalized: center
                )
            }
            return nil

        case let .tracking(f1ID, f2ID, initialDist, startTime, _, _):
            if timestamp - startTime > config.maxGestureDuration {
                state = .idle
                return nil
            }
            let f1 = touches.first(where: { $0.identifier == f1ID })
            let f2 = touches.first(where: { $0.identifier == f2ID })
            if let f1, let f2 {
                let currentDist = TouchGeometry.distance(f1, f2)
                let center = TouchGeometry.midpoint(f1, f2)
                let ratio: Float = switch direction {
                case .inward:
                    initialDist > 0.05 ? (initialDist - currentDist) / initialDist : 0
                case .outward:
                    initialDist > 0.05 ? (currentDist - initialDist) / initialDist : 0
                }
                if ratio >= config.pinchRatioThreshold {
                    state = .cooldown(until: timestamp + config.cooldownDuration)
                    let cmdHeld = isCmdHeld?() ?? false
                    return result(atNormalized: center, cmdHeld: cmdHeld)
                } else {
                    state = .tracking(
                        finger1ID: f1ID, finger2ID: f2ID,
                        initialDistance: initialDist,
                        startTime: startTime,
                        lastDistance: currentDist,
                        lastCenterNormalized: center
                    )
                }
                return nil
            }
            state = .idle
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

    private func result(atNormalized center: (Float, Float), cmdHeld: Bool) -> GestureResult {
        switch direction {
        case .inward:
            if cmdHeld {
                .cmdPinchIn(atNormalized: center)
            } else {
                .pinchIn(atNormalized: center)
            }
        case .outward:
            if cmdHeld {
                .cmdPinchOut(atNormalized: center)
            } else {
                .pinchOut(atNormalized: center)
            }
        }
    }
}

/// Pure geometry helpers shared by pinch recognizers.
enum TouchGeometry {
    static func distance(_ a: TouchPoint, _ b: TouchPoint) -> Float {
        let dx = a.normalizedX - b.normalizedX
        let dy = a.normalizedY - b.normalizedY
        return sqrt(dx * dx + dy * dy)
    }

    static func midpoint(_ a: TouchPoint, _ b: TouchPoint) -> (Float, Float) {
        ((a.normalizedX + b.normalizedX) / 2.0,
         (a.normalizedY + b.normalizedY) / 2.0)
    }
}
