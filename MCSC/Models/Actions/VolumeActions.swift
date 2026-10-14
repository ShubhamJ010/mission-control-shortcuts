import Cocoa

/// Closes a Finder window showing an ejectable/mounted volume, then ejects the volume.
struct EjectVolumeAction {
    func perform(
        window: AXUIElement,
        mountPath: String,
        service: AccessibilityServiceProtocol,
        volumeService: MountedVolumeServiceProtocol
    ) {
        // 1. Close the Finder window first
        if let closeButton: AXUIElement = service.getAttributeValue(kAXCloseButtonAttribute, for: window) {
            _ = service.performAction(kAXPressAction, on: closeButton)
        }

        // 2. Eject the mounted volume asynchronously
        volumeService.ejectVolume(at: mountPath) { _ in }
    }

    func perform(
        windowInfo: [String: Any],
        mountPath: String,
        service: AccessibilityServiceProtocol,
        volumeService: MountedVolumeServiceProtocol
    ) {
        // 1. Close the Finder window using Mission Control action
        MissionControlWindowActions.performClose(on: windowInfo, accessibilityService: service)

        // 2. Eject the mounted volume asynchronously
        volumeService.ejectVolume(at: mountPath) { _ in }
    }
}

