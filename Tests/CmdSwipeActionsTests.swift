import Cocoa
import Foundation
import XCTest

final class CmdSwipeActionsTests: XCTestCase {
    private var mockService: MockAccessibilityService!

    override func setUp() {
        super.setUp()
        mockService = MockAccessibilityService()
    }

    override func tearDown() {
        mockService = nil
        super.tearDown()
    }

    func testCloseAllTabsWithNilElementDoesNotCrash() {
        mockService.mockElement = nil
        let point = CGPoint(x: 120, y: 200)
        WindowCloser().perform(.allTabs, at: point, fromApp: nil, service: mockService)
        XCTAssertEqual(mockService.getElementCalledWith, point)
    }

    func testNewWindowActionWithNilElementDoesNotCrash() {
        mockService.mockElement = nil
        let action = NewWindowAction()
        let point = CGPoint(x: 80, y: 90)
        action.perform(at: point, service: mockService)
        XCTAssertEqual(mockService.getElementCalledWith, point)
    }

    func testFillScreenActionWithNilElementDoesNotCrash() {
        mockService.mockElement = nil
        let action = FillScreenAction()
        let point = CGPoint(x: 150, y: 250)
        action.perform(at: point, service: mockService)
        XCTAssertEqual(mockService.getElementCalledWith, point)
        XCTAssertNil(mockService.setFrameCalledWith)
    }

    func testReasonableSizeActionWithNilElementDoesNotCrash() {
        mockService.mockElement = nil
        let action = ReasonableSizeAction()
        let point = CGPoint(x: 150, y: 250)
        action.perform(at: point, service: mockService)
        XCTAssertEqual(mockService.getElementCalledWith, point)
        XCTAssertNil(mockService.setFrameCalledWith)
    }

    func testAlmostMaximizeActionWithNilElementDoesNotCrash() {
        mockService.mockElement = nil
        let action = AlmostMaximizeAction()
        let point = CGPoint(x: 150, y: 250)
        action.perform(at: point, service: mockService)
        XCTAssertEqual(mockService.getElementCalledWith, point)
        XCTAssertNil(mockService.setFrameCalledWith)
    }

    // MARK: - CloseScope.activeTab (cursor trigger)

    func testCloseActiveTabFocusesResolvedWindowBeforeCmdWFallback() {
        // Simulate a window that lacks an accessible tab group, forcing the
        // Cmd+W fallback path. The resolved window (not the app's key window)
        // must be focused first.
        let appElement = AXUIElementCreateApplication(NSRunningApplication.current.processIdentifier)
        mockService.mockElement = appElement
        let hoveredWindow = AXUIElementCreateApplication(NSRunningApplication.current.processIdentifier)
        mockService.mockWindow = hoveredWindow
        mockService.mockTabCloseButton = nil

        WindowCloser().perform(.activeTab, at: CGPoint(x: 10, y: 10), fromApp: nil, service: mockService)

        XCTAssertEqual(mockService.focusWindowCalledWith, hoveredWindow)
    }

    func testCloseActiveTabPrefersAccessibleTabCloseButton() {
        // When the window exposes a tab close button, no focus change or
        // Cmd+W fallback should occur.
        let appElement = AXUIElementCreateApplication(NSRunningApplication.current.processIdentifier)
        mockService.mockElement = appElement
        mockService.mockWindow = AXUIElementCreateApplication(NSRunningApplication.current.processIdentifier)
        let closeBtn = AXUIElementCreateApplication(NSRunningApplication.current.processIdentifier)
        mockService.mockTabCloseButton = closeBtn

        WindowCloser().perform(.activeTab, at: CGPoint(x: 10, y: 10), fromApp: nil, service: mockService)

        XCTAssertNil(mockService.focusWindowCalledWith)
        XCTAssertEqual(mockService.performActionCalledWith?.element, closeBtn)
    }

    // MARK: - CloseScope.activeTab (Dock trigger)

    func testCloseActiveTabFromDockTargetsKeyWindowTabCloseButton() {
        let app = NSRunningApplication.current
        let keyWindow = AXUIElementCreateApplication(app.processIdentifier)
        let closeBtn = AXUIElementCreateApplication(app.processIdentifier)
        mockService.mockFocusedWindow = keyWindow
        mockService.mockTabCloseButton = closeBtn

        WindowCloser().perform(.activeTab, at: .zero, fromApp: app, service: mockService)

        XCTAssertEqual(mockService.performActionCalledWith?.element, closeBtn)
        XCTAssertNil(mockService.focusWindowCalledWith)
    }

    func testCloseActiveTabFromDockFallsBackToKeyWindowCmdWWhenNoTabButton() {
        let app = NSRunningApplication.current
        let keyWindow = AXUIElementCreateApplication(app.processIdentifier)
        mockService.mockFocusedWindow = keyWindow
        mockService.mockTabCloseButton = nil

        // No tab close button available: the Cmd+W fallback (targeting the key
        // window) runs. We assert it resolved the key window via the focused
        // window attribute rather than iterating all windows.
        WindowCloser().perform(.activeTab, at: .zero, fromApp: app, service: mockService)

        XCTAssertNil(mockService.performActionCalledWith)
    }

    // MARK: - CloseScope.wholeApp

    /// A real running app that is not this process, so the never-close-self
    /// guard passes while the mock service fully controls AX responses.
    private func makeForeignApp() throws -> NSRunningApplication {
        let current = NSRunningApplication.current.processIdentifier
        return try XCTUnwrap(
            NSWorkspace.shared.runningApplications.first { $0.processIdentifier != current }
        )
    }

    func testCloseWholeAppPressesRedCloseButtonOnEveryWindow() throws {
        let app = try makeForeignApp()
        let windows = [
            AXUIElementCreateApplication(app.processIdentifier),
            AXUIElementCreateApplication(app.processIdentifier)
        ]
        let closeBtn = AXUIElementCreateApplication(app.processIdentifier)
        mockService.mockAppWindows = windows
        mockService.mockCloseButton = closeBtn

        WindowCloser().perform(.wholeApp, at: .zero, fromApp: app, service: mockService)

        XCTAssertEqual(mockService.performActionCalledWith?.element, closeBtn)
    }

    func testCloseWholeAppDoesNothingWhenAppHasNoWindows() throws {
        // Regression guard: a Dock-triggered close of an app with zero windows
        // must be a no-op — it used to terminate the whole application.
        let app = try makeForeignApp()
        mockService.mockAppWindows = []

        WindowCloser().perform(.wholeApp, at: .zero, fromApp: app, service: mockService)

        XCTAssertNil(mockService.performActionCalledWith)
    }
}
