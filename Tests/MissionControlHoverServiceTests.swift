import Cocoa
import Foundation
import XCTest

@MainActor
final class MissionControlHoverServiceTests: XCTestCase {
    private var mockService: MockAccessibilityService!
    private var isMissionControlActive = false
    private var hoverService: MissionControlHoverService!

    override func setUp() {
        super.setUp()
        mockService = MockAccessibilityService()
        isMissionControlActive = false
        hoverService = MissionControlHoverService(
            accessibilityService: mockService,
            isMissionControlActiveProvider: { [weak self] in
                self?.isMissionControlActive ?? false
            }
        )
    }

    override func tearDown() {
        hoverService.stop()
        hoverService = nil
        mockService = nil
        super.tearDown()
    }

    func testInitialStateIsNotTracking() {
        XCTAssertFalse(hoverService.isTracking)
        XCTAssertTrue(hoverService.isEnabled)
    }

    func testStartAndStopTracking() {
        hoverService.start()
        XCTAssertTrue(hoverService.isTracking)

        hoverService.stop()
        XCTAssertFalse(hoverService.isTracking)
    }

    func testTogglingEnabledState() {
        hoverService.isEnabled = false
        XCTAssertFalse(hoverService.isEnabled)

        hoverService.isEnabled = true
        XCTAssertTrue(hoverService.isEnabled)
    }

    func testMouseDownWhenNotActiveReturnsFalse() {
        let result = hoverService.handleMouseDown(at: CGPoint(x: 100, y: 100))
        XCTAssertFalse(result)
    }

    func testFlagsChangedDoesNotCrash() {
        hoverService.start()
        hoverService.handleFlagsChanged(cmdPressed: true, optionPressed: false, controlPressed: false)
        hoverService.handleFlagsChanged(cmdPressed: false, optionPressed: true, controlPressed: false)
        hoverService.handleFlagsChanged(cmdPressed: false, optionPressed: false, controlPressed: true)
        hoverService.handleFlagsChanged(cmdPressed: true, optionPressed: true, controlPressed: true)
        hoverService.handleFlagsChanged(cmdPressed: false, optionPressed: false, controlPressed: false)
    }

    func testControlKeySelectsFullscreenMode() {
        hoverService.start()
        // No modifiers → close (default)
        hoverService.handleFlagsChanged(cmdPressed: false, optionPressed: false, controlPressed: false)
        XCTAssertEqual(hoverService.currentOverlayMode, .close)
        // Control held → fullscreen
        hoverService.handleFlagsChanged(cmdPressed: false, optionPressed: false, controlPressed: true)
        XCTAssertEqual(hoverService.currentOverlayMode, .fullscreen)
        // Release → back to close
        hoverService.handleFlagsChanged(cmdPressed: false, optionPressed: false, controlPressed: false)
        XCTAssertEqual(hoverService.currentOverlayMode, .close)
    }

    // MARK: - Space-change observer lifecycle (#2)

    func testStartRegistersSpaceChangeObserver() {
        XCTAssertNil(hoverService.spaceChangeObserver)
        hoverService.start()
        XCTAssertNotNil(hoverService.spaceChangeObserver)
    }

    func testStopRemovesSpaceChangeObserver() {
        hoverService.start()
        XCTAssertNotNil(hoverService.spaceChangeObserver)
        hoverService.stop()
        XCTAssertNil(hoverService.spaceChangeObserver)
    }

    func testDoubleStartDoesNotDuplicateObserver() {
        hoverService.start()
        let first = hoverService.spaceChangeObserver
        hoverService.start() // no-op guard
        XCTAssertTrue(hoverService.spaceChangeObserver === first)
    }

    // MARK: - Window-list dedup (#3)

    func testInitialWindowCountIsZero() {
        XCTAssertEqual(hoverService._testWindowCount, 0)
    }

    // MARK: - Space change must not flash the preview overlay

    /// Builds a minimal tracked-window entry covering `rect`, shaped exactly
    /// like the CGWindowList dictionaries `fetchWindows()` produces.
    private func makeWindowInfo(at rect: CGRect) -> [String: Any] {
        [
            "kCGWindowBounds": [
                "X": rect.origin.x,
                "Y": rect.origin.y,
                "Width": rect.width,
                "Height": rect.height
            ]
        ]
    }

    /// Regression: a plain desktop switch (Ctrl+←/→ or three-finger swipe)
    /// fires `activeSpaceDidChangeNotification`. The handler used to recompute
    /// the hover overlay unconditionally, flashing the close button over
    /// whatever window sat under the cursor until the next mouse move hid it.
    /// Outside Mission Control the overlay must stay hidden.
    func testSpaceChangeOutsideMissionControlDoesNotShowOverlay() {
        let overlay = PreviewCloseButtonOverlay()
        let service = MissionControlHoverService(
            accessibilityService: mockService,
            isMissionControlActiveProvider: { [weak self] in
                self?.isMissionControlActive ?? false
            },
            overlay: overlay
        )
        service.start()
        defer { service.stop() }

        // A large window sits directly under the cursor, so a naive
        // `updateOverlay` call would show the close button.
        service._testSeedWindows([makeWindowInfo(at: CGRect(x: 0, y: 0, width: 800, height: 600))])
        isMissionControlActive = false

        service.handleSpaceChange(at: CGPoint(x: 400, y: 300))

        XCTAssertFalse(overlay.isVisible)
    }

    /// While Mission Control *is* open, a Space change must keep refreshing
    /// the overlay for the new Space's windows under the cursor.
    func testSpaceChangeInsideMissionControlShowsOverlayUnderCursor() {
        let overlay = PreviewCloseButtonOverlay()
        let service = MissionControlHoverService(
            accessibilityService: mockService,
            isMissionControlActiveProvider: { [weak self] in
                self?.isMissionControlActive ?? false
            },
            overlay: overlay
        )
        service.start()
        defer { service.stop() }

        service._testSeedWindows([makeWindowInfo(at: CGRect(x: 100, y: 100, width: 400, height: 300))])
        isMissionControlActive = true

        service.handleSpaceChange(at: CGPoint(x: 250, y: 250))

        XCTAssertTrue(overlay.isVisible)

        // Moving off every tracked window hides it again.
        service.handleSpaceChange(at: CGPoint(x: 900, y: 900))
        XCTAssertFalse(overlay.isVisible)
    }

    // MARK: - Open / close / reopen state machine + AXObserver unification

    /// A helper that builds a hover service wired to a recording Mission
    /// Control service and an injected overlay, mirroring production wiring.
    private func makeUnifiedService(overlay: PreviewCloseButtonOverlay,
                                    mcService: MockMissionControlService) -> MissionControlHoverService {
        MissionControlHoverService(
            accessibilityService: mockService,
            isMissionControlActiveProvider: { [weak mcService] in
                mcService?.isMissionControlActive ?? false
            },
            missionControlService: mcService,
            overlay: overlay
        )
    }

    /// The Dock AXObserver open transition must be forwarded to the shared
    /// detector via `markActive(true)` so every consumer sees the instant
    /// signal instead of the lagging window-list scan.
    func testDockNotificationOpenForwardsMarkActiveTrue() {
        let mcService = MockMissionControlService()
        let overlay = PreviewCloseButtonOverlay()
        let service = makeUnifiedService(overlay: overlay, mcService: mcService)
        service.start()
        defer { service.stop() }

        service.handleDockNotification("AXExposeShowAllWindows")

        XCTAssertEqual(mcService.markActiveCalls, [true])
        XCTAssertTrue(mcService.isMissionControlActive)
    }

    /// `AXExposeExit` must forward `markActive(false)` and clear the tracked
    /// window list so no stale entries persist before the next open.
    func testAxExposeExitForwardsMarkActiveFalseAndClearsWindowList() {
        let mcService = MockMissionControlService()
        let overlay = PreviewCloseButtonOverlay()
        let service = makeUnifiedService(overlay: overlay, mcService: mcService)
        service.start()
        defer { service.stop() }

        // Open: seed windows and mark active.
        service.handleDockNotification("AXExposeShowAllWindows")
        service._testSeedWindows([makeWindowInfo(at: CGRect(x: 0, y: 0, width: 100, height: 100))])
        XCTAssertEqual(service._testWindowCount, 1)

        // Close: must clear the window list and forward false.
        service.handleDockNotification("AXExposeExit")

        XCTAssertEqual(mcService.markActiveCalls, [true, false])
        XCTAssertFalse(mcService.isMissionControlActive)
        XCTAssertEqual(service._testWindowCount, 0)
    }

    /// `AXExposeShowDesktop` must keep Mission Control inactive rather than
    /// falsely treating it as an active Exposé session.
    func testAxExposeShowDesktopDoesNotActivateMissionControl() {
        let mcService = MockMissionControlService()
        let overlay = PreviewCloseButtonOverlay()
        let service = makeUnifiedService(overlay: overlay, mcService: mcService)
        service.start()
        defer { service.stop() }

        service.handleDockNotification("AXExposeShowDesktop")

        XCTAssertEqual(mcService.markActiveCalls, [false])
        XCTAssertFalse(mcService.isMissionControlActive)
        XCTAssertFalse(service.isMissionControlActive)
        XCTAssertEqual(service._testWindowCount, 0)
    }

    /// `AXExposeShowDesktop` after `AXExposeShowAllWindows` must deactivate and
    /// clear the tracked window list just like `AXExposeExit`.
    func testAxExposeShowDesktopWhileActiveDeactivatesAndClearsSession() {
        let mcService = MockMissionControlService()
        let overlay = PreviewCloseButtonOverlay()
        let service = makeUnifiedService(overlay: overlay, mcService: mcService)
        service.start()
        defer { service.stop() }

        service.handleDockNotification("AXExposeShowAllWindows")
        service._testSeedWindows([makeWindowInfo(at: CGRect(x: 0, y: 0, width: 100, height: 100))])
        XCTAssertEqual(service._testWindowCount, 1)

        service.handleDockNotification("AXExposeShowDesktop")

        XCTAssertEqual(mcService.markActiveCalls, [true, false])
        XCTAssertFalse(mcService.isMissionControlActive)
        XCTAssertFalse(service.isMissionControlActive)
        XCTAssertEqual(service._testWindowCount, 0)
    }

    /// Open → close → reopen must restore a working session: the overlay
    /// reappears on reopen and the window poll timer / keyboard tap are
    /// recreated. Verifies fix #4 (timer not restarted after reopen) and the
    /// unification path round-trips cleanly.
    func testOpenCloseReopenRestoresOverlaySession() {
        let mcService = MockMissionControlService()
        let overlay = PreviewCloseButtonOverlay()
        let service = makeUnifiedService(overlay: overlay, mcService: mcService)
        service.start()
        defer { service.stop() }

        // Open
        service.handleDockNotification("AXExposeShowAllWindows")
        service._testSeedWindows([makeWindowInfo(at: CGRect(x: 100, y: 100, width: 400, height: 300))])
        isMissionControlActive = true

        // Close
        service.handleDockNotification("AXExposeExit")
        isMissionControlActive = false
        XCTAssertFalse(overlay.isVisible)

        // Reopen
        service._testSeedWindows([makeWindowInfo(at: CGRect(x: 100, y: 100, width: 400, height: 300))])
        service.handleDockNotification("AXExposeShowAllWindows")
        isMissionControlActive = true

        // The unified detector saw true → false → true.
        XCTAssertEqual(mcService.markActiveCalls, [true, false, true])

        // A space-change refresh under the cursor must show the overlay again,
        // proving the window poll / overlay session was restored on reopen.
        service.handleSpaceChange(at: CGPoint(x: 250, y: 250))
        XCTAssertTrue(overlay.isVisible)
    }

    // MARK: - Instant Exit Key Triggers

    func testF3KeyDownHidesOverlayAndPassesThrough() {
        let overlay = PreviewCloseButtonOverlay()
        let service = MissionControlHoverService(
            accessibilityService: mockService,
            isMissionControlActiveProvider: { true },
            overlay: overlay
        )
        service.start()
        defer { service.stop() }

        service._testSeedWindows([makeWindowInfo(at: CGRect(x: 100, y: 100, width: 400, height: 300))])
        service.handleSpaceChange(at: CGPoint(x: 250, y: 250))
        XCTAssertTrue(overlay.isVisible)

        // F3 (keyCode 99)
        let handled = service.handleKeyDown(keyCode: 99, characters: nil, flags: [])
        XCTAssertFalse(handled, "Exit key must pass through to macOS WindowServer")
        XCTAssertFalse(overlay.isVisible, "Overlay must be hidden immediately")
    }

    func testHardwareMCKey160HidesOverlayAndPassesThrough() {
        let overlay = PreviewCloseButtonOverlay()
        let service = MissionControlHoverService(
            accessibilityService: mockService,
            isMissionControlActiveProvider: { true },
            overlay: overlay
        )
        service.start()
        defer { service.stop() }

        service._testSeedWindows([makeWindowInfo(at: CGRect(x: 100, y: 100, width: 400, height: 300))])
        service.handleSpaceChange(at: CGPoint(x: 250, y: 250))
        XCTAssertTrue(overlay.isVisible)

        // Hardware MC Key (keyCode 160)
        let handled = service.handleKeyDown(keyCode: 160, characters: nil, flags: [])
        XCTAssertFalse(handled, "Exit key must pass through to macOS WindowServer")
        XCTAssertFalse(overlay.isVisible, "Overlay must be hidden immediately")
    }

    func testControlUpArrowHidesOverlayAndPassesThrough() {
        let overlay = PreviewCloseButtonOverlay()
        let service = MissionControlHoverService(
            accessibilityService: mockService,
            isMissionControlActiveProvider: { true },
            overlay: overlay
        )
        service.start()
        defer { service.stop() }

        service._testSeedWindows([makeWindowInfo(at: CGRect(x: 100, y: 100, width: 400, height: 300))])
        service.handleSpaceChange(at: CGPoint(x: 250, y: 250))
        XCTAssertTrue(overlay.isVisible)

        // Ctrl + Up Arrow (keyCode 126 + maskControl)
        let handled = service.handleKeyDown(keyCode: 126, characters: nil, flags: [.maskControl])
        XCTAssertFalse(handled, "Ctrl+Up must pass through to macOS WindowServer")
        XCTAssertFalse(overlay.isVisible, "Overlay must be hidden immediately")
    }

    func testEscapeWithEmptyQueryHidesOverlayAndPassesThrough() {
        let overlay = PreviewCloseButtonOverlay()
        let service = MissionControlHoverService(
            accessibilityService: mockService,
            isMissionControlActiveProvider: { true },
            overlay: overlay
        )
        service.start()
        defer { service.stop() }

        service._testSeedWindows([makeWindowInfo(at: CGRect(x: 100, y: 100, width: 400, height: 300))])
        service.handleSpaceChange(at: CGPoint(x: 250, y: 250))
        XCTAssertTrue(overlay.isVisible)

        // Escape (keyCode 53) with empty search query
        let handled = service.handleKeyDown(keyCode: 53, characters: nil, flags: [])
        XCTAssertFalse(handled, "Escape on empty query must pass through to dismiss MC")
        XCTAssertFalse(overlay.isVisible, "Overlay must be hidden immediately")
    }

    func testPreviewCloseButtonOverlayCalculatesCurrentAXRectAndResetsOnHide() {
        let overlay = PreviewCloseButtonOverlay()
        let rect = CGRect(x: 200, y: 150, width: 400, height: 300)
        overlay.show(at: rect)

        XCTAssertTrue(overlay.isVisible)
        XCTAssertFalse(overlay.currentAXRect.isEmpty)
        XCTAssertEqual(overlay.currentAXRect.width, PreviewCloseButtonOverlay.buttonDimension)
        XCTAssertEqual(overlay.currentAXRect.height, PreviewCloseButtonOverlay.buttonDimension)

        overlay.hide()
        XCTAssertFalse(overlay.isVisible)
        XCTAssertEqual(overlay.currentAXRect, .zero)
    }

    func testActivePreviewTileHysteresisPreventsMovementOnMouseMoveWithinPreview() {
        let overlay = PreviewCloseButtonOverlay()
        let service = MissionControlHoverService(
            accessibilityService: mockService,
            isMissionControlActiveProvider: { [weak self] in self?.isMissionControlActive ?? false },
            overlay: overlay
        )
        service.start()
        defer { service.stop() }

        isMissionControlActive = true
        let previewRect = CGRect(x: 100, y: 100, width: 300, height: 200)
        let dummyTile = AXUIElementCreateSystemWide()
        mockService.mockElement = dummyTile
        mockService.mockPreviewTile = (tileElement: dummyTile, windowID: CGWindowID(777))
        mockService.mockFrame = previewRect

        let winInfo: [String: Any] = [
            kCGWindowNumber as String: CGWindowID(777),
            "kCGWindowBounds": [
                "X": previewRect.origin.x,
                "Y": previewRect.origin.y,
                "Width": previewRect.width,
                "Height": previewRect.height
            ]
        ]
        service._testSeedWindows([winInfo])

        // First mouse move inside the preview tile: activates hover overlay
        service.updateOverlay(at: CGPoint(x: 150, y: 150))
        XCTAssertTrue(overlay.isVisible)
        XCTAssertEqual(service.currentPreviewFrame, previewRect)
        let initialAXRect = overlay.currentAXRect
        let callCountAfterFirstHover = mockService.getElementCallCount

        // Second mouse move inside the preview tile: hysteresis kicks in, no AX query, no reposition
        service.updateOverlay(at: CGPoint(x: 200, y: 180))
        XCTAssertTrue(overlay.isVisible)
        XCTAssertEqual(overlay.currentAXRect, initialAXRect)
        XCTAssertEqual(mockService.getElementCallCount, callCountAfterFirstHover, "Hysteresis must prevent AX query while mouse stays within active tile")

        // Mouse leaves preview tile: overlay hides
        mockService.mockElement = nil
        mockService.mockPreviewTile = nil
        service.updateOverlay(at: CGPoint(x: 50, y: 50))
        XCTAssertFalse(overlay.isVisible)
        XCTAssertNil(service.currentPreviewFrame)
    }

    func testPreviewOverlayPositioningCenteredOnVertexAndCloseButtonFrame() {
        let overlay = PreviewCloseButtonOverlay()
        let previewRect = CGRect(x: 200, y: 100, width: 400, height: 300)

        // 1. Centered on the top-left vertex of the preview thumbnail
        overlay.show(for: previewRect)
        XCTAssertTrue(overlay.isVisible)
        let expectedCenterX = previewRect.minX
        let expectedCenterY = previewRect.minY
        XCTAssertEqual(overlay.currentAXRect.midX, expectedCenterX, accuracy: 0.5)
        XCTAssertEqual(overlay.currentAXRect.midY, expectedCenterY, accuracy: 0.5)
        XCTAssertEqual(overlay.currentAXRect.origin.x, previewRect.minX - PreviewCloseButtonOverlay.buttonDimension / 2.0, accuracy: 0.5)
        XCTAssertEqual(overlay.currentAXRect.origin.y, previewRect.minY - PreviewCloseButtonOverlay.buttonDimension / 2.0, accuracy: 0.5)

        // 2. Aligned with native close button AX frame if provided
        let closeBtnRect = CGRect(x: 210, y: 110, width: 20, height: 20)
        overlay.show(for: previewRect, closeButtonFrame: closeBtnRect)
        XCTAssertTrue(overlay.isVisible)
        let expectedBtnCenterX = closeBtnRect.midX
        let expectedBtnCenterY = closeBtnRect.midY
        XCTAssertEqual(overlay.currentAXRect.midX, expectedBtnCenterX, accuracy: 0.5)
        XCTAssertEqual(overlay.currentAXRect.midY, expectedBtnCenterY, accuracy: 0.5)
    }

    func testUpdateOverlayQueriesAndAlignsWithNativeCloseButtonFrame() {
        let overlay = PreviewCloseButtonOverlay()
        let service = MissionControlHoverService(
            accessibilityService: mockService,
            isMissionControlActiveProvider: { [weak self] in self?.isMissionControlActive ?? false },
            overlay: overlay
        )
        service.start()
        defer { service.stop() }

        isMissionControlActive = true
        let previewRect = CGRect(x: 100, y: 100, width: 300, height: 200)
        let dummyTile = AXUIElementCreateSystemWide()
        mockService.mockElement = dummyTile
        mockService.mockPreviewTile = (tileElement: dummyTile, windowID: CGWindowID(888))
        mockService.mockFrame = previewRect

        let nativeCloseRect = CGRect(x: 108, y: 108, width: 16, height: 16)
        mockService.mockCloseButtonFrame = nativeCloseRect

        let winInfo: [String: Any] = [
            kCGWindowNumber as String: CGWindowID(888),
            "kCGWindowBounds": [
                "X": previewRect.origin.x,
                "Y": previewRect.origin.y,
                "Width": previewRect.width,
                "Height": previewRect.height
            ]
        ]
        service._testSeedWindows([winInfo])

        service.updateOverlay(at: CGPoint(x: 150, y: 150))
        XCTAssertTrue(overlay.isVisible)
        XCTAssertEqual(overlay.currentAXRect.midX, nativeCloseRect.midX, accuracy: 0.5)
        XCTAssertEqual(overlay.currentAXRect.midY, nativeCloseRect.midY, accuracy: 0.5)
    }

    func testMissionControlWindowActionsPerformCloseResolvesWindowID() {
        let winInfo: [String: Any] = [
            kCGWindowOwnerPID as String: pid_t(1234),
            kCGWindowNumber as String: CGWindowID(999)
        ]
        mockService.focusWindowReturnValue = true
        // Set mockWindow to verify focusWindow is called with the resolved window
        let dummyElement = AXUIElementCreateSystemWide()
        mockService.mockWindowForWindowID[999] = dummyElement

        MissionControlWindowActions.performClose(on: winInfo, accessibilityService: mockService)
        XCTAssertEqual(mockService.focusWindowCalledWith, dummyElement)
    }

    func testMissionControlWindowActionsPerformMinimizeResolvesWindowID() {
        let winInfo: [String: Any] = [
            kCGWindowOwnerPID as String: pid_t(1234),
            kCGWindowNumber as String: CGWindowID(888)
        ]
        let dummyElement = AXUIElementCreateSystemWide()
        mockService.mockWindowForWindowID[888] = dummyElement
        mockService.setMinimizedReturnValue = true

        MissionControlWindowActions.performMinimize(on: winInfo, accessibilityService: mockService)
        XCTAssertEqual(mockService.setMinimizedCalledWith?.element, dummyElement)
        XCTAssertEqual(mockService.setMinimizedCalledWith?.minimized, true)
    }

    func testIsSafeTargetProcessProtectsCriticalSystemApps() {
        XCTAssertFalse(NSRunningApplication.current.isSafeTargetProcess)
        if let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first {
            XCTAssertFalse(dock.isSafeTargetProcess)
        }
        if let wm = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.WindowManager").first {
            XCTAssertFalse(wm.isSafeTargetProcess)
        }
    }

    // MARK: - Multi-Desktop Mission Control Isolation Tests

    func testMultiDesktopMissionControlOverlaySuppressedForWindowOnOtherSpace() {
        let mockSpaceService = MockSpaceManagementService()
        // Space 1 has windows 101, 102. Space 2 has window 201.
        mockSpaceService.mockCurrentSpaceID = 2
        mockSpaceService.mockWindowSpaces = [
            101: [1],
            102: [1],
            201: [2]
        ]

        let overlay = PreviewCloseButtonOverlay()
        let service = MissionControlHoverService(
            accessibilityService: mockService,
            isMissionControlActiveProvider: { [weak self] in self?.isMissionControlActive ?? false },
            spaceService: mockSpaceService,
            overlay: overlay
        )
        service.start()
        defer { service.stop() }

        isMissionControlActive = true

        let win201: [String: Any] = [
            kCGWindowNumber as String: CGWindowID(201),
            kCGWindowOwnerName as String: "Xcode",
            kCGWindowLayer as String: 0,
            "kCGWindowBounds": [
                "X": CGFloat(500), "Y": CGFloat(500), "Width": CGFloat(400), "Height": CGFloat(300)
            ]
        ]
        // On Space 2, only window 201 is in the space
        service._testSeedWindows([win201])

        let dummyTile101 = AXUIElementCreateSystemWide()
        let previewRect101 = CGRect(x: 100, y: 100, width: 300, height: 200)

        // Cursor is at (150, 150) where Desktop 1's window 101 would be in WindowManager's flat overlay
        mockService.mockElement = dummyTile101
        mockService.mockPreviewTile = (tileElement: dummyTile101, windowID: CGWindowID(101))
        mockService.mockFrame = previewRect101

        service.updateOverlay(at: CGPoint(x: 150, y: 150))

        // Overlay MUST NOT be shown for window 101 from Desktop 1
        XCTAssertFalse(overlay.isVisible)

        // Now simulate cursor over Desktop 2's own window 201
        let dummyTile201 = AXUIElementCreateSystemWide()
        let previewRect201 = CGRect(x: 500, y: 500, width: 400, height: 300)
        mockService.mockElement = dummyTile201
        mockService.mockPreviewTile = (tileElement: dummyTile201, windowID: CGWindowID(201))
        mockService.mockFrame = previewRect201

        service.updateOverlay(at: CGPoint(x: 550, y: 550))

        // Overlay MUST be shown for window 201 on Desktop 2
        XCTAssertTrue(overlay.isVisible)
        XCTAssertEqual(overlay.currentAXRect.midX, previewRect201.minX, accuracy: 0.5)
        XCTAssertEqual(overlay.currentAXRect.midY, previewRect201.minY, accuracy: 0.5)
    }

    func testSpaceChangeResetsHysteresisAndStaleOverlay() {
        let mockSpaceService = MockSpaceManagementService()
        mockSpaceService.mockCurrentSpaceID = 1
        mockSpaceService.mockWindowSpaces = [
            101: [1],
            201: [2]
        ]

        let overlay = PreviewCloseButtonOverlay()
        let service = MissionControlHoverService(
            accessibilityService: mockService,
            isMissionControlActiveProvider: { [weak self] in self?.isMissionControlActive ?? false },
            spaceService: mockSpaceService,
            overlay: overlay
        )
        service.start()
        defer { service.stop() }

        isMissionControlActive = true

        let win101: [String: Any] = [
            kCGWindowNumber as String: CGWindowID(101),
            kCGWindowOwnerName as String: "App1",
            kCGWindowLayer as String: 0,
            "kCGWindowBounds": [
                "X": CGFloat(100), "Y": CGFloat(100), "Width": CGFloat(300), "Height": CGFloat(200)
            ]
        ]
        service._testSeedWindows([win101])

        let dummyTile101 = AXUIElementCreateSystemWide()
        let previewRect101 = CGRect(x: 100, y: 100, width: 300, height: 200)
        mockService.mockElement = dummyTile101
        mockService.mockPreviewTile = (tileElement: dummyTile101, windowID: CGWindowID(101))
        mockService.mockFrame = previewRect101

        service.updateOverlay(at: CGPoint(x: 150, y: 150))
        XCTAssertTrue(overlay.isVisible)
        XCTAssertEqual(service.currentPreviewFrame, previewRect101)

        // Switch to Space 2
        mockSpaceService.mockCurrentSpaceID = 2
        let win201: [String: Any] = [
            kCGWindowNumber as String: CGWindowID(201),
            kCGWindowOwnerName as String: "App2",
            kCGWindowLayer as String: 0,
            "kCGWindowBounds": [
                "X": CGFloat(600), "Y": CGFloat(200), "Width": CGFloat(400), "Height": CGFloat(300)
            ]
        ]
        service._testSeedWindows([win201])

        // Space change occurs while cursor was at (150, 150)
        service.handleSpaceChange(at: CGPoint(x: 150, y: 150))

        // On Space 2, cursor at (150, 150) should NOT keep the stale Space 1 window overlay visible
        XCTAssertFalse(overlay.isVisible)
        XCTAssertNil(service.currentPreviewFrame)
    }

    func testAccessibilityServiceMatchingWindowIDsFiltersCrossSpaceTiles() {
        let dummyTile = AXUIElementCreateSystemWide()
        mockService.mockElement = dummyTile
        mockService.mockPreviewTile = (tileElement: dummyTile, windowID: CGWindowID(101))

        // When allowed IDs do not include 101, it must return nil
        let resultDisallowed = mockService.getMissionControlPreviewTile(at: CGPoint(x: 100, y: 100), matchingWindowIDs: [201, 202])
        XCTAssertNil(resultDisallowed)

        // When allowed IDs include 101, it returns the tile
        let resultAllowed = mockService.getMissionControlPreviewTile(at: CGPoint(x: 100, y: 100), matchingWindowIDs: [101, 201])
        XCTAssertNotNil(resultAllowed)
        XCTAssertEqual(resultAllowed?.windowID, 101)
    }

    func testEmptyMatchingWindowIDsReturnsNil() {
        let dummyTile = AXUIElementCreateSystemWide()
        mockService.mockElement = dummyTile
        mockService.mockPreviewTile = (tileElement: dummyTile, windowID: CGWindowID(101))

        // When matchingWindowIDs is empty set, it must return nil immediately
        let result = mockService.getMissionControlPreviewTile(at: CGPoint(x: 100, y: 100), matchingWindowIDs: [])
        XCTAssertNil(result)
    }

    func testEmptySpaceNeverShowsPreviewOverlay() {
        let mockSpaceService = MockSpaceManagementService()
        mockSpaceService.mockCurrentSpaceID = 2
        mockSpaceService.mockWindowSpaces = [:]

        let overlay = PreviewCloseButtonOverlay()
        let service = MissionControlHoverService(
            accessibilityService: mockService,
            isMissionControlActiveProvider: { [weak self] in self?.isMissionControlActive ?? false },
            spaceService: mockSpaceService,
            overlay: overlay
        )
        service.start()
        defer { service.stop() }

        isMissionControlActive = true
        service.windows = []

        let dummyTile101 = AXUIElementCreateSystemWide()
        let previewRect101 = CGRect(x: 100, y: 100, width: 300, height: 200)
        mockService.mockElement = dummyTile101
        mockService.mockPreviewTile = (tileElement: dummyTile101, windowID: CGWindowID(101))
        mockService.mockFrame = previewRect101

        // Attempting to update overlay or query preview on empty space
        service.updateOverlay(at: CGPoint(x: 150, y: 150))

        XCTAssertFalse(overlay.isVisible)
        XCTAssertNil(service.currentPreviewFrame)
        XCTAssertNil(service.currentHoveredWindow)
        XCTAssertNil(service.previewWindow(at: CGPoint(x: 150, y: 150)))
    }

    // MARK: - Drag Suppression

    func testDraggingPreviewHidesCloseOverlay() {
        let overlay = PreviewCloseButtonOverlay()
        let service = MissionControlHoverService(
            accessibilityService: mockService,
            isMissionControlActiveProvider: { [weak self] in
                self?.isMissionControlActive ?? false
            },
            overlay: overlay
        )
        service.start()
        defer { service.stop() }

        isMissionControlActive = true
        service._testSeedWindows([makeWindowInfo(at: CGRect(x: 100, y: 100, width: 400, height: 300))])

        // 1. Move over the preview window -> overlay shows
        service.handleMouseMoved(at: CGPoint(x: 200, y: 200))
        XCTAssertTrue(overlay.isVisible)
        XCTAssertFalse(service.isDragging)

        // 2. Begin dragging the preview -> overlay hides immediately, isDragging is true
        service.handleMouseDragged(at: CGPoint(x: 210, y: 210))
        XCTAssertFalse(overlay.isVisible)
        XCTAssertTrue(service.isDragging)

        // 3. Continuing to drag keeps the overlay hidden even if dragging over the preview
        service.handleMouseDragged(at: CGPoint(x: 250, y: 250))
        XCTAssertFalse(overlay.isVisible)
        XCTAssertTrue(service.isDragging)

        // 4. Mouse moved events during drag must also be ignored/suppressed
        service.handleMouseMoved(at: CGPoint(x: 260, y: 260))
        XCTAssertFalse(overlay.isVisible)

        // 5. Release mouse (drop) -> isDragging resets, overlay remains hidden until next mouse move
        service.handleMouseUp(at: CGPoint(x: 260, y: 260))
        XCTAssertFalse(service.isDragging)
        XCTAssertFalse(overlay.isVisible)

        // 6. After drag is complete, moving mouse over the window re-enables the overlay
        service.handleMouseMoved(at: CGPoint(x: 200, y: 200))
        XCTAssertTrue(overlay.isVisible)
    }

    func testMouseDownOutsideOverlayHidesCloseButtonAndPreparesDrag() {
        let overlay = PreviewCloseButtonOverlay()
        let service = MissionControlHoverService(
            accessibilityService: mockService,
            isMissionControlActiveProvider: { [weak self] in
                self?.isMissionControlActive ?? false
            },
            overlay: overlay
        )
        service.start()
        defer { service.stop() }

        isMissionControlActive = true
        service._testSeedWindows([makeWindowInfo(at: CGRect(x: 100, y: 100, width: 400, height: 300))])

        // Hover over window -> overlay is shown
        service.handleMouseMoved(at: CGPoint(x: 200, y: 200))
        XCTAssertTrue(overlay.isVisible)

        // Mouse down on window preview (outside close button) -> overlay is hidden, returns false to allow drag
        let handled = service.handleMouseDown(at: CGPoint(x: 200, y: 200))
        XCTAssertFalse(handled)
        XCTAssertFalse(overlay.isVisible)
        XCTAssertTrue(service.isMouseDown)

        // While mouse is held down, moving mouse does not flash the overlay
        service.handleMouseMoved(at: CGPoint(x: 205, y: 205))
        XCTAssertFalse(overlay.isVisible)

        // Dragging ensues
        service.handleMouseDragged(at: CGPoint(x: 220, y: 220))
        XCTAssertTrue(service.isDragging)
        XCTAssertFalse(overlay.isVisible)

        // Mouse up ends drag
        service.handleMouseUp(at: CGPoint(x: 220, y: 220))
        XCTAssertFalse(service.isMouseDown)
        XCTAssertFalse(service.isDragging)
    }

    func testDeactivationOrSpaceChangeWhileDraggingClearsDragState() {
        let overlay = PreviewCloseButtonOverlay()
        let service = MissionControlHoverService(
            accessibilityService: mockService,
            isMissionControlActiveProvider: { [weak self] in
                self?.isMissionControlActive ?? false
            },
            overlay: overlay
        )
        service.start()
        defer { service.stop() }

        isMissionControlActive = true
        service._testSeedWindows([makeWindowInfo(at: CGRect(x: 100, y: 100, width: 400, height: 300))])

        service.handleMouseDragged(at: CGPoint(x: 150, y: 150))
        XCTAssertTrue(service.isDragging)

        service.handleDeactivated()
        XCTAssertFalse(service.isDragging)
        XCTAssertFalse(service.isMouseDown)

        service.handleMouseDragged(at: CGPoint(x: 150, y: 150))
        XCTAssertTrue(service.isDragging)

        service.handleSpaceChange()
        XCTAssertFalse(service.isDragging)
        XCTAssertFalse(service.isMouseDown)
    }
}
