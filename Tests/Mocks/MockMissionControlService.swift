import Foundation

/// Recording Mission Control double. Unlike the inert
/// `MockSettingsMissionControlService`, this one records `markActive` calls
/// and lets tests drive `isMissionControlActive` so the hover service's
/// open/close/reopen state machine can be verified against the unified
/// detector signal.
@MainActor
final class MockMissionControlService: MissionControlServiceProtocol {
    var isMissionControlActive = false
    var isSimulating = false
    var onActivated: (() -> Void)?
    var onDeactivated: (() -> Void)?

    /// Ordered log of every `markActive(_:)` push.
    private(set) var markActiveCalls: [Bool] = []

    func checkMissionControlActive() -> Bool {
        isMissionControlActive
    }

    func executeFixSequence() {}

    func start() {}
    func stop() {}

    func markActive(_ active: Bool) {
        markActiveCalls.append(active)
        isMissionControlActive = active
        if active {
            onActivated?()
        } else {
            onDeactivated?()
        }
    }
}
