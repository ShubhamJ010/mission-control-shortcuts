import Cocoa
import Foundation
import XCTest

final class DockInteractionSuppressorTests: XCTestCase {
    private var suppressor: DockInteractionSuppressor!

    override func setUp() {
        super.setUp()
        suppressor = DockInteractionSuppressor()
    }

    override func tearDown() {
        suppressor.stop()
        suppressor = nil
        super.tearDown()
    }

    func testInitialStateIsDisabled() {
        XCTAssertFalse(suppressor.isSuppressing)
        XCTAssertNil(suppressor.isDockHoveredProvider)
        XCTAssertNil(suppressor.isEnabledProvider)
    }

    func testSuppressionStateCanBeMutated() {
        suppressor.isSuppressing = true
        XCTAssertTrue(suppressor.isSuppressing)
        suppressor.isSuppressing = false
        XCTAssertFalse(suppressor.isSuppressing)
    }

    func testStopResetsSuppressionState() {
        suppressor.isSuppressing = true
        suppressor.stop()
        XCTAssertFalse(suppressor.isSuppressing)
    }

    func testDockHoveredProviderIntegration() throws {
        var queriedPoint: CGPoint?
        suppressor.isDockHoveredProvider = { point in
            queriedPoint = point
            return point.y > 900
        }

        XCTAssertTrue(try XCTUnwrap(suppressor.isDockHoveredProvider?(CGPoint(x: 500, y: 950))))
        XCTAssertEqual(queriedPoint, CGPoint(x: 500, y: 950))

        XCTAssertFalse(try XCTUnwrap(suppressor.isDockHoveredProvider?(CGPoint(x: 500, y: 100))))
        XCTAssertEqual(queriedPoint, CGPoint(x: 500, y: 100))
    }

    func testIsEnabledProviderIntegration() throws {
        var isEnabled = true
        suppressor.isEnabledProvider = { isEnabled }

        XCTAssertTrue(try XCTUnwrap(suppressor.isEnabledProvider?()))

        isEnabled = false
        XCTAssertFalse(try XCTUnwrap(suppressor.isEnabledProvider?()))
    }

    func testMultipleStartsAndStopsAreSafe() {
        // Calling start/stop repeatedly should never crash or throw
        suppressor.start()
        suppressor.start()
        suppressor.stop()
        suppressor.stop()
    }

    // MARK: - Event Filter Tests (Tap vs Physical Press Click)

    private func makeMouseEvent(
        type: CGEventType,
        location: CGPoint,
        button: CGMouseButton = .right,
        pressure: Double = 0.0
    ) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: button
        ))
        event.setDoubleValueField(.mouseEventPressure, value: pressure)
        return event
    }

    func testPhysicalPressClickPassesThroughWhenSuppressingOverDock() throws {
        suppressor.isEnabledProvider = { true }
        suppressor.isDockHoveredProvider = { $0.y > 900 }
        suppressor.isSuppressing = true

        let clickLocation = CGPoint(x: 500, y: 950)
        let event = try makeMouseEvent(type: .rightMouseDown, location: clickLocation, pressure: 1.0)

        let result = suppressor.filterEvent(type: .rightMouseDown, event: event)
        XCTAssertNotNil(result, "Physical press-click (pressure > 0) must NEVER be swallowed over the Dock")
    }

    func testPhysicalPressClickAndReleaseBothPassThroughWhenSuppressingOverDock() throws {
        suppressor.isEnabledProvider = { true }
        suppressor.isDockHoveredProvider = { $0.y > 900 }
        suppressor.isSuppressing = true

        let clickLocation = CGPoint(x: 500, y: 950)
        let downEvent = try makeMouseEvent(type: .rightMouseDown, location: clickLocation, pressure: 1.0)
        let downResult = suppressor.filterEvent(type: .rightMouseDown, event: downEvent)
        XCTAssertNotNil(downResult, "Physical press-click down must pass through")

        // Trackpad release often drops pressure to 0.0 upon mouse-up
        let upEvent = try makeMouseEvent(type: .rightMouseUp, location: clickLocation, pressure: 0.0)
        let upResult = suppressor.filterEvent(type: .rightMouseUp, event: upEvent)
        XCTAssertNotNil(
            upResult,
            "Physical press-click mouse-up must pass through even if pressure drops to 0.0 on release"
        )
    }

    func testSynthesizedTapClickSwallowedWhenSuppressingOverDock() throws {
        suppressor.isEnabledProvider = { true }
        suppressor.isDockHoveredProvider = { $0.y > 900 }
        suppressor.isSuppressing = true

        let clickLocation = CGPoint(x: 500, y: 950)
        let downEvent = try makeMouseEvent(type: .rightMouseDown, location: clickLocation, pressure: 0.0)
        let downResult = suppressor.filterEvent(type: .rightMouseDown, event: downEvent)
        XCTAssertNil(
            downResult,
            "Synthesized tap-click (pressure == 0) down must be swallowed when isSuppressing is true over the Dock"
        )

        let upEvent = try makeMouseEvent(type: .rightMouseUp, location: clickLocation, pressure: 0.0)
        let upResult = suppressor.filterEvent(type: .rightMouseUp, event: upEvent)
        XCTAssertNil(
            upResult,
            "Synthesized tap-click up must be swallowed when isSuppressing is true over the Dock"
        )
    }

    func testSynthesizedTapClickPassesThroughWhenNotSuppressing() throws {
        suppressor.isEnabledProvider = { true }
        suppressor.isDockHoveredProvider = { $0.y > 900 }
        suppressor.isSuppressing = false

        let clickLocation = CGPoint(x: 500, y: 950)
        let event = try makeMouseEvent(type: .rightMouseDown, location: clickLocation, pressure: 0.0)

        let result = suppressor.filterEvent(type: .rightMouseDown, event: event)
        XCTAssertNotNil(result, "Synthesized tap-click must pass through when not suppressing")
    }

    func testSynthesizedTapClickPassesThroughOutsideDock() throws {
        suppressor.isEnabledProvider = { true }
        suppressor.isDockHoveredProvider = { $0.y > 900 }
        suppressor.isSuppressing = true

        let outsideLocation = CGPoint(x: 500, y: 100)
        let event = try makeMouseEvent(type: .rightMouseDown, location: outsideLocation, pressure: 0.0)

        let result = suppressor.filterEvent(type: .rightMouseDown, event: event)
        XCTAssertNotNil(result, "Synthesized tap-click outside the Dock must never be swallowed")
    }

    func testPhysicalPressClickOutsideDockAllowsReleaseOverDock() throws {
        suppressor.isEnabledProvider = { true }
        suppressor.isDockHoveredProvider = { $0.y > 900 }
        suppressor.isSuppressing = true

        let outsideLocation = CGPoint(x: 500, y: 100)
        let insideLocation = CGPoint(x: 500, y: 950)

        let downEvent = try makeMouseEvent(type: .leftMouseDown, location: outsideLocation, button: .left, pressure: 1.0)
        let downResult = suppressor.filterEvent(type: .leftMouseDown, event: downEvent)
        XCTAssertNotNil(downResult, "Drag starting outside Dock passes through")

        let upEvent = try makeMouseEvent(type: .leftMouseUp, location: insideLocation, button: .left, pressure: 0.0)
        let upResult = suppressor.filterEvent(type: .leftMouseUp, event: upEvent)
        XCTAssertNotNil(upResult, "Release of an active physical drag over Dock must pass through")
    }

    func testSmartMagnifySwallowedOverDock() throws {
        suppressor.isEnabledProvider = { true }
        suppressor.isDockHoveredProvider = { $0.y > 900 }

        let gestureType = try XCTUnwrap(CGEventType(rawValue: 32)) // smartMagnify
        let event = try XCTUnwrap(CGEvent(source: nil))
        event.location = CGPoint(x: 500, y: 950)

        let result = suppressor.filterEvent(type: gestureType, event: event)
        XCTAssertNil(result, "smartMagnify (App Exposé trigger) must be swallowed over the Dock")
    }

    func testSmartMagnifyPassesThroughOutsideDock() throws {
        suppressor.isEnabledProvider = { true }
        suppressor.isDockHoveredProvider = { $0.y > 900 }

        let gestureType = try XCTUnwrap(CGEventType(rawValue: 32))
        let event = try XCTUnwrap(CGEvent(source: nil))
        event.location = CGPoint(x: 500, y: 100)

        let result = suppressor.filterEvent(type: gestureType, event: event)
        XCTAssertNotNil(result, "smartMagnify outside the Dock must pass through")
    }

    func testDisabledSuppressorPassesAllEvents() throws {
        suppressor.isEnabledProvider = { false }
        suppressor.isDockHoveredProvider = { _ in true }
        suppressor.isSuppressing = true

        let event = try makeMouseEvent(type: .rightMouseDown, location: CGPoint(x: 500, y: 950), pressure: 0.0)

        let result = suppressor.filterEvent(type: .rightMouseDown, event: event)
        XCTAssertNotNil(result, "Disabled suppressor must pass through all events")
    }
}
