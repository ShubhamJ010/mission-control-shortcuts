import Foundation
import XCTest

final class RouterTests: XCTestCase {
    private var mockService: MockAccessibilityService!
    private var actionRegistry: ActionRegistry!
    private var shortcutRouter: ShortcutActionRouter!
    private var gestureRouter: GestureActionRouter!

    override func setUp() {
        super.setUp()
        mockService = MockAccessibilityService()
        mockService.mockElement = AXUIElementCreateSystemWide()
        actionRegistry = ActionRegistry()
        shortcutRouter = ShortcutActionRouter(actions: actionRegistry)
        gestureRouter = GestureActionRouter(actions: actionRegistry)
        // Tests construct `ShortcutConfiguration()` expecting pristine
        // defaults; clear persisted toggle state so results never depend on
        // prior runs (config mutations write through to UserDefaults).
        for entry in ShortcutConfiguration.toggleDefaults {
            UserDefaults.standard.removeObject(forKey: entry.key)
        }
    }

    func testShortcutRouterCmdWProducesCloseActionWhenEnabled() {
        let config = ShortcutConfiguration()
        let result = shortcutRouter.routeShortcut(
            keyCode: ShortcutActionRouter.kKeyW,
            flags: .maskCommand,
            location: CGPoint(x: 100, y: 100),
            config: config,
            isMissionControlActive: true,
            target: .none,
            service: mockService,
            activateApp: { _ in }
        )

        switch result {
        case let .consumeAndExecute(feedbackMode, _):
            XCTAssertEqual(feedbackMode, .close)
        case .ignore:
            XCTFail("Expected shortcut to be consumed and executed")
        }
    }

    func testShortcutRouterIgnoresWhenMissionControlInactive() {
        let config = ShortcutConfiguration()
        let result = shortcutRouter.routeShortcut(
            keyCode: ShortcutActionRouter.kKeyW,
            flags: .maskCommand,
            location: CGPoint(x: 100, y: 100),
            config: config,
            isMissionControlActive: false,
            target: .none,
            service: mockService,
            activateApp: { _ in }
        )

        switch result {
        case .consumeAndExecute:
            XCTFail("Should ignore when Mission Control is inactive")
        case .ignore:
            break
        }
    }

    func testShortcutRouterIgnoresWhenDisabled() {
        var config = ShortcutConfiguration()
        config.isCmdWEnabled = false

        let result = shortcutRouter.routeShortcut(
            keyCode: ShortcutActionRouter.kKeyW,
            flags: .maskCommand,
            location: CGPoint(x: 100, y: 100),
            config: config,
            isMissionControlActive: true,
            target: .none,
            service: mockService,
            activateApp: { _ in }
        )

        switch result {
        case .consumeAndExecute:
            XCTFail("Should ignore disabled shortcut")
        case .ignore:
            break
        }
    }

    func testNewShortcutsDefaultToDisabledInConfiguration() {
        let config = ShortcutConfiguration()
        XCTAssertFalse(config.isCmdFEnabled)
        XCTAssertFalse(config.isCmdTEnabled)
        XCTAssertFalse(config.isCmdNEnabled)
        XCTAssertFalse(config.isCmdShiftWEnabled)
        XCTAssertFalse(config.isCmdShiftTEnabled)
    }

    func testShortcutRouterCmdFRoutesToFullscreenWhenEnabled() {
        var config = ShortcutConfiguration()
        config.isCmdFEnabled = true

        let result = shortcutRouter.routeShortcut(
            keyCode: ShortcutActionRouter.kKeyF,
            flags: .maskCommand,
            location: CGPoint(x: 100, y: 100),
            config: config,
            isMissionControlActive: true,
            target: .none,
            service: mockService,
            activateApp: { _ in }
        )

        switch result {
        case let .consumeAndExecute(feedbackMode, _):
            XCTAssertEqual(feedbackMode, .fullscreen)
        case .ignore:
            XCTFail("Expected Cmd+F to route to fullscreen")
        }
    }

    func testShortcutRouterCmdTRoutesToNewTabWhenEnabled() {
        var config = ShortcutConfiguration()
        config.isCmdTEnabled = true

        let result = shortcutRouter.routeShortcut(
            keyCode: ShortcutActionRouter.kKeyT,
            flags: .maskCommand,
            location: CGPoint(x: 100, y: 100),
            config: config,
            isMissionControlActive: true,
            target: .none,
            service: mockService,
            activateApp: { _ in }
        )

        switch result {
        case let .consumeAndExecute(feedbackMode, _):
            XCTAssertEqual(feedbackMode, .newTab)
        case .ignore:
            XCTFail("Expected Cmd+T to route to newTab")
        }
    }

    func testShortcutRouterCmdNRoutesToNewWindowWhenEnabled() {
        var config = ShortcutConfiguration()
        config.isCmdNEnabled = true

        let result = shortcutRouter.routeShortcut(
            keyCode: ShortcutActionRouter.kKeyN,
            flags: .maskCommand,
            location: CGPoint(x: 100, y: 100),
            config: config,
            isMissionControlActive: true,
            target: .none,
            service: mockService,
            activateApp: { _ in }
        )

        switch result {
        case let .consumeAndExecute(feedbackMode, _):
            XCTAssertEqual(feedbackMode, .newWindow)
        case .ignore:
            XCTFail("Expected Cmd+N to route to newWindow")
        }
    }

    func testShortcutRouterCmdShiftWRoutesToCloseAllTabsWhenEnabled() {
        var config = ShortcutConfiguration()
        config.isCmdShiftWEnabled = true

        let result = shortcutRouter.routeShortcut(
            keyCode: ShortcutActionRouter.kKeyW,
            flags: [.maskCommand, .maskShift],
            location: CGPoint(x: 100, y: 100),
            config: config,
            isMissionControlActive: true,
            target: .none,
            service: mockService,
            activateApp: { _ in }
        )

        switch result {
        case let .consumeAndExecute(feedbackMode, _):
            XCTAssertEqual(feedbackMode, .closeAllTabs)
        case .ignore:
            XCTFail("Expected Cmd+Shift+W to route to closeAllTabs")
        }
    }

    func testShortcutRouterCmdShiftTRoutesToReopenTabWhenEnabled() {
        var config = ShortcutConfiguration()
        config.isCmdShiftTEnabled = true

        let result = shortcutRouter.routeShortcut(
            keyCode: ShortcutActionRouter.kKeyT,
            flags: [.maskCommand, .maskShift],
            location: CGPoint(x: 100, y: 100),
            config: config,
            isMissionControlActive: true,
            target: .none,
            service: mockService,
            activateApp: { _ in }
        )

        switch result {
        case let .consumeAndExecute(feedbackMode, _):
            XCTAssertEqual(feedbackMode, .reopenTab)
        case .ignore:
            XCTFail("Expected Cmd+Shift+T to route to reopenTab")
        }
    }

    func testGestureRouterPinchInRoutesToClose() throws {
        let result = try gestureRouter.routeGesture(
            .pinchIn(atNormalized: (0.5, 0.5)),
            at: CGPoint(x: 200, y: 200),
            target: .window(XCTUnwrap(mockService.mockElement)),
            service: mockService,
            activateApp: { _ in }
        )

        switch result {
        case let .execute(feedbackMode, haptic, _):
            XCTAssertEqual(feedbackMode, .close)
            XCTAssertEqual(haptic, .pinchIn)
        case .none:
            XCTFail("Expected gesture to route to action")
        }
    }

    func testGestureRouterCmdPinchInRoutesToQuit() throws {
        let result = try gestureRouter.routeGesture(
            .cmdPinchIn(atNormalized: (0.5, 0.5)),
            at: CGPoint(x: 200, y: 200),
            target: .window(XCTUnwrap(mockService.mockElement)),
            service: mockService,
            activateApp: { _ in }
        )

        switch result {
        case let .execute(feedbackMode, haptic, _):
            XCTAssertEqual(feedbackMode, .quit)
            XCTAssertEqual(haptic, .pinchIn)
        case .none:
            XCTFail("Expected gesture to route to action")
        }
    }

    func testGestureRouterDoubleTapRoutesToReasonableSize() throws {
        let result = try gestureRouter.routeGesture(
            .twoFingerDoubleTap,
            at: CGPoint(x: 200, y: 200),
            target: .window(XCTUnwrap(mockService.mockElement)),
            service: mockService,
            activateApp: { _ in }
        )

        switch result {
        case let .execute(feedbackMode, haptic, _):
            XCTAssertEqual(feedbackMode, .reasonable)
            XCTAssertEqual(haptic, .twoFingerDoubleTap)
        case .none:
            XCTFail("Expected gesture to route to action")
        }
    }

    func testMakeSmallerRoutesOnWindowTargetWithMakeSmallerFeedback() throws {
        let result = try routePinchInBound(to: .makeSmaller, target: .window(XCTUnwrap(mockService.mockElement)))
        guard case let .execute(mode, _, _) = result else {
            XCTFail("Expected makeSmaller on window to execute")
            return
        }
        XCTAssertEqual(mode, .makeSmaller)
    }

    func testMakeSmallerRoutesOnDockTargetWithMakeSmallerFeedback() {
        let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
            .first ?? NSRunningApplication.current
        let result = routePinchInBound(to: .makeSmaller, target: .dock(dockApp))
        guard case let .execute(mode, _, _) = result else {
            XCTFail("Expected makeSmaller on dock to execute")
            return
        }
        XCTAssertEqual(mode, .makeSmaller)
    }

    func testShortcutRouterCmdWRoutesToEjectWhenFinderMountedVolume() throws {
        let mockVolumeService = MockMountedVolumeService()
        mockVolumeService.mockEjectablePath = "/Volumes/AppInstaller"

        let finderApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
        mockService.mockApp = finderApp
        mockService.mockDocumentPath = "/Volumes/AppInstaller"

        // Explicit: a persisted `mcsc.autoEject.enabled = 0` from the real app
        // would otherwise disable the eject branch and fail these assertions.
        var config = ShortcutConfiguration()
        config.isAutoEjectEnabled = true

        let result = try shortcutRouter.routeShortcut(
            keyCode: ShortcutActionRouter.kKeyW,
            flags: .maskCommand,
            location: CGPoint(x: 100, y: 100),
            config: config,
            isMissionControlActive: true,
            target: .window(XCTUnwrap(mockService.mockElement)),
            service: mockService,
            volumeService: mockVolumeService,
            activateApp: { _ in }
        )

        switch result {
        case let .consumeAndExecute(feedbackMode, action):
            XCTAssertEqual(feedbackMode, .eject)
            action()
            XCTAssertEqual(mockVolumeService.ejectVolumeCalledWith, "/Volumes/AppInstaller")
        case .ignore:
            XCTFail("Expected shortcut to route to eject action")
        }
    }

    func testShortcutRouterCmdQRoutesToEjectWhenFinderMountedVolume() throws {
        let mockVolumeService = MockMountedVolumeService()
        mockVolumeService.mockEjectablePath = "/Volumes/AppInstaller"

        let finderApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
        mockService.mockApp = finderApp
        mockService.mockDocumentPath = "/Volumes/AppInstaller"

        // Explicit: a persisted `mcsc.autoEject.enabled = 0` from the real app
        // would otherwise disable the eject branch and fail these assertions.
        var config = ShortcutConfiguration()
        config.isAutoEjectEnabled = true

        let result = try shortcutRouter.routeShortcut(
            keyCode: ShortcutActionRouter.kKeyQ,
            flags: .maskCommand,
            location: CGPoint(x: 100, y: 100),
            config: config,
            isMissionControlActive: true,
            target: .window(XCTUnwrap(mockService.mockElement)),
            service: mockService,
            volumeService: mockVolumeService,
            activateApp: { _ in }
        )

        switch result {
        case let .consumeAndExecute(feedbackMode, action):
            XCTAssertEqual(feedbackMode, .eject)
            action()
            XCTAssertEqual(mockVolumeService.ejectVolumeCalledWith, "/Volumes/AppInstaller")
        case .ignore:
            XCTFail("Expected Cmd+Q on mounted volume to route to eject action")
        }
    }

    func testShortcutRouterDoesNotEjectWhenAutoEjectDisabled() throws {
        let mockVolumeService = MockMountedVolumeService()
        mockVolumeService.mockEjectablePath = "/Volumes/AppInstaller"

        let finderApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
        mockService.mockApp = finderApp
        mockService.mockDocumentPath = "/Volumes/AppInstaller"

        var config = ShortcutConfiguration()
        config.isAutoEjectEnabled = false

        let result = try shortcutRouter.routeShortcut(
            keyCode: ShortcutActionRouter.kKeyW,
            flags: .maskCommand,
            location: CGPoint(x: 100, y: 100),
            config: config,
            isMissionControlActive: true,
            target: .window(XCTUnwrap(mockService.mockElement)),
            service: mockService,
            volumeService: mockVolumeService,
            activateApp: { _ in }
        )

        switch result {
        case let .consumeAndExecute(feedbackMode, _):
            XCTAssertEqual(feedbackMode, .close)
        case .ignore:
            XCTFail("Expected standard close action when auto-eject disabled")
        }
    }

    func testGestureRouterPinchInRoutesToEjectWhenFinderMountedVolume() throws {
        let mockVolumeService = MockMountedVolumeService()
        mockVolumeService.mockEjectablePath = "/Volumes/AppInstaller"

        let finderApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
        mockService.mockApp = finderApp
        mockService.mockDocumentPath = "/Volumes/AppInstaller"

        let result = try gestureRouter.routeGesture(
            .pinchIn(atNormalized: (0.5, 0.5)),
            at: CGPoint(x: 200, y: 200),
            target: .window(XCTUnwrap(mockService.mockElement)),
            service: mockService,
            volumeService: mockVolumeService,
            activateApp: { _ in }
        )

        switch result {
        case let .execute(feedbackMode, haptic, action):
            XCTAssertEqual(feedbackMode, .eject)
            XCTAssertEqual(haptic, .pinchIn)
            action()
            XCTAssertEqual(mockVolumeService.ejectVolumeCalledWith, "/Volumes/AppInstaller")
        case .none:
            XCTFail("Expected gesture to route to eject action")
        }
    }

    func testGestureRouterDoesNotEjectWhenAutoEjectDisabled() throws {
        let mockVolumeService = MockMountedVolumeService()
        mockVolumeService.mockEjectablePath = "/Volumes/AppInstaller"

        let finderApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
        mockService.mockApp = finderApp
        mockService.mockDocumentPath = "/Volumes/AppInstaller"

        let result = try gestureRouter.routeGesture(
            .pinchIn(atNormalized: (0.5, 0.5)),
            at: CGPoint(x: 200, y: 200),
            target: .window(XCTUnwrap(mockService.mockElement)),
            service: mockService,
            volumeService: mockVolumeService,
            isAutoEjectEnabled: false,
            activateApp: { _ in }
        )

        switch result {
        case let .execute(feedbackMode, haptic, _):
            XCTAssertEqual(feedbackMode, .close)
            XCTAssertEqual(haptic, .pinchIn)
            XCTAssertNil(mockVolumeService.ejectVolumeCalledWith)
        case .none:
            XCTFail("Expected gesture to route to standard close action")
        }
    }

    func testShortcutRouterExecutesDockShortcutWhenMissionControlInactiveAndDockActionsOutsideMCEnabled() {
        let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
            .first ?? NSRunningApplication.current
        var config = ShortcutConfiguration()
        config.isDockActionsOutsideMCEnabled = true

        let result = shortcutRouter.routeShortcut(
            keyCode: ShortcutActionRouter.kKeyW,
            flags: .maskCommand,
            location: CGPoint(x: 100, y: 100),
            config: config,
            isMissionControlActive: false,
            target: .dock(dockApp),
            service: mockService,
            activateApp: { _ in }
        )

        switch result {
        case let .consumeAndExecute(feedbackMode, _):
            XCTAssertEqual(feedbackMode, .close)
        case .ignore:
            XCTFail("Expected dock shortcut to be consumed and executed outside MC when enabled")
        }
    }

    func testShortcutRouterIgnoresDockShortcutWhenMissionControlInactiveAndDockActionsOutsideMCDisabled() {
        let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
            .first ?? NSRunningApplication.current
        var config = ShortcutConfiguration()
        config.isDockActionsOutsideMCEnabled = false

        let result = shortcutRouter.routeShortcut(
            keyCode: ShortcutActionRouter.kKeyW,
            flags: .maskCommand,
            location: CGPoint(x: 100, y: 100),
            config: config,
            isMissionControlActive: false,
            target: .dock(dockApp),
            service: mockService,
            activateApp: { _ in }
        )

        switch result {
        case .consumeAndExecute:
            XCTFail("Should ignore dock shortcut outside MC when disabled")
        case .ignore:
            break
        }
    }

    func testShortcutRouterExecutesAllDockShortcutsOutsideMCWhenEnabled() {
        let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
            .first ?? NSRunningApplication.current
        var config = ShortcutConfiguration()
        config.isDockActionsOutsideMCEnabled = true

        let qResult = shortcutRouter.routeShortcut(
            keyCode: ShortcutActionRouter.kKeyQ,
            flags: .maskCommand,
            location: CGPoint(x: 100, y: 100),
            config: config,
            isMissionControlActive: false,
            target: .dock(dockApp),
            service: mockService,
            activateApp: { _ in }
        )
        if case let .consumeAndExecute(mode, _) = qResult {
            XCTAssertEqual(mode, .quit)
        } else {
            XCTFail("Expected Cmd+Q on dock to execute")
        }

        let mResult = shortcutRouter.routeShortcut(
            keyCode: ShortcutActionRouter.kKeyM,
            flags: .maskCommand,
            location: CGPoint(x: 100, y: 100),
            config: config,
            isMissionControlActive: false,
            target: .dock(dockApp),
            service: mockService,
            activateApp: { _ in }
        )
        if case let .consumeAndExecute(mode, _) = mResult {
            XCTAssertEqual(mode, .minimize)
        } else {
            XCTFail("Expected Cmd+M on dock to execute")
        }

        let hResult = shortcutRouter.routeShortcut(
            keyCode: ShortcutActionRouter.kKeyH,
            flags: .maskCommand,
            location: CGPoint(x: 100, y: 100),
            config: config,
            isMissionControlActive: false,
            target: .dock(dockApp),
            service: mockService,
            activateApp: { _ in }
        )
        if case let .consumeAndExecute(mode, _) = hResult {
            XCTAssertEqual(mode, .hide)
        } else {
            XCTFail("Expected Cmd+H on dock to execute")
        }
    }

    // MARK: - Title bar actions outside Mission Control

    func testShortcutRouterExecutesTitleBarShortcutOutsideMCWhenEnabled() throws {
        var config = ShortcutConfiguration()
        config.isTitleBarActionsOutsideMCEnabled = true

        let result = try shortcutRouter.routeShortcut(
            keyCode: ShortcutActionRouter.kKeyW,
            flags: .maskCommand,
            location: CGPoint(x: 100, y: 100),
            config: config,
            isMissionControlActive: false,
            target: .window(XCTUnwrap(mockService.mockElement)),
            service: mockService,
            isTitleBarHover: true,
            activateApp: { _ in }
        )

        switch result {
        case let .consumeAndExecute(feedbackMode, _):
            XCTAssertEqual(feedbackMode, .close)
        case .ignore:
            XCTFail("Expected title-bar shortcut to be consumed outside MC when enabled")
        }
    }

    func testShortcutRouterIgnoresTitleBarShortcutOutsideMCWhenDisabled() throws {
        var config = ShortcutConfiguration()
        config.isTitleBarActionsOutsideMCEnabled = false

        let result = try shortcutRouter.routeShortcut(
            keyCode: ShortcutActionRouter.kKeyW,
            flags: .maskCommand,
            location: CGPoint(x: 100, y: 100),
            config: config,
            isMissionControlActive: false,
            target: .window(XCTUnwrap(mockService.mockElement)),
            service: mockService,
            isTitleBarHover: true,
            activateApp: { _ in }
        )

        switch result {
        case .consumeAndExecute:
            XCTFail("Should ignore title-bar shortcut outside MC when disabled")
        case .ignore:
            break
        }
    }

    func testShortcutRouterIgnoresWindowTitleShortcutWithoutTitleBarHover() throws {
        var config = ShortcutConfiguration()
        config.isTitleBarActionsOutsideMCEnabled = true

        let result = try shortcutRouter.routeShortcut(
            keyCode: ShortcutActionRouter.kKeyW,
            flags: .maskCommand,
            location: CGPoint(x: 100, y: 100),
            config: config,
            isMissionControlActive: false,
            target: .window(XCTUnwrap(mockService.mockElement)),
            service: mockService,
            isTitleBarHover: false,
            activateApp: { _ in }
        )

        switch result {
        case .consumeAndExecute:
            XCTFail("Should ignore window shortcut outside MC without title-bar hover")
        case .ignore:
            break
        }
    }

    func testGestureRouterRoutesAllGesturesToDockTargets() {
        let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
            .first ?? NSRunningApplication.current

        let gesturesToExpectedModes: [(GestureResult, CursorFeedbackOverlay.Mode)] = [
            (.pinchIn(atNormalized: (0.5, 0.5)), .close),
            (.cmdPinchIn(atNormalized: (0.5, 0.5)), .quit),
            (.pinchOut(atNormalized: (0.5, 0.5)), .fullscreen),
            (.cmdPinchOut(atNormalized: (0.5, 0.5)), .newWindow),
            (.swipeLeft(atNormalized: (0.5, 0.5)), .closeTab),
            (.cmdSwipeLeft(atNormalized: (0.5, 0.5)), .closeAllTabs),
            (.swipeRight(atNormalized: (0.5, 0.5)), .reopenTab),
            (.cmdSwipeRight(atNormalized: (0.5, 0.5)), .newWindow),
            (.swipeDown(atNormalized: (0.5, 0.5)), .maximize),
            (.cmdSwipeDown(atNormalized: (0.5, 0.5)), .maximize),
            (.swipeUp(atNormalized: (0.5, 0.5)), .minimize),
            (.cmdSwipeUp(atNormalized: (0.5, 0.5)), .hide),
            (.twoFingerDoubleTap, .reasonable),
            (.cmdTwoFingerDoubleTap, .almost)
        ]

        for (gesture, expectedMode) in gesturesToExpectedModes {
            let result = gestureRouter.routeGesture(
                gesture,
                at: CGPoint(x: 200, y: 200),
                target: .dock(dockApp),
                service: mockService,
                activateApp: { _ in }
            )
            if case let .execute(mode, _, _) = result {
                XCTAssertEqual(mode, expectedMode, "Gesture \(gesture) should route to \(expectedMode)")
            } else {
                XCTFail("Expected gesture \(gesture) on dock to execute")
            }
        }
    }

    // MARK: - Desktop navigation (move to next / previous desktop)

    func testGestureDefaultsNeverAssignDesktopNavigationActions() {
        for kind in GestureKind.allCases {
            for isCmd in [false, true] {
                XCTAssertNotEqual(
                    GestureDefaults.action(for: kind, isCmd: isCmd), .moveNextDesktop,
                    "\(kind) (cmd=\(isCmd)) must not be assigned by default"
                )
                XCTAssertNotEqual(
                    GestureDefaults.action(for: kind, isCmd: isCmd), .movePreviousDesktop,
                    "\(kind) (cmd=\(isCmd)) must not be assigned by default"
                )
            }
        }
    }

    /// Binds `action` to pinch-in on a scratch config, restoring any persisted
    /// mapping afterwards so the UserDefaults-backed defaults stay untouched.
    private func routePinchInBound(to action: GestureAction,
                                   target: TargetResolution) -> ResolvedGestureAction {
        let key = "mcsc.gestures.actions"
        let original = UserDefaults.standard.dictionary(forKey: key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        var config = ShortcutConfiguration()
        config.gestureActions[.pinchIn] = action
        return gestureRouter.routeGesture(
            .pinchIn(atNormalized: (0.5, 0.5)),
            at: CGPoint(x: 200, y: 200),
            target: target,
            service: mockService,
            activateApp: { _ in }
        )
    }

    func testMoveNextDesktopRoutesOnWindowTargetWithSpaceRightFeedback() throws {
        let result = try routePinchInBound(to: .moveNextDesktop, target: .window(XCTUnwrap(mockService.mockElement)))
        guard case let .execute(mode, _, _) = result else {
            return XCTFail("Expected moveNextDesktop on window to execute")
        }
        XCTAssertEqual(mode, .spaceRight)
    }

    func testMovePreviousDesktopRoutesOnWindowTargetWithSpaceLeftFeedback() throws {
        let result = try routePinchInBound(
            to: .movePreviousDesktop,
            target: .window(XCTUnwrap(mockService.mockElement))
        )
        guard case let .execute(mode, _, _) = result else {
            return XCTFail("Expected movePreviousDesktop on window to execute")
        }
        XCTAssertEqual(mode, .spaceLeft)
    }

    func testDesktopMoveOverDockTargetsFocusedAppWindow() {
        let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
            .first ?? NSRunningApplication.current

        let next = routePinchInBound(to: .moveNextDesktop, target: .dock(dockApp))
        guard case let .execute(nextMode, _, _) = next else {
            return XCTFail("Expected moveNextDesktop on dock to execute")
        }
        XCTAssertEqual(nextMode, .spaceRight)

        let previous = routePinchInBound(to: .movePreviousDesktop, target: .dock(dockApp))
        guard case let .execute(previousMode, _, _) = previous else {
            return XCTFail("Expected movePreviousDesktop on dock to execute")
        }
        XCTAssertEqual(previousMode, .spaceLeft)
    }
}

final class DesktopNavigationActionTests: XCTestCase {
    /// Closure-capture-friendly log; `MoveWindowToDesktopAction`'s injected
    /// side-effect closures append here instead of posting real events.
    private final class LogBox {
        var entries: [String] = []
        func append(_ entry: String) {
            entries.append(entry)
        }
    }

    func testSequenceHoldsMouseDownAcrossSwitchAndReleasesLast() {
        let log = LogBox()
        var action = MoveWindowToDesktopAction(direction: .next)
        action.postMouseEvent = { (type: CGEventType, _: CGPoint) in log.append("mouse \(type.rawValue)") }
        action.warpCursor = { _ in log.append("warp") }
        action.postEscapeKey = { log.append("escape") }
        action.sendSpaceSwitchShortcut = { log.append("switch \($0)") }
        action.waitFor = { _ in }

        action.runSequence(grabPoint: CGPoint(x: 140, y: 112), dismissMissionControl: false)

        // mouseMoved = 5, leftMouseDown = 1, leftMouseDragged = 6, leftMouseUp = 2.
        XCTAssertEqual(log.entries.first, "mouse 5")
        XCTAssertTrue(log.entries.contains("warp"))
        guard let down = log.entries.firstIndex(of: "mouse 1"),
              let spaceSwitch = log.entries.firstIndex(of: "switch next"),
              let up = log.entries.firstIndex(of: "mouse 2") else {
            return XCTFail("Missing expected events: \(log.entries)")
        }
        XCTAssertLessThan(down, spaceSwitch, "Space switch must fire while mouse is held down")
        XCTAssertLessThan(spaceSwitch, up, "Release must happen after the Space switch animation")
        XCTAssertEqual(log.entries.last, "mouse 2")
    }

    func testMissionControlDismissedBeforeDragWhenActive() {
        let log = LogBox()
        var action = MoveWindowToDesktopAction(direction: .previous)
        action.postMouseEvent = { _, _ in }
        action.warpCursor = { _ in }
        action.postEscapeKey = { log.append("escape") }
        action.sendSpaceSwitchShortcut = { log.append("switch \($0)") }
        action.waitFor = { _ in }

        action.runSequence(grabPoint: .zero, dismissMissionControl: true)

        XCTAssertEqual(log.entries.first, "escape", "Mission Control must close first")
        XCTAssertEqual(log.entries.dropFirst().first, "switch previous")
    }

    func testNoEscapeWhenMissionControlInactive() {
        let log = LogBox()
        var action = MoveWindowToDesktopAction(direction: .next)
        action.postMouseEvent = { _, _ in }
        action.warpCursor = { _ in }
        action.postEscapeKey = { log.append("escape") }
        action.sendSpaceSwitchShortcut = { _ in }
        action.waitFor = { _ in }

        action.runSequence(grabPoint: .zero, dismissMissionControl: false)

        XCTAssertFalse(log.entries.contains("escape"))
    }

    func testDirectionKeyCodesMatchDockSpaceShortcuts() {
        XCTAssertEqual(MoveWindowToDesktopAction.Direction.next.arrowKeyCode, 124)
        XCTAssertEqual(MoveWindowToDesktopAction.Direction.previous.arrowKeyCode, 123)
    }
}

final class MockMountedVolumeService: MountedVolumeServiceProtocol {
    var mockEjectablePath: String?
    var ejectVolumeCalledWith: String?
    var ejectVolumeSuccess: Bool = true

    func ejectableVolumePath(forDocumentPath _: String?, windowTitle _: String?) -> String? {
        mockEjectablePath
    }

    func ejectVolume(at mountPath: String, completion: @escaping (Bool) -> Void) {
        ejectVolumeCalledWith = mountPath
        completion(ejectVolumeSuccess)
    }
}
