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
        /// Precomputed window number for fast scalar sort comparison.
        let windowNumber: Int
        /// Precomputed bounding box in Quartz AX coordinates for $O(1)$ sort comparisons.
        let bounds: CGRect

        init(
            windowInfo: [String: Any],
            ownerName: String,
            centerPoint: CGPoint,
            shoulderPoint: CGPoint,
            rank: Int,
            windowNumber: Int = 0,
            bounds: CGRect = .zero
        ) {
            self.windowInfo = windowInfo
            self.ownerName = ownerName
            self.centerPoint = centerPoint
            self.shoulderPoint = shoulderPoint
            self.rank = rank
            self.windowNumber = windowNumber != 0 ? windowNumber : WindowSelectionEngine.windowNumber(windowInfo)
            self.bounds = bounds != .zero ? bounds : (WindowSelectionEngine.boundsRect(for: windowInfo) ?? .zero)
        }

        init(
            windowInfo: [String: Any],
            ownerName: String,
            shoulderPoint: CGPoint,
            rank: Int,
            windowNumber: Int = 0,
            bounds: CGRect = .zero
        ) {
            self.init(
                windowInfo: windowInfo,
                ownerName: ownerName,
                centerPoint: shoulderPoint,
                shoulderPoint: shoulderPoint,
                rank: rank,
                windowNumber: windowNumber,
                bounds: bounds
            )
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
        AppSignpost.trace(AppSignpost.search, "fuzzyMatch") {
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

                guard let bounds = boundsRect(for: window) else {
                    continue
                }
                let shoulder = CGPoint(x: bounds.origin.x + shoulderInset, y: bounds.origin.y + shoulderInset)
                let center = bounds.width > 0 && bounds.height > 0
                    ? CGPoint(x: bounds.midX, y: bounds.midY)
                    : shoulder
                let winNum = windowNumber(window)

                matches.append(Match(
                    windowInfo: window,
                    ownerName: ownerName,
                    centerPoint: center,
                    shoulderPoint: shoulder,
                    rank: rank,
                    windowNumber: winNum,
                    bounds: bounds
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
                return a.windowNumber < b.windowNumber
            }
            return matches
        }
    }

    /// Computes the bounding box `CGRect` once from a window dictionary.
    static func boundsRect(for windowInfo: [String: Any]) -> CGRect? {
        guard let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: Any] else {
            return nil
        }
        return boundsRect(from: boundsDict)
    }

    /// Computes the bounding box `CGRect` directly from a bounds dictionary.
    static func boundsRect(from boundsDict: [String: Any]) -> CGRect? {
        guard let xVal = boundsDict["X"], let yVal = boundsDict["Y"],
              let x = numberToCGFloat(xVal),
              let y = numberToCGFloat(yVal) else {
            return nil
        }
        let w = (boundsDict["Width"].flatMap { numberToCGFloat($0) }) ?? 0
        let h = (boundsDict["Height"].flatMap { numberToCGFloat($0) }) ?? 0
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Center (middle) point of `boundsDict`.
    /// When Tab cycling or fuzzy typing, the mouse cursor is placed in the
    /// middle of the preview rather than in the top-left corner.
    static func centerPoint(
        for boundsDict: [String: Any]
    ) -> CGPoint? {
        guard let rect = boundsRect(from: boundsDict) else {
            return nil
        }
        if rect.width > 0, rect.height > 0 {
            return CGPoint(x: rect.midX, y: rect.midY)
        }
        return CGPoint(x: rect.origin.x + defaultShoulderInset, y: rect.origin.y + defaultShoulderInset)
    }

    /// Top-left shoulder of `boundsDict`, inset right and down so the point
    /// sits on the thumbnail rather than on the hover-button vertex.
    static func shoulderPoint(
        for boundsDict: [String: Any],
        inset: CGFloat = defaultShoulderInset
    ) -> CGPoint? {
        guard let rect = boundsRect(from: boundsDict) else {
            return nil
        }
        return CGPoint(x: rect.origin.x + inset, y: rect.origin.y + inset)
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
        AppSignpost.trace(AppSignpost.search, "rowMajorSorted") {
            var matches: [Match] = []
            matches.reserveCapacity(windows.count)

            for window in windows {
                guard let ownerName = window[kCGWindowOwnerName as String] as? String,
                      !ownerName.isEmpty,
                      let bounds = boundsRect(for: window) else {
                    continue
                }
                let shoulder = CGPoint(x: bounds.origin.x + shoulderInset, y: bounds.origin.y + shoulderInset)
                let center = bounds.width > 0 && bounds.height > 0
                    ? CGPoint(x: bounds.midX, y: bounds.midY)
                    : shoulder
                let winNum = windowNumber(window)

                matches.append(Match(
                    windowInfo: window,
                    ownerName: ownerName,
                    centerPoint: center,
                    shoulderPoint: shoulder,
                    rank: 0,
                    windowNumber: winNum,
                    bounds: bounds
                ))
            }

            // O(N log N) sort using precomputed scalar CGRect values — zero dictionary lookups or NSNumber bridges
            matches.sort { a, b in
                let aY = a.bounds.origin.y
                let bY = b.bounds.origin.y
                if abs(aY - bY) > 40 {
                    return aY < bY
                }
                let aX = a.bounds.origin.x
                let bX = b.bounds.origin.x
                if aX != bX {
                    return aX < bX
                }
                return a.windowNumber < b.windowNumber
            }
            return matches
        }
    }

    static func windowNumber(_ info: [String: Any]) -> Int {
        if let n = info[kCGWindowNumber as String] as? NSNumber {
            return n.intValue
        }
        return 0
    }
}
