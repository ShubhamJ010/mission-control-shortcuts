import Cocoa
import Foundation
import XCTest

final class WindowSearchSessionTests: XCTestCase {
    private func window(owner: String, number: Int = 1) -> [String: Any] {
        [
            kCGWindowOwnerName as String: owner,
            kCGWindowBounds as String: ["X": 0.0, "Y": 0.0, "Width": 400.0, "Height": 300.0],
            kCGWindowNumber as String: number
        ]
    }

    private var windows: [[String: Any]] {
        [
            window(owner: "Code", number: 1),
            window(owner: "Xcode", number: 2),
            window(owner: "Safari", number: 3)
        ]
    }

    func testStartsWithNoSelection() {
        let session = WindowSearchSession()
        XCTAssertEqual(session.selectedIndex, -1)
        XCTAssertTrue(session.query.isEmpty)
    }

    func testFirstLetterSelectsBestMatch() {
        var session = WindowSearchSession()
        let effect = session.handleKey(keyCode: 8, characters: "c", flags: [], windows: windows)
        XCTAssertEqual(effect, .updated)
        XCTAssertEqual(session.query, "c")
        XCTAssertEqual(session.selectedIndex, 0)
        XCTAssertEqual(session.matches(in: windows).map(\.ownerName), ["Code", "Xcode"])
    }

    func testCommandKeyPassesThrough() {
        var session = WindowSearchSession()
        let effect = session.handleKey(
            keyCode: 13,
            characters: "w",
            flags: .maskCommand,
            windows: windows
        )
        XCTAssertEqual(effect, .ignore)
        XCTAssertTrue(session.query.isEmpty)
        XCTAssertEqual(session.selectedIndex, -1)
    }

    func testOptionAndControlKeysPassThrough() {
        var session = WindowSearchSession()
        XCTAssertEqual(
            session.handleKey(keyCode: 8, characters: "c", flags: .maskAlternate, windows: windows),
            .ignore
        )
        XCTAssertEqual(
            session.handleKey(keyCode: 8, characters: "c", flags: .maskControl, windows: windows),
            .ignore
        )
        XCTAssertTrue(session.query.isEmpty)
    }

    func testShiftDoesNotBlockTyping() {
        var session = WindowSearchSession()
        let effect = session.handleKey(keyCode: 8, characters: "C", flags: .maskShift, windows: windows)
        XCTAssertEqual(effect, .updated)
        XCTAssertEqual(session.query, "C")
        XCTAssertEqual(session.selectedIndex, 0)
    }

    func testEscapeWithEmptyQueryPassesThrough() {
        var session = WindowSearchSession()
        XCTAssertEqual(session.handleKey(keyCode: 53, characters: nil, flags: [], windows: windows), .ignore)
    }

    func testEscapeClearsActiveQuery() {
        var session = WindowSearchSession()
        _ = session.handleKey(keyCode: 8, characters: "c", flags: [], windows: windows)
        XCTAssertEqual(session.handleKey(keyCode: 53, characters: nil, flags: [], windows: windows), .clear)
        XCTAssertTrue(session.query.isEmpty)
        XCTAssertEqual(session.selectedIndex, -1)
    }

    func testBackspaceRemovesLastCharacter() {
        var session = WindowSearchSession()
        _ = session.handleKey(keyCode: 8, characters: "c", flags: [], windows: windows)
        _ = session.handleKey(keyCode: 31, characters: "o", flags: [], windows: windows)
        XCTAssertEqual(session.query, "co")
        XCTAssertEqual(session.handleKey(keyCode: 51, characters: nil, flags: [], windows: windows), .updated)
        XCTAssertEqual(session.query, "c")
        XCTAssertEqual(session.selectedIndex, 0)
    }

    func testBackspaceToEmptyClears() {
        var session = WindowSearchSession()
        _ = session.handleKey(keyCode: 8, characters: "c", flags: [], windows: windows)
        XCTAssertEqual(session.handleKey(keyCode: 51, characters: nil, flags: [], windows: windows), .clear)
        XCTAssertTrue(session.query.isEmpty)
        XCTAssertEqual(session.selectedIndex, -1)
    }

    func testTabCyclesRowMajorWhenQueryEmpty() {
        var session = WindowSearchSession()
        // Tab with empty query now cycles row-major (new feature), not ignored.
        XCTAssertEqual(session.handleKey(keyCode: 48, characters: nil, flags: [], windows: windows), .updated)
        XCTAssertEqual(session.selectedIndex, 0)
        // Wrap-around forward
        XCTAssertEqual(session.handleKey(keyCode: 48, characters: nil, flags: [], windows: windows), .updated)
        XCTAssertEqual(session.selectedIndex, 1)
        // Shift+Tab cycles backward (flags maskShift)
        XCTAssertEqual(session.handleKey(keyCode: 48, characters: nil, flags: .maskShift, windows: windows), .updated)
        XCTAssertEqual(session.selectedIndex, 0)
    }

    func testArrowsIgnoredUntilQueryIsNonEmpty() {
        var session = WindowSearchSession()
        XCTAssertEqual(session.handleKey(keyCode: 125, characters: nil, flags: [], windows: windows), .ignore)
        XCTAssertEqual(session.handleKey(keyCode: 126, characters: nil, flags: [], windows: windows), .ignore)
    }

    func testTabCyclesFilteredMatchesWhenSearching() {
        var session = WindowSearchSession()
        _ = session.handleKey(keyCode: 8, characters: "c", flags: [], windows: windows)
        // Filtered matches are ["Code", "Xcode"]; Tab should cycle only those, not all 3.
        XCTAssertEqual(session.matches(in: windows).count, 2)
        XCTAssertEqual(session.selectedIndex, 0)
        XCTAssertEqual(session.handleKey(keyCode: 48, characters: nil, flags: [], windows: windows), .updated)
        XCTAssertEqual(session.selectedIndex, 1)
        XCTAssertEqual(session.handleKey(keyCode: 48, characters: nil, flags: [], windows: windows), .updated)
        XCTAssertEqual(session.selectedIndex, 0)
        // Pill / session should still be active (query not cleared) until Enter.
        XCTAssertEqual(session.query, "c")
    }

    func testTypingDAfterCleanupIsQueryNotRotate() {
        var session = WindowSearchSession()
        // D/K aliases removed — typing "d" should append to query, not rotate.
        XCTAssertEqual(session.handleKey(keyCode: 2, characters: "d", flags: [], windows: windows), .updated)
        XCTAssertEqual(session.query, "d")
        // "d" matches Code + Xcode in the fixture, proving it was treated as query.
        XCTAssertEqual(session.matches(in: windows).count, 2)
    }

    func testTabCyclesMatches() {
        var session = WindowSearchSession()
        _ = session.handleKey(keyCode: 8, characters: "c", flags: [], windows: windows)
        XCTAssertEqual(session.selectedIndex, 0)
        XCTAssertEqual(session.handleKey(keyCode: 48, characters: nil, flags: [], windows: windows), .updated)
        XCTAssertEqual(session.selectedIndex, 1)
        XCTAssertEqual(session.handleKey(keyCode: 48, characters: nil, flags: [], windows: windows), .updated)
        XCTAssertEqual(session.selectedIndex, 0)
    }

    func testUpArrowCyclesBackwards() {
        var session = WindowSearchSession()
        _ = session.handleKey(keyCode: 8, characters: "c", flags: [], windows: windows)
        XCTAssertEqual(session.handleKey(keyCode: 126, characters: nil, flags: [], windows: windows), .updated)
        XCTAssertEqual(session.selectedIndex, 1)
        XCTAssertEqual(session.handleKey(keyCode: 126, characters: nil, flags: [], windows: windows), .updated)
        XCTAssertEqual(session.selectedIndex, 0)
    }

    func testEnterWithNoSelectionIsIgnored() {
        var session = WindowSearchSession()
        XCTAssertEqual(session.handleKey(keyCode: 36, characters: nil, flags: [], windows: windows), .ignore)
    }

    func testEnterWithSelectionActivates() {
        var session = WindowSearchSession()
        _ = session.handleKey(keyCode: 8, characters: "c", flags: [], windows: windows)
        XCTAssertEqual(session.handleKey(keyCode: 36, characters: nil, flags: [], windows: windows), .activate)
        XCTAssertEqual(session.selectedIndex, 0)
    }

    func testNoMatchLeavesSelectionUnset() {
        var session = WindowSearchSession()
        _ = session.handleKey(keyCode: 45, characters: "n", flags: [], windows: windows)
        XCTAssertEqual(session.query, "n")
        XCTAssertEqual(session.selectedIndex, -1)
        XCTAssertEqual(session.handleKey(keyCode: 36, characters: nil, flags: [], windows: windows), .ignore)
    }

    func testPunctuationIsIgnored() {
        var session = WindowSearchSession()
        XCTAssertEqual(session.handleKey(keyCode: 44, characters: "/", flags: [], windows: windows), .ignore)
        XCTAssertTrue(session.query.isEmpty)
    }
}
