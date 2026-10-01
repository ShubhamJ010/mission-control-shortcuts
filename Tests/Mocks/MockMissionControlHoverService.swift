import Foundation
import CoreGraphics

@MainActor
final class MockMissionControlHoverService: MissionControlHoverServiceProtocol {
    var isEnabled: Bool = true
    var isTracking: Bool = false
    var isMissionControlActive: Bool = true
    var isDragging: Bool = false
    var currentHoveredWindow: [String: Any]?
    var currentHoveredWindowFrame: CGRect?
    var mockPreviewWindow: (windowInfo: [String: Any], windowID: CGWindowID)?

    var executedActions: [(mode: PreviewCloseButtonOverlay.Mode, windowInfo: [String: Any])] = []

    func start() {}
    func stop() {}
    func hideOverlay() {}
    func hideAllOverlays() {}
    func handleActivated() {}
    func handleDeactivated() {}
    func clearSearch() {}

    func previewWindow(at point: CGPoint) -> (windowInfo: [String: Any], windowID: CGWindowID)? {
        mockPreviewWindow
    }

    func executeAction(mode: PreviewCloseButtonOverlay.Mode, on windowInfo: [String: Any]) {
        executedActions.append((mode: mode, windowInfo: windowInfo))
    }
}
