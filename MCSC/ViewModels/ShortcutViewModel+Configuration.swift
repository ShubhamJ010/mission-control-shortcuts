import Foundation

extension ShortcutViewModel {
    /// Forwarding properties for configuration (keeps AppDelegate and Settings API unchanged)
    var isClosingEnabled: Bool {
        get { config.isClosingEnabled } set { config.isClosingEnabled = newValue }
    }

    var isCmdWEnabled: Bool {
        get { config.isCmdWEnabled } set { config.isCmdWEnabled = newValue }
    }

    var isCmdQEnabled: Bool {
        get { config.isCmdQEnabled } set { config.isCmdQEnabled = newValue }
    }

    var isCmdMEnabled: Bool {
        get { config.isCmdMEnabled } set { config.isCmdMEnabled = newValue }
    }

    var isCmdHEnabled: Bool {
        get { config.isCmdHEnabled } set { config.isCmdHEnabled = newValue }
    }

    var isCmdFEnabled: Bool {
        get { config.isCmdFEnabled } set { config.isCmdFEnabled = newValue }
    }

    var isCmdSpaceEnabled: Bool {
        get { config.isCmdSpaceEnabled } set { config.isCmdSpaceEnabled = newValue }
    }

    var isTabShortcutsEnabled: Bool {
        get { config.isTabShortcutsEnabled } set { config.isTabShortcutsEnabled = newValue }
    }

    var isCmdTEnabled: Bool {
        get { config.isCmdTEnabled } set { config.isCmdTEnabled = newValue }
    }

    var isCmdNEnabled: Bool {
        get { config.isCmdNEnabled } set { config.isCmdNEnabled = newValue }
    }

    var isCmdShiftTEnabled: Bool {
        get { config.isCmdShiftTEnabled } set { config.isCmdShiftTEnabled = newValue }
    }

    var isFillScreenEnabled: Bool {
        get { config.isFillScreenEnabled } set { config.isFillScreenEnabled = newValue }
    }

    var isAlmostMaximizeEnabled: Bool {
        get { config.isAlmostMaximizeEnabled } set { config.isAlmostMaximizeEnabled = newValue }
    }

    var isReasonableSizeEnabled: Bool {
        get { config.isReasonableSizeEnabled } set { config.isReasonableSizeEnabled = newValue }
    }

    var isMakeLargerEnabled: Bool {
        get { config.isMakeLargerEnabled } set { config.isMakeLargerEnabled = newValue }
    }

    var isMakeSmallerEnabled: Bool {
        get { config.isMakeSmallerEnabled } set { config.isMakeSmallerEnabled = newValue }
    }

    var isLeftHalfSnapEnabled: Bool {
        get { config.isLeftHalfSnapEnabled } set { config.isLeftHalfSnapEnabled = newValue }
    }

    var isRightHalfSnapEnabled: Bool {
        get { config.isRightHalfSnapEnabled } set { config.isRightHalfSnapEnabled = newValue }
    }

    var isLeftThirdSnapEnabled: Bool {
        get { config.isLeftThirdSnapEnabled } set { config.isLeftThirdSnapEnabled = newValue }
    }

    var isRightThirdSnapEnabled: Bool {
        get { config.isRightThirdSnapEnabled } set { config.isRightThirdSnapEnabled = newValue }
    }

    var isMoveNextDesktopEnabled: Bool {
        get { config.isMoveNextDesktopEnabled } set { config.isMoveNextDesktopEnabled = newValue }
    }

    var isMovePreviousDesktopEnabled: Bool {
        get { config.isMovePreviousDesktopEnabled } set { config.isMovePreviousDesktopEnabled = newValue }
    }

    var isAutoEjectEnabled: Bool {
        get { config.isAutoEjectEnabled } set { config.isAutoEjectEnabled = newValue }
    }

    var isQuitAppIfNoWindowsEnabled: Bool {
        get { config.isQuitAppIfNoWindowsEnabled } set { config.isQuitAppIfNoWindowsEnabled = newValue }
    }

    var isDockActionsOutsideMCEnabled: Bool {
        get { config.isDockActionsOutsideMCEnabled }
        set {
            config.isDockActionsOutsideMCEnabled = newValue
            syncServiceLifecycles()
        }
    }

    var isTitleBarActionsOutsideMCEnabled: Bool {
        get { config.isTitleBarActionsOutsideMCEnabled } set { config.isTitleBarActionsOutsideMCEnabled = newValue }
    }

    var isGesturesEnabled: Bool {
        get { config.isGesturesEnabled }
        set {
            config.isGesturesEnabled = newValue
            syncServiceLifecycles()
        }
    }

    var isPinchInEnabled: Bool {
        get { config.isPinchInEnabled } set { config.isPinchInEnabled = newValue }
    }

    var isPinchOutEnabled: Bool {
        get { config.isPinchOutEnabled } set { config.isPinchOutEnabled = newValue }
    }

    var isSwipeLeftEnabled: Bool {
        get { config.isSwipeLeftEnabled } set { config.isSwipeLeftEnabled = newValue }
    }

    var isSwipeRightEnabled: Bool {
        get { config.isSwipeRightEnabled } set { config.isSwipeRightEnabled = newValue }
    }

    var isSwipeDownEnabled: Bool {
        get { config.isSwipeDownEnabled } set { config.isSwipeDownEnabled = newValue }
    }

    var isSwipeUpEnabled: Bool {
        get { config.isSwipeUpEnabled } set { config.isSwipeUpEnabled = newValue }
    }

    var isTwoFingerDoubleTapEnabled: Bool {
        get { config.isTwoFingerDoubleTapEnabled } set { config.isTwoFingerDoubleTapEnabled = newValue }
    }

    var isTwoFingerHoldEnabled: Bool {
        get { config.isTwoFingerHoldEnabled }
        set {
            config.isTwoFingerHoldEnabled = newValue
            holdDetector.config.holdDuration = config.twoFingerHoldDuration
        }
    }

    var twoFingerHoldDuration: Double {
        get { config.twoFingerHoldDuration }
        set {
            config.twoFingerHoldDuration = newValue
            holdDetector.config.holdDuration = newValue
        }
    }

    var isKeyboardNavigationEnabled: Bool {
        get { config.isKeyboardNavigationEnabled } set { config.isKeyboardNavigationEnabled = newValue }
    }

    var isHapticFeedbackEnabled: Bool {
        get { config.isHapticFeedbackEnabled } set { config.isHapticFeedbackEnabled = newValue }
    }

    var isCursorFeedbackEnabled: Bool {
        get { config.isCursorFeedbackEnabled } set { config.isCursorFeedbackEnabled = newValue }
    }

    var isOptimizedAnimationModeEnabled: Bool {
        get { config.isOptimizedAnimationModeEnabled }
        set { config.isOptimizedAnimationModeEnabled = newValue }
    }
}
