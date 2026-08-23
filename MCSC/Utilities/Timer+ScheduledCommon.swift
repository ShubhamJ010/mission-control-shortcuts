import Foundation

/// Centralizes the `RunLoop.main` in `.common` modes + tolerance pattern used
/// for Mission Control's window-list poll (0.5 s during Exposé) and the
/// keyboard-search idle clear (2 s). Using `.common` modes ensures the timers
/// fire while Mission Control's tracking run loop is active, and tolerance
/// allows the system to coalesce the timer for power efficiency.
///
/// Shared by `MissionControlHoverService` and its extensions; kept internal so
/// both files schedule timers identically.
enum HoverServiceTiming {
    static let windowPoll: TimeInterval = 0.5
    static let windowPollTolerance: TimeInterval = 0.05
    static let queryIdle: TimeInterval = 2.0
    static let queryIdleTolerance: TimeInterval = 0.2
}

extension Timer {
    /// Creates and schedules a timer on `RunLoop.main` in `.common` modes with
    /// the given tolerance. The timer is auto-added to the run loop and
    /// returned for invalidation by the caller.
    static func scheduledCommon(
        interval: TimeInterval,
        repeats: Bool,
        tolerance: TimeInterval,
        block: @escaping (Timer) -> Void
    ) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats, block: block)
        timer.tolerance = tolerance
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
