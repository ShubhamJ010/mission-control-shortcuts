import Cocoa

/// Service lifecycle gating for `ShortcutViewModel`: which heavyweight
/// services run is derived from the feature toggles, and every `start()` /
/// `stop()` pair is idempotent. Split from the main file to stay under the
/// SwiftLint `file_length` budget.
@MainActor
extension ShortcutViewModel {
    /// `true` when any feature that consumes trackpad frames is enabled.
    /// When `false`, `MultitouchService` is not started — avoiding dlopen
    /// of MultitouchSupport.framework and its 60-120 Hz frame stream.
    var needsMultitouch: Bool {
        config.isGesturesEnabled
    }

    /// `true` when the dock interaction suppressor should be active.
    var needsDockSuppressor: Bool {
        config.isGesturesEnabled && config.isDockActionsOutsideMCEnabled
    }

    /// Starts or stops heavyweight services in response to toggle changes.
    /// Each service's `start()`/`stop()` is idempotent — safe to call when
    /// already in the desired state.
    func syncServiceLifecycles() {
        if needsMultitouch {
            multitouchService.start()
        } else {
            multitouchService.stop()
            gestureEngine.reset()
        }

        if needsDockSuppressor {
            dockSuppressor.start()
        } else {
            dockSuppressor.stop()
        }

        if isHoverCloseButtonEnabled {
            hoverService.start()
        } else {
            hoverService.stop()
        }
    }
}
