import Cocoa

/// The kind of gesture MCSC wants to give the user tactile feedback for.
enum HapticType: Equatable {
    case swipeLeft
    case swipeRight
    case swipeDown
    case swipeUp
    case twoFingerDoubleTap
    case cmdTwoFingerDoubleTap
    case pinchIn
    case pinchOut
    case twoFingerHold
}

/// Plays short, tactile haptic pulses through the built-in trackpad engine.
///
/// Each gesture is mapped to a small choreography of `NSHapticFeedbackManager`
/// patterns so swipes, taps, and pinches feel distinct. The follow-up pulses
/// are scheduled on a background queue because they are intentionally delayed
/// relative to the lead pulse; they are cheap, fire-and-forget calls.
enum HapticService {
    static func perform(_ type: HapticType) {
        let performer = NSHapticFeedbackManager.defaultPerformer
        switch type {
        case .swipeLeft:
            performer.perform(.alignment, performanceTime: .now)
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05) {
                performer.perform(.levelChange, performanceTime: .now)
            }
        case .swipeRight:
            performer.perform(.levelChange, performanceTime: .now)
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05) {
                performer.perform(.alignment, performanceTime: .now)
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.09) {
                performer.perform(.alignment, performanceTime: .now)
            }
        case .swipeDown:
            performer.perform(.levelChange, performanceTime: .now)
        case .swipeUp:
            performer.perform(.alignment, performanceTime: .now)
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.07) {
                performer.perform(.levelChange, performanceTime: .now)
            }
        case .twoFingerDoubleTap:
            performer.perform(.alignment, performanceTime: .now)
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.10) {
                performer.perform(.alignment, performanceTime: .now)
            }
        case .cmdTwoFingerDoubleTap:
            performer.perform(.alignment, performanceTime: .now)
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.10) {
                performer.perform(.alignment, performanceTime: .now)
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.08) {
                    performer.perform(.levelChange, performanceTime: .now)
                }
            }
        case .pinchIn:
            performer.perform(.levelChange, performanceTime: .now)
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.08) {
                performer.perform(.levelChange, performanceTime: .now)
            }
        case .pinchOut:
            // Distinct from pinchIn (levelChange → levelChange): expand feel uses
            // alignment (light tick) then levelChange (deeper thud).
            performer.perform(.alignment, performanceTime: .now)
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.08) {
                performer.perform(.levelChange, performanceTime: .now)
            }
        case .twoFingerHold:
            performer.perform(.levelChange, performanceTime: .now)
        }
    }
}
