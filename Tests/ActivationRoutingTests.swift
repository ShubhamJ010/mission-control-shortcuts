import Foundation
import XCTest

final class ActivationRoutingTests: XCTestCase {
    private var mockService: MockAccessibilityService!
    private var actionRegistry: ActionRegistry!
    private var gestureRouter: GestureActionRouter!
    private var shortcutRouter: ShortcutActionRouter!

    override func setUp() {
        super.setUp()
        mockService = MockAccessibilityService()
        mockService.mockElement = AXUIElementCreateSystemWide()
        actionRegistry = ActionRegistry()
        gestureRouter = GestureActionRouter(actions: actionRegistry)
        shortcutRouter = ShortcutActionRouter(actions: actionRegistry)

        for entry in ShortcutConfiguration.toggleDefaults {
            UserDefaults.standard.removeObject(forKey: entry.key)
        }
        UserDefaults.standard.removeObject(forKey: ShortcutConfiguration.bindingsStorageKey)
        UserDefaults.standard.removeObject(forKey: ShortcutConfiguration.gestureActionsStorageKey)
        UserDefaults.standard.removeObject(forKey: ShortcutConfiguration.cmdGestureActionsStorageKey)
    }

    private func routePinchInBound(
        to action: GestureAction,
        target: TargetResolution,
        activateApp: @escaping (CGPoint) -> Void
    ) -> ResolvedGestureAction {
        var config = ShortcutConfiguration()
        config.gestureActions[.pinchIn] = action
        return gestureRouter.routeGesture(
            .pinchIn(atNormalized: (0.5, 0.5)),
            at: CGPoint(x: 200, y: 200),
            target: target,
            service: mockService,
            activateApp: activateApp
        )
    }

    func testGestureRouterActivatesAppForFocusActionsOnWindowTarget() throws {
        let focusActions: [GestureAction] = [
            .closeTab, .reopenTab, .newTab, .newWindow,
            .toggleFullscreen, .fillScreen, .almostMaximize,
            .makeLarger, .makeSmaller, .reasonableSize, .unminimizeAll,
            .leftHalfSnap, .rightHalfSnap, .leftThirdSnap, .rightThirdSnap
        ]

        for action in focusActions {
            var activateAppCalled = false
            let result = try routePinchInBound(
                to: action,
                target: .window(XCTUnwrap(mockService.mockElement)),
                activateApp: { _ in activateAppCalled = true }
            )

            guard case let .execute(_, _, executionBlock) = result else {
                XCTFail("Expected \(action) on window to execute")
                continue
            }
            executionBlock()
            XCTAssertTrue(activateAppCalled, "Expected \(action) on window to invoke activateApp")
        }
    }

    func testGestureRouterActivatesAppForFocusActionsOnDockTarget() {
        let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
            .first ?? NSRunningApplication.current

        let focusActions: [GestureAction] = [
            .closeTab, .reopenTab, .newTab, .newWindow,
            .toggleFullscreen, .fillScreen, .almostMaximize,
            .makeLarger, .makeSmaller, .reasonableSize, .unminimizeAll
        ]

        for action in focusActions {
            var activateAppCalled = false
            let result = routePinchInBound(
                to: action,
                target: .dock(dockApp),
                activateApp: { _ in activateAppCalled = true }
            )

            guard case let .execute(_, _, executionBlock) = result else {
                XCTFail("Expected \(action) on dock to execute")
                continue
            }
            executionBlock()
            XCTAssertTrue(activateAppCalled, "Expected \(action) on dock to invoke activateApp")
        }
    }

    func testGestureRouterDoesNotActivateAppForQuitHideMinimize() throws {
        let nonFocusActions: [GestureAction] = [
            .quitApp, .hideApp, .minimize, .closeWindow, .moveNextDesktop, .movePreviousDesktop
        ]

        for action in nonFocusActions {
            var activateAppCalled = false
            let result = try routePinchInBound(
                to: action,
                target: .window(XCTUnwrap(mockService.mockElement)),
                activateApp: { _ in activateAppCalled = true }
            )

            guard case let .execute(_, _, executionBlock) = result else {
                XCTFail("Expected \(action) on window to execute")
                continue
            }
            executionBlock()
            XCTAssertFalse(activateAppCalled, "Expected \(action) to NOT invoke activateApp")
        }
    }

    func testShortcutRouterActivatesAppForShiftResizeAndTabShortcuts() {
        var config = ShortcutConfiguration()
        config.isCmdShiftTEnabled = true
        config.isFillScreenEnabled = true
        config.isReasonableSizeEnabled = true

        var activateCalled = false
        let reopenResult = shortcutRouter.routeShortcut(
            keyCode: ShortcutActionRouter.kKeyT,
            flags: [.maskCommand, .maskShift],
            location: CGPoint(x: 100, y: 100),
            config: config,
            isMissionControlActive: true,
            target: .none,
            service: mockService,
            activateApp: { _ in activateCalled = true }
        )

        guard case let .consumeAndExecute(_, executionBlock) = reopenResult else {
            return XCTFail("Expected Cmd+Shift+T to execute")
        }
        executionBlock()
        XCTAssertTrue(activateCalled, "Cmd+Shift+T must call activateApp")
    }
}
