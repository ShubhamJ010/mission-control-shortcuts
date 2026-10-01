import Foundation
import os

/// Zero-overhead signpost instrumentation using Apple's `OSSignposter`.
/// When Xcode Instruments (Points of Interest / Time Profiler / System Trace) is
/// not active, intervals compile down to a near-zero cost check in the kernel trace buffer.
enum AppSignpost {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "sj010.MCSC"

    static let eventTap = OSSignposter(subsystem: subsystem, category: "eventTap")
    static let multitouch = OSSignposter(subsystem: subsystem, category: "multitouch")
    static let missionControl = OSSignposter(subsystem: subsystem, category: "missionControl")
    static let accessibility = OSSignposter(subsystem: subsystem, category: "accessibility")
    static let search = OSSignposter(subsystem: subsystem, category: "search")
    static let memory = OSSignposter(subsystem: subsystem, category: "memory")

    /// Wraps synchronous execution in a measured signpost interval.
    @inline(__always)
    static func trace<T>(
        _ signposter: OSSignposter,
        _ name: StaticString,
        _ operation: () throws -> T
    ) rethrows -> T {
        guard signposter.isEnabled else {
            return try operation()
        }
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: id)
        defer { signposter.endInterval(name, state) }
        return try operation()
    }
}
