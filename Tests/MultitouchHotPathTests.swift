import Cocoa
import XCTest

@MainActor
final class MultitouchHotPathTests: XCTestCase {
    private var mockAccessibility: MockAccessibilityService!
    private var mockMissionControl: MockSettingsMissionControlService!
    private var mockEventTap: MockSettingsEventTapService!
    private var launchAtLogin: LaunchAtLoginService!
    private var viewModel: ShortcutViewModel!

    override func setUp() {
        super.setUp()
        clearPersistedSettings()
        mockAccessibility = MockAccessibilityService()
        mockAccessibility.mockElement = AXUIElementCreateSystemWide()
        mockMissionControl = MockSettingsMissionControlService()
        mockEventTap = MockSettingsEventTapService()
        launchAtLogin = LaunchAtLoginService()

        viewModel = ShortcutViewModel(
            eventTapService: mockEventTap,
            accessibilityService: mockAccessibility,
            missionControlService: mockMissionControl,
            launchAtLoginService: launchAtLogin
        )
        viewModel.isGesturesEnabled = true
        viewModel.isTitleBarActionsOutsideMCEnabled = true
        viewModel.isDockActionsOutsideMCEnabled = true
    }

    override func tearDown() {
        viewModel.stop()
        viewModel = nil
        launchAtLogin = nil
        mockEventTap = nil
        mockMissionControl = nil
        mockAccessibility = nil
        clearPersistedSettings()
        super.tearDown()
    }

    private func clearPersistedSettings() {
        for entry in ShortcutConfiguration.toggleDefaults {
            UserDefaults.standard.removeObject(forKey: entry.key)
        }
        UserDefaults.standard.removeObject(forKey: ShortcutConfiguration.bindingsStorageKey)
        UserDefaults.standard.removeObject(forKey: ShortcutConfiguration.gestureActionsStorageKey)
        UserDefaults.standard.removeObject(forKey: ShortcutConfiguration.cmdGestureActionsStorageKey)
    }

    private func makeTouch(id: Int32, x: Float, y: Float) -> TouchPoint {
        TouchPoint(identifier: id, state: 4, normalizedX: x, normalizedY: y, size: 1.0)
    }

    // MARK: - Hot Path Gating Tests

    func testSingleFingerFrameBypassesAXEntirely() {
        let singleTouch = [makeTouch(id: 1, x: 0.5, y: 0.5)]

        // Deliver multiple 1-finger frames across time
        viewModel.multitouchService.onFrame?(singleTouch, 1.0)
        viewModel.multitouchService.onFrame?(singleTouch, 1.04)
        viewModel.multitouchService.onFrame?(singleTouch, 1.08)

        XCTAssertEqual(
            mockAccessibility.getElementCallCount,
            0,
            "1-finger frames must early exit with 0 AX IPC calls"
        )
        XCTAssertFalse(
            viewModel.dockSuppressor.isSuppressing,
            "1 finger must not activate dock suppression"
        )
    }

    func testEmptyTouchFrameResetsHoldAndEngineWithoutAX() {
        // First simulate a 2-finger frame to establish tracking
        let twoTouches = [makeTouch(id: 1, x: 0.5, y: 0.5), makeTouch(id: 2, x: 0.6, y: 0.5)]
        viewModel.multitouchService.onFrame?(twoTouches, 1.0)

        let initialAXCalls = mockAccessibility.getElementCallCount

        // Now deliver touch-lift (empty frame)
        viewModel.multitouchService.onFrame?([], 1.1)

        XCTAssertEqual(
            mockAccessibility.getElementCallCount,
            initialAXCalls,
            "Empty frame (finger lift) must not incur any AX hit-tests"
        )
        XCTAssertFalse(
            viewModel.dockSuppressor.isSuppressing,
            "Finger lift must reset dock suppression"
        )
        XCTAssertFalse(
            viewModel.holdDetector.isHoldActive,
            "Finger lift must reset hold detector"
        )
    }

    func testTwoFingerHoldOnlyQueriesAXOnActivationFrame() {
        viewModel.isTwoFingerHoldEnabled = true
        viewModel.twoFingerHoldDuration = 0.4

        let curPt = viewModel.currentAXMouseLocation()
        mockAccessibility.mockWindow = mockAccessibility.mockElement
        mockAccessibility.mockFrame = CGRect(x: curPt.x - 50, y: curPt.y - 10, width: 800, height: 600)

        let t0 = [makeTouch(id: 1, x: 0.5, y: 0.5), makeTouch(id: 2, x: 0.6, y: 0.5)]

        // Frames before hold threshold (0.0s, 0.1s, 0.2s, 0.3s)
        viewModel.multitouchService.onFrame?(t0, 1.0)
        viewModel.multitouchService.onFrame?(t0, 1.1)
        viewModel.multitouchService.onFrame?(t0, 1.2)
        viewModel.multitouchService.onFrame?(t0, 1.3)

        XCTAssertEqual(
            mockAccessibility.getElementCallCount,
            0,
            "Stationary frames before hold threshold must not query AX"
        )

        // Threshold reached at +0.45s (> 0.4s duration): hold activates over title bar
        viewModel.multitouchService.onFrame?(t0, 1.45)
        XCTAssertTrue(viewModel.holdDetector.isHoldActive, "Hold must become active at duration threshold")
        XCTAssertEqual(
            mockAccessibility.getElementCallCount,
            1,
            "Hold activation should query AX target region exactly once"
        )

        // Subsequent frames while held (1.55s, 1.65s)
        viewModel.multitouchService.onFrame?(t0, 1.55)
        viewModel.multitouchService.onFrame?(t0, 1.65)

        XCTAssertEqual(
            mockAccessibility.getElementCallCount,
            1,
            "Subsequent frames while held must NOT re-query AX"
        )
    }

    func testOneFingerLiftBeforeThresholdAbortsHoldDetector() {
        viewModel.isTwoFingerHoldEnabled = true
        viewModel.twoFingerHoldDuration = 0.4

        let t0 = [makeTouch(id: 1, x: 0.5, y: 0.5), makeTouch(id: 2, x: 0.6, y: 0.5)]
        viewModel.multitouchService.onFrame?(t0, 1.0)

        // 1 finger lifted at 0.2s (before 0.4s threshold)
        let singleTouch = [makeTouch(id: 1, x: 0.5, y: 0.5)]
        viewModel.multitouchService.onFrame?(singleTouch, 1.2)

        XCTAssertFalse(
            viewModel.holdDetector.isHoldActive,
            "Lifting one finger before hold threshold must cleanly abort hold detector to idle"
        )
    }

    func testOneFingerLiftAfterHoldExpiresAfterLatchDuration() {
        viewModel.isTwoFingerHoldEnabled = true
        viewModel.twoFingerHoldDuration = 0.4

        let curPt = viewModel.currentAXMouseLocation()
        mockAccessibility.mockWindow = mockAccessibility.mockElement
        mockAccessibility.mockFrame = CGRect(x: curPt.x - 50, y: curPt.y - 10, width: 800, height: 600)

        let t0 = [makeTouch(id: 1, x: 0.5, y: 0.5), makeTouch(id: 2, x: 0.6, y: 0.5)]
        viewModel.multitouchService.onFrame?(t0, 1.0)
        viewModel.multitouchService.onFrame?(t0, 1.45)
        XCTAssertTrue(viewModel.holdDetector.isHoldActive, "Hold must become active")

        // 1 finger lifted at 1.55s -> enters latch grace window
        let singleTouch = [makeTouch(id: 1, x: 0.5, y: 0.5)]
        viewModel.multitouchService.onFrame?(singleTouch, 1.55)
        XCTAssertTrue(viewModel.holdDetector.isHoldActive, "Modifier stays latched during latchDuration grace period")

        // Beyond 0.8s latch duration (1.55 + 0.85 = 2.4s)
        viewModel.multitouchService.onFrame?(singleTouch, 2.45)
        XCTAssertFalse(
            viewModel.holdDetector.isHoldActive,
            "Hold modifier must expire after latch duration passes"
        )
    }

    func testHoldOnInvalidRegionResetsHoldModifier() {
        viewModel.isTwoFingerHoldEnabled = true
        viewModel.twoFingerHoldDuration = 0.4
        viewModel.isTitleBarActionsOutsideMCEnabled = false
        viewModel.isDockActionsOutsideMCEnabled = false
        mockMissionControl.isMissionControlActive = false

        let t0 = [makeTouch(id: 1, x: 0.5, y: 0.5), makeTouch(id: 2, x: 0.6, y: 0.5)]
        viewModel.multitouchService.onFrame?(t0, 1.0)
        viewModel.multitouchService.onFrame?(t0, 1.45)

        XCTAssertFalse(
            viewModel.holdDetector.isHoldActive,
            "Hold on invalid target region must reset detector immediately"
        )
    }

    func testOutsideMCNonTitleBarGestureIgnoredByRouter() {
        let registry = ActionRegistry()
        let router = GestureActionRouter(actions: registry)
        let element = AXUIElementCreateSystemWide()

        let nonTitleBarResult = router.routeGesture(
            .pinchIn(atNormalized: (0.5, 0.5)),
            at: CGPoint(x: 200, y: 200),
            target: .window(element),
            isMissionControlActive: false,
            service: mockAccessibility,
            isTitleBarHover: false,
            activateApp: { _ in }
        )

        switch nonTitleBarResult {
        case .none:
            break // Success: correctly ignored
        case .execute:
            XCTFail("Gesture outside Mission Control and not on title bar must be ignored")
        }

        let titleBarResult = router.routeGesture(
            .pinchIn(atNormalized: (0.5, 0.5)),
            at: CGPoint(x: 200, y: 200),
            target: .window(element),
            isMissionControlActive: false,
            service: mockAccessibility,
            isTitleBarHover: true,
            activateApp: { _ in }
        )

        switch titleBarResult {
        case .execute:
            break // Success: routed when hovering title bar
        case .none:
            XCTFail("Gesture on title bar outside Mission Control must be executed")
        }
    }
}
