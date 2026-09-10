import Cocoa

/// Represents a 2D screen coordinate in Quartz / AX space (origin top-left of primary screen).
typealias AXPoint = CGPoint

/// Represents a 2D screen coordinate in Cocoa space (origin bottom-left of primary screen).
typealias CocoaPoint = CGPoint

/// Shared coordinate-space transformation helpers bridging Quartz/Accessibility
/// coordinates (top-left origin) and Cocoa screen coordinates (bottom-left origin).
enum ScreenGeometry {
    /// Primary display height (in Cocoa points), used as reference for Y-axis inversion.
    static var primaryScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    /// Converts a Cocoa NSScreen frame to AX/Quartz bounds (origin top-left).
    static func axBounds(for screen: NSScreen, primaryHeight: CGFloat = primaryScreenHeight) -> CGRect {
        CGRect(
            x: screen.frame.origin.x,
            y: primaryHeight - screen.frame.origin.y - screen.frame.height,
            width: screen.frame.width,
            height: screen.frame.height
        )
    }

    /// Converts a Cocoa NSScreen visibleFrame (excluding menu bar and dock) to AX/Quartz bounds (origin top-left).
    static func axVisibleBounds(for screen: NSScreen, primaryHeight: CGFloat = primaryScreenHeight) -> CGRect {
        let visible = screen.visibleFrame
        return CGRect(
            x: visible.origin.x,
            y: primaryHeight - visible.origin.y - visible.height,
            width: visible.width,
            height: visible.height
        )
    }

    /// Returns the NSScreen whose AX bounds contain `point` (Quartz coords).
    static func screenContaining(axPoint point: AXPoint) -> NSScreen? {
        let primaryHeight = primaryScreenHeight
        return NSScreen.screens.first(where: {
            axBounds(for: $0, primaryHeight: primaryHeight).contains(point)
        }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// Converts a Quartz/AX point to Cocoa screen coordinates (origin bottom-left).
    static func cocoaPoint(for axPoint: AXPoint, primaryHeight: CGFloat = primaryScreenHeight) -> CocoaPoint {
        CGPoint(x: axPoint.x, y: primaryHeight - axPoint.y)
    }

    /// Converts a Quartz/AX screen point into a Cocoa screen origin that centers
    /// a panel of `panelSize` on the point, clamped so the panel never leaves the
    /// display that contains it.
    static func cocoaAnchorPoint(for point: AXPoint, panelSize: CGSize) -> CocoaPoint {
        let primaryHeight = primaryScreenHeight
        let halfW = panelSize.width / 2.0
        let halfH = panelSize.height / 2.0

        var x = point.x - halfW
        var y = (primaryHeight - point.y) - halfH

        let centerCocoa = CGPoint(x: point.x, y: primaryHeight - point.y)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(centerCocoa) })
            ?? NSScreen.screens.first
        if let frame = screen?.frame {
            x = min(max(x, frame.minX), frame.maxX - panelSize.width)
            y = min(max(y, frame.minY), frame.maxY - panelSize.height)
        }
        return CGPoint(x: x, y: y)
    }
}
