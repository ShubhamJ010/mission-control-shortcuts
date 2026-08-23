import Cocoa
import Foundation
import XCTest

final class WindowSelectionEngineTests: XCTestCase {
    private func window(
        owner: String,
        x: CGFloat = 0,
        y: CGFloat = 0,
        width: CGFloat = 400,
        height: CGFloat = 300,
        number: Int = 1
    ) -> [String: Any] {
        [
            kCGWindowOwnerName as String: owner,
            kCGWindowBounds as String: ["X": x, "Y": y, "Width": width, "Height": height],
            kCGWindowNumber as String: number
        ]
    }

    func testEmptyQueryReturnsNoMatches() {
        let windows = [window(owner: "Code"), window(owner: "Safari")]
        XCTAssertTrue(WindowSelectionEngine.fuzzyMatch(query: "", in: windows).isEmpty)
        XCTAssertTrue(WindowSelectionEngine.fuzzyMatch(query: "   ", in: windows).isEmpty)
    }

    func testPrefixBeatsSubstring() {
        let windows = [
            window(owner: "Xcode", number: 1),
            window(owner: "Code", number: 2)
        ]
        let matches = WindowSelectionEngine.fuzzyMatch(query: "co", in: windows)
        XCTAssertEqual(matches.map(\.ownerName), ["Code", "Xcode"])
        XCTAssertEqual(matches[0].rank, 0)
        XCTAssertEqual(matches[1].rank, 1)
    }

    func testSubstringStillMatches() {
        let windows = [window(owner: "Xcode")]
        let matches = WindowSelectionEngine.fuzzyMatch(query: "code", in: windows)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].ownerName, "Xcode")
        XCTAssertEqual(matches[0].rank, 1)
    }

    func testMatchIsCaseInsensitive() {
        let windows = [window(owner: "Safari")]
        let matches = WindowSelectionEngine.fuzzyMatch(query: "SAF", in: windows)
        XCTAssertEqual(matches.map(\.ownerName), ["Safari"])
        XCTAssertEqual(matches[0].rank, 0)
    }

    func testMissingOwnerIsSkipped() {
        let nameless: [String: Any] = [
            kCGWindowBounds as String: ["X": 0.0, "Y": 0.0, "Width": 400.0, "Height": 300.0],
            kCGWindowNumber as String: 9
        ]
        let windows = [nameless, window(owner: "Mail")]
        let matches = WindowSelectionEngine.fuzzyMatch(query: "m", in: windows)
        XCTAssertEqual(matches.map(\.ownerName), ["Mail"])
    }

    func testShoulderInsetMath() {
        let point = WindowSelectionEngine.shoulderPoint(
            for: ["X": 100, "Y": 200, "Width": 400, "Height": 300],
            inset: 20
        )
        XCTAssertEqual(point, CGPoint(x: 120, y: 220))
    }

    func testShoulderPointNilWithoutOrigin() {
        XCTAssertNil(WindowSelectionEngine.shoulderPoint(for: ["Width": 100, "Height": 100]))
    }

    func testSameOwnerWindowsOrderedByWindowNumber() {
        let windows = [
            window(owner: "Code", x: 500, number: 20),
            window(owner: "Code", x: 0, number: 10)
        ]
        let matches = WindowSelectionEngine.fuzzyMatch(query: "code", in: windows)
        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches[0].shoulderPoint.x, 20)
        XCTAssertEqual(matches[1].shoulderPoint.x, 520)
    }

    func testUnrelatedOwnersExcluded() {
        let windows = [window(owner: "Code"), window(owner: "Safari"), window(owner: "Finder")]
        let names = WindowSelectionEngine.fuzzyMatch(query: "code", in: windows).map(\.ownerName)
        XCTAssertEqual(names, ["Code"])
    }

    func testRowMajorSortedOrdersByYThenX() {
        let windows = [
            window(owner: "C", x: 500, y: 0, number: 3),
            window(owner: "A", x: 0, y: 0, number: 1),
            window(owner: "B", x: 0, y: 400, number: 2)
        ]
        let sorted = WindowSelectionEngine.rowMajorSorted(in: windows)
        XCTAssertEqual(sorted.map(\.ownerName), ["A", "C", "B"])
        XCTAssertEqual(sorted[0].shoulderPoint, CGPoint(x: 20, y: 20))
        XCTAssertEqual(sorted[1].shoulderPoint, CGPoint(x: 520, y: 20))
        XCTAssertEqual(sorted[2].shoulderPoint, CGPoint(x: 20, y: 420))
    }

    func testRowMajorSortedSkipsMissingBounds() {
        let bad: [String: Any] = [kCGWindowOwnerName as String: "Bad", kCGWindowNumber as String: 9]
        let good = window(owner: "Good", x: 10, y: 10)
        let sorted = WindowSelectionEngine.rowMajorSorted(in: [bad, good])
        XCTAssertEqual(sorted.map(\.ownerName), ["Good"])
    }
}
