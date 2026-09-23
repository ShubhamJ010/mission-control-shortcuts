import CoreGraphics
import Foundation

/// Pure, stateless fuzzy matching over a Mission Control window list.
///
/// Matches `query` against `kCGWindowOwnerName` and ranks exact prefixes
/// ahead of substring hits. No service or view dependencies — reusable by
/// any feature that needs "pick a window by typing."
enum WindowSelectionEngine {
    /// Inset from the top-left window origin to the highlight shoulder point.
    /// Kept in sync with hover-button geometry (`PreviewCloseButtonOverlay`
    /// uses `buttonDimension/2 = 16`; 20 pt stays clear of the button while
    /// still landing on the thumbnail for grouped windows).
    static let defaultShoulderInset: CGFloat = 20

    /// A single ranked match, including both the middle center point and the
    /// shoulder point used to drive Mission Control's native highlight and mouse targeting.
    struct Match {
        let windowInfo: [String: Any]
        let ownerName: String
        /// Center point (middle) of the preview in AX/Quartz coordinates.
        let centerPoint: CGPoint
        /// Top-left inset in AX/Quartz coordinates, clear of the hover button.
        let shoulderPoint: CGPoint
        /// `0` = prefix match (best), `1` = substring match.
        let rank: Int

        init(windowInfo: [String: Any], ownerName: String, centerPoint: CGPoint, shoulderPoint: CGPoint, rank: Int) {
            self.windowInfo = windowInfo
            self.ownerName = ownerName
            self.centerPoint = centerPoint
            self.shoulderPoint = shoulderPoint
            self.rank = rank
        }

        init(windowInfo: [String: Any], ownerName: String, shoulderPoint: CGPoint, rank: Int) {
            self.windowInfo = windowInfo
            self.ownerName = ownerName
            self.centerPoint = shoulderPoint
            self.shoulderPoint = shoulderPoint
            self.rank = rank
        }
    }

    /// Matches `query` against each window's owner name.
    ///
    /// Empty or whitespace-only queries return an empty array. Results are
    /// sorted by rank, then localized owner name, then window number so
    /// several windows of the same app stay in a stable order.
    static func fuzzyMatch(
        query: String,
        in windows: [[String: Any]],
        shoulderInset: CGFloat = defaultShoulderInset
    ) -> [Match] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }

        var matches: [Match] = []
        matches.reserveCapacity(windows.count)

        for window in windows {
            guard let ownerName = window[kCGWindowOwnerName as String] as? String,
                  !ownerName.isEmpty else {
                continue
            }

            let haystack = ownerName.lowercased()
            let rank: Int
            if haystack.hasPrefix(needle) {
                rank = 0
            } else if haystack.contains(needle) {
                rank = 1
            } else {
                continue
            }

            guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let shoulder = shoulderPoint(for: bounds, inset: shoulderInset) else {
                continue
            }
            let center = centerPoint(for: bounds) ?? shoulder

            matches.append(Match(
                windowInfo: window,
                ownerName: ownerName,
                centerPoint: center,
                shoulderPoint: shoulder,
                rank: rank
            ))
        }

        matches.sort { a, b in
            if a.rank != b.rank {
                return a.rank < b.rank
            }
            let nameOrder = a.ownerName.localizedStandardCompare(b.ownerName)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return windowNumber(a.windowInfo) < windowNumber(b.windowInfo)
        }
        return matches
    }

    /// Center (middle) point of `boundsDict`.
    /// When Tab cycling or fuzzy typing, the mouse cursor is placed in the
    /// middle of the preview rather than in the top-left corner.
    static func centerPoint(
        for boundsDict: [String: Any]
    ) -> CGPoint? {
        guard let xVal = boundsDict["X"], let yVal = boundsDict["Y"],
              let x = numberToCGFloat(xVal),
              let y = numberToCGFloat(yVal) else {
            return nil
        }
        let w = (boundsDict["Width"].flatMap { numberToCGFloat($0) }) ?? 0
        let h = (boundsDict["Height"].flatMap { numberToCGFloat($0) }) ?? 0
        if w > 0, h > 0 {
            return CGPoint(x: x + w / 2.0, y: y + h / 2.0)
        }
        return CGPoint(x: x + defaultShoulderInset, y: y + defaultShoulderInset)
    }

    /// Top-left shoulder of `boundsDict`, inset right and down so the point
    /// sits on the thumbnail rather than on the hover-button vertex.
    static func shoulderPoint(
        for boundsDict: [String: Any],
        inset: CGFloat = defaultShoulderInset
    ) -> CGPoint? {
        guard let xVal = boundsDict["X"], let yVal = boundsDict["Y"],
              let x = numberToCGFloat(xVal),
              let y = numberToCGFloat(yVal) else {
            return nil
        }
        return CGPoint(x: x + inset, y: y + inset)
    }

    nonisolated private static func numberToCGFloat(_ value: Any) -> CGFloat? {
        if let n = value as? NSNumber {
            return CGFloat(n.doubleValue)
        }
        if let v = value as? CGFloat {
            return v
        }
        return nil
    }

    nonisolated private static func cgNumber(_ dict: [String: Any], key: String) -> Double {
        (dict[key] as? NSNumber)?.doubleValue ?? 0
    }

    /// Row-major ordering of all visible windows used for Tab cycling when no
    /// query is active. Unlike `fuzzyMatch(query:in:)` this does not filter by
    /// owner name — every window with a valid owner and bounds is included with
    /// `rank == 0` (see `Match.rank`). Ordering is top-to-bottom then
    /// left-to-right with a 40 pt vertical row tolerance so thumbnails that are
    /// slightly misaligned on the same row are treated as the same row,
    /// avoiding jitter. Ties on X fall back to `windowNumber` for stability
    /// when several windows share an owner.
    static func rowMajorSorted(
        in windows: [[String: Any]],
        shoulderInset: CGFloat = defaultShoulderInset
    ) -> [Match] {
        var matches: [Match] = []
        matches.reserveCapacity(windows.count)

        for window in windows {
            guard let ownerName = window[kCGWindowOwnerName as String] as? String,
                  !ownerName.isEmpty,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let shoulder = shoulderPoint(for: bounds, inset: shoulderInset) else {
                continue
            }
            let center = centerPoint(for: bounds) ?? shoulder

            matches.append(Match(
                windowInfo: window,
                ownerName: ownerName,
                centerPoint: center,
                shoulderPoint: shoulder,
                rank: 0
            ))
        }

        matches.sort { a, b in
            let aBounds = a.windowInfo[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let bBounds = b.windowInfo[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let aY = cgNumber(aBounds, key: "Y")
            let bY = cgNumber(bBounds, key: "Y")
            if abs(aY - bY) > 40 {
                return aY < bY
            }
            let aX = cgNumber(aBounds, key: "X")
            let bX = cgNumber(bBounds, key: "X")
            if aX != bX {
                return aX < bX
            }
            return windowNumber(a.windowInfo) < windowNumber(b.windowInfo)
        }
        return matches
    }

    private static func windowNumber(_ info: [String: Any]) -> Int {
        if let n = info[kCGWindowNumber as String] as? NSNumber {
            return n.intValue
        }
        return 0
    }
}
