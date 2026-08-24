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
}
