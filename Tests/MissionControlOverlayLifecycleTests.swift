import Cocoa
import Foundation
import XCTest

final class MockPreviewCloseButtonOverlay: PreviewCloseButtonOverlayProtocol {
    var isVisible = false
    var currentAXRect: CGRect = .zero
    var currentMode: PreviewCloseButtonOverlay.Mode = .close
    var showCallCount = 0
    var hideCallCount = 0

    func show(for windowFrame: CGRect, closeButtonFrame: CGRect?, mode: PreviewCloseButtonOverlay.Mode) {
        isVisible = true
        currentAXRect = windowFrame
        currentMode = mode
        showCallCount += 1
    }

    func show(for windowFrame: CGRect, mode: PreviewCloseButtonOverlay.Mode) {
        isVisible = true
        currentAXRect = windowFrame
        currentMode = mode
        showCallCount += 1
    }

    func show(at windowBounds: CGRect, mode: PreviewCloseButtonOverlay.Mode) {
        isVisible = true
        currentAXRect = windowBounds
        currentMode = mode
        showCallCount += 1
    }

    func setMode(_ mode: PreviewCloseButtonOverlay.Mode) {
        currentMode = mode
    }

    func setHovered(_ isHovered: Bool) {}

    func hide() {
        isVisible = false
        currentAXRect = .zero
        hideCallCount += 1
    }
}

final class MockSearchBarOverlay: SearchBarOverlayProtocol {
    var isVisible = false
    var currentQuery = ""
    var showCallCount = 0
    var hideCallCount = 0

    func show(query: String) {
        isVisible = true
        currentQuery = query
        showCallCount += 1
    }

    func hide() {
        isVisible = false
        currentQuery = ""
        hideCallCount += 1
    }
}

@MainActor
final class MissionControlOverlayLifecycleTests: XCTestCase {
    private var mockService: MockAccessibilityService!
    private var mockCloseOverlay: MockPreviewCloseButtonOverlay!
    private var mockSearchOverlay: MockSearchBarOverlay!
    private var isMissionControlActive = false
    private var hoverService: MissionControlHoverService!

    override func setUp() {
        super.setUp()
        mockService = MockAccessibilityService()
        mockCloseOverlay = MockPreviewCloseButtonOverlay()
        mockSearchOverlay = MockSearchBarOverlay()
        isMissionControlActive = true
        hoverService = MissionControlHoverService(
            accessibilityService: mockService,
            isMissionControlActiveProvider: { [weak self] in
                self?.isMissionControlActive ?? false
            },
            overlay: mockCloseOverlay,
            searchOverlay: mockSearchOverlay
        )
    }

    override func tearDown() {
        hoverService.stop()
        hoverService = nil
        mockSearchOverlay = nil
        mockCloseOverlay = nil
        mockService = nil
        super.tearDown()
    }

    private func seedTestWindow() {
        hoverService._testSeedWindows([[
            kCGWindowNumber as String: CGWindowID(42),
            kCGWindowOwnerName as String: "Terminal",
            kCGWindowBounds as String: [
                "X": CGFloat(100),
                "Y": CGFloat(100),
                "Width": CGFloat(800),
                "Height": CGFloat(600)
            ]
        ]])
    }

    // MARK: - Lifecycle Sync Between Close Button and Search Overlay

    func testHoverCloseButtonAppearsAndHidesWithSearchSession() {
        hoverService.start()
        seedTestWindow()

        _ = hoverService.handleKeyDown(keyCode: 1, characters: "t", flags: [])
        XCTAssertTrue(mockCloseOverlay.isVisible)
        XCTAssertTrue(mockSearchOverlay.isVisible)

        hoverService.clearSearch()
        XCTAssertFalse(mockCloseOverlay.isVisible)
        XCTAssertFalse(mockSearchOverlay.isVisible)
    }

    // MARK: - Escape Key Teardown

    func testEscapeKeyWithEmptyQueryDismissesCloseAndSearchOverlays() {
        hoverService.start()
        seedTestWindow()
        mockCloseOverlay.show(at: CGRect(x: 100, y: 100, width: 200, height: 200), mode: .close)
        XCTAssertTrue(mockCloseOverlay.isVisible)
        XCTAssertFalse(mockSearchOverlay.isVisible)

        let handled = hoverService.handleKeyDown(keyCode: 53, characters: nil, flags: [])
        XCTAssertFalse(handled, "Escape on empty query must pass through to exit MC")
        XCTAssertFalse(mockCloseOverlay.isVisible)
        XCTAssertFalse(mockSearchOverlay.isVisible)
        XCTAssertFalse(hoverService.isMissionControlActive)
    }

    // MARK: - Mouse Move Outside Active MC Instantly Dismisses Both

    func testMouseMoveWhenMissionControlIsNoLongerActiveDismissesAllOverlays() {
        hoverService.start()
        seedTestWindow()
        _ = hoverService.handleKeyDown(keyCode: 1, characters: "t", flags: [])
        XCTAssertTrue(mockCloseOverlay.isVisible)
        XCTAssertTrue(mockSearchOverlay.isVisible)

        isMissionControlActive = false

        hoverService.handleMouseMoved(at: CGPoint(x: 50, y: 50))

        XCTAssertFalse(mockCloseOverlay.isVisible)
        XCTAssertFalse(mockSearchOverlay.isVisible)
        XCTAssertTrue(hoverService.searchSession.query.isEmpty)
        XCTAssertFalse(hoverService.isMissionControlActive)
    }

    // MARK: - Mouse Click Outside Previews Hides All Overlays

    func testMouseDownOutsideWindowPreviewsHidesAllOverlays() {
        hoverService.start()
        seedTestWindow()
        _ = hoverService.handleKeyDown(keyCode: 1, characters: "t", flags: [])
        XCTAssertTrue(mockCloseOverlay.isVisible)
        XCTAssertTrue(mockSearchOverlay.isVisible)

        let handled = hoverService.handleMouseDown(at: CGPoint(x: 950, y: 950))
        XCTAssertFalse(handled, "Click on backdrop must pass through to dismiss MC")
        XCTAssertFalse(mockCloseOverlay.isVisible)
        XCTAssertFalse(mockSearchOverlay.isVisible)
        XCTAssertTrue(hoverService.searchSession.query.isEmpty)
    }

    // MARK: - Direct handleDeactivated() Unconditionally Hides All Overlays

    func testHandleDeactivatedUnconditionallyHidesAllOverlays() {
        hoverService.start()
        mockCloseOverlay.show(at: CGRect(x: 0, y: 0, width: 100, height: 100), mode: .close)
        mockSearchOverlay.show(query: "HELLO")
        XCTAssertTrue(mockCloseOverlay.isVisible)
        XCTAssertTrue(mockSearchOverlay.isVisible)

        hoverService.handleDeactivated()

        XCTAssertFalse(mockCloseOverlay.isVisible)
        XCTAssertFalse(mockSearchOverlay.isVisible)
        XCTAssertTrue(hoverService.searchSession.query.isEmpty)
        XCTAssertFalse(hoverService.isMissionControlActive)
    }

    // MARK: - hideAllOverlays API

    func testHideAllOverlaysHidesCloseAndSearchOverlaysAndClearsSession() {
        hoverService.start()
        seedTestWindow()
        _ = hoverService.handleKeyDown(keyCode: 1, characters: "t", flags: [])
        XCTAssertTrue(mockCloseOverlay.isVisible)
        XCTAssertTrue(mockSearchOverlay.isVisible)

        hoverService.hideAllOverlays()

        XCTAssertFalse(mockCloseOverlay.isVisible)
        XCTAssertFalse(mockSearchOverlay.isVisible)
        XCTAssertTrue(hoverService.searchSession.query.isEmpty)
    }

    // MARK: - Continuous Typing Outside Mission Control (Regression: "ccccccc")

    func testContinuousTypingOutsideMissionControlDoesNotShowSearchOverlayOrSwallowKeys() {
        hoverService.start()
        seedTestWindow()

        // Mission Control opens
        isMissionControlActive = true
        hoverService.handleActivated()
        XCTAssertTrue(hoverService.isMissionControlActive)

        // Mission Control quickly closes
        isMissionControlActive = false
        // Even if handleDeactivated was delayed, the first keystroke must detect MC is inactive
        for _ in 0..<7 {
            let handled = hoverService.handleKeyDown(keyCode: 8, characters: "c", flags: [])
            XCTAssertFalse(handled, "Typing outside Mission Control must NEVER swallow keystrokes")
            XCTAssertFalse(mockSearchOverlay.isVisible, "Search bar overlay must NEVER appear outside Mission Control")
            XCTAssertTrue(hoverService.searchSession.query.isEmpty, "Query must stay empty when typing outside MC")
        }
        XCTAssertFalse(hoverService.isMissionControlActive)
    }

    func testTypingWithMockMissionControlServiceActiveStateTransitions() {
        let mockMC = MockMissionControlService()
        let customHoverService = MissionControlHoverService(
            accessibilityService: mockService,
            isMissionControlActiveProvider: { mockMC.checkMissionControlActive() },
            missionControlService: mockMC,
            overlay: mockCloseOverlay,
            searchOverlay: mockSearchOverlay
        )
        customHoverService.start()
        customHoverService._testSeedWindows([[
            kCGWindowNumber as String: CGWindowID(101),
            kCGWindowOwnerName as String: "Safari",
            kCGWindowBounds as String: [
                "X": CGFloat(100),
                "Y": CGFloat(100),
                "Width": CGFloat(800),
                "Height": CGFloat(600)
            ]
        ]])

        // 1. Mission Control is active: typing 's' matches Safari and shows overlay
        mockMC.isMissionControlActive = true
        customHoverService.handleActivated()
        let handledInMC = customHoverService.handleKeyDown(keyCode: 1, characters: "s", flags: [])
        XCTAssertTrue(handledInMC, "Keystroke in Mission Control should be handled")
        XCTAssertTrue(mockSearchOverlay.isVisible)
        XCTAssertEqual(customHoverService.searchSession.query, "s")

        // 2. Mission Control exits (e.g. quick exit)
        mockMC.isMissionControlActive = false

        // Continuous typing outside MC (e.g. "ccccccc")
        for _ in 0..<7 {
            let handledOutside = customHoverService.handleKeyDown(keyCode: 8, characters: "c", flags: [])
            XCTAssertFalse(handledOutside, "Keystroke outside Mission Control must pass through")
            XCTAssertFalse(mockSearchOverlay.isVisible, "Overlay must remain hidden outside Mission Control")
        }
        XCTAssertFalse(customHoverService.isMissionControlActive)
        customHoverService.stop()
    }

    // MARK: - Immediate Typing Without Mouse Movement

    func testTypingImmediatelyOnMissionControlOpenWithoutMouseMovement() {
        let mockMC = MockMissionControlService()
        let customHoverService = MissionControlHoverService(
            accessibilityService: mockService,
            isMissionControlActiveProvider: { mockMC.checkMissionControlActive() },
            missionControlService: mockMC,
            overlay: mockCloseOverlay,
            searchOverlay: mockSearchOverlay
        )
        customHoverService.start()
        defer { customHoverService.stop() }

        // Mission Control opens, but mouse does NOT move at all
        mockMC.isMissionControlActive = true
        customHoverService.handleActivated()

        // Windows list is seeded (simulating fetchWindows)
        customHoverService._testSeedWindows([
            [
                kCGWindowNumber as String: CGWindowID(202),
                kCGWindowOwnerName as String: "Terminal",
                kCGWindowLayer as String: 0,
                kCGWindowBounds as String: [
                    "X": CGFloat(100),
                    "Y": CGFloat(100),
                    "Width": CGFloat(500),
                    "Height": CGFloat(400)
                ]
            ]
        ])

        // User starts typing 't' immediately without hovering on any preview window
        XCTAssertFalse(mockSearchOverlay.isVisible)
        let handled = customHoverService.handleKeyDown(keyCode: 17, characters: "t", flags: [])

        XCTAssertTrue(handled, "Typing immediately on Mission Control open must be consumed")
        XCTAssertTrue(mockSearchOverlay.isVisible, "Search bar overlay must immediately appear")
        XCTAssertEqual(customHoverService.searchSession.query, "t")
        XCTAssertTrue(mockCloseOverlay.isVisible, "Close button overlay must update to match the selected preview window")
    }

    // MARK: - Cursor Positioning at Preview Middle (Not Top-Left Corner)

    func testCursorTargetsPreviewCenterOnFuzzyTypeAndTab() {
        hoverService.start()
        hoverService._testSeedWindows([
            [
                kCGWindowNumber as String: CGWindowID(1),
                kCGWindowOwnerName as String: "Terminal",
                kCGWindowLayer as String: 0,
                kCGWindowBounds as String: [
                    "X": CGFloat(100),
                    "Y": CGFloat(100),
                    "Width": CGFloat(400),
                    "Height": CGFloat(300)
                ]
            ],
            [
                kCGWindowNumber as String: CGWindowID(2),
                kCGWindowOwnerName as String: "Safari",
                kCGWindowLayer as String: 0,
                kCGWindowBounds as String: [
                    "X": CGFloat(600),
                    "Y": CGFloat(100),
                    "Width": CGFloat(400),
                    "Height": CGFloat(300)
                ]
            ]
        ])

        // 1. Fuzzy typing 't' should match Terminal only
        _ = hoverService.handleKeyDown(keyCode: 17, characters: "t", flags: [])
        XCTAssertEqual(hoverService.currentMatches.count, 1)
        let termMatch = hoverService.currentMatches[0]
        let termCenter = hoverService.previewCenter(for: termMatch)
        // Middle: 100 + 400/2 = 300, 100 + 300/2 = 250
        XCTAssertEqual(termCenter, CGPoint(x: 300, y: 250))
        // Verify it is NOT the left top corner (120, 120)
        XCTAssertNotEqual(termCenter, CGPoint(x: 120, y: 120))

        hoverService.clearSearch()

        // 2. Tab cycling through windows with empty query (row-major order)
        // Tab key: keyCode 48
        _ = hoverService.handleKeyDown(keyCode: 48, characters: "\t", flags: [])
        XCTAssertEqual(hoverService.currentMatches.count, 2)
        let firstTabMatch = hoverService.currentMatches[hoverService.searchSession.selectedIndex]
        let firstCenter = hoverService.previewCenter(for: firstTabMatch)
        XCTAssertEqual(firstCenter, CGPoint(x: 300, y: 250))
        XCTAssertNotEqual(firstCenter, CGPoint(x: 120, y: 120))

        // Next Tab moves to second window (Safari)
        _ = hoverService.handleKeyDown(keyCode: 48, characters: "\t", flags: [])
        let secondTabMatch = hoverService.currentMatches[hoverService.searchSession.selectedIndex]
        let secondCenter = hoverService.previewCenter(for: secondTabMatch)
        // Middle: 600 + 400/2 = 800, 100 + 300/2 = 250
        XCTAssertEqual(secondCenter, CGPoint(x: 800, y: 250))
        XCTAssertNotEqual(secondCenter, CGPoint(x: 620, y: 120))
    }
}
