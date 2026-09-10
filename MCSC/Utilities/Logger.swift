import Foundation
@_exported import os

/// Lightweight logging wrapper using `os.Logger` for compile-time optimized,
/// zero-allocation logging under normal operation.
enum AppLogger {
    static let subsystem = Bundle.main.bundleIdentifier ?? "sj010.MCSC"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let dock = Logger(subsystem: subsystem, category: "dock")
    static let multitouch = Logger(subsystem: subsystem, category: "multitouch")
    static let gesture = Logger(subsystem: subsystem, category: "gesture")
    static let accessibility = Logger(subsystem: subsystem, category: "accessibility")
    static let eventTap = Logger(subsystem: subsystem, category: "eventTap")
    static let volume = Logger(subsystem: subsystem, category: "volume")
    static let missionControl = Logger(subsystem: subsystem, category: "missionControl")
    static let diagnostics = Logger(subsystem: subsystem, category: "diagnostics")
}
