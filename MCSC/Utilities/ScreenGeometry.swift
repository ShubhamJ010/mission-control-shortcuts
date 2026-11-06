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

    /// Returns the AX/Quartz bounds of the macOS menu bar on `screen` if present.
    /// Returns `nil` for secondary screens that do not display a menu bar.
    static func menuBarFrame(for screen: NSScreen, primaryHeight: CGFloat = primaryScreenHeight) -> CGRect? {
        let topDiff = screen.frame.maxY - screen.visibleFrame.maxY
        let height: CGFloat
        if topDiff > 0 {
            height = topDiff
        } else if screen == NSScreen.screens.first || NSScreen.screensHaveSeparateSpaces {
            let safeTop = screen.safeAreaInsets.top
            height = safeTop > 0 ? safeTop : NSStatusBar.system.thickness
        } else {
            return nil
        }
        guard height > 0 else { return nil }

        let screenAX = axBounds(for: screen, primaryHeight: primaryHeight)
        return CGRect(
            x: screenAX.minX,
            y: screenAX.minY,
            width: screenAX.width,
            height: height
        )
    }

    /// `true` when `point` (in Quartz/AX coords) lies within the macOS menu bar region of any display.
    static func isMenuBarRegion(at point: AXPoint) -> Bool {
        guard let screen = screenContaining(axPoint: point),
              let menuBar = menuBarFrame(for: screen) else {
            return false
        }
        return menuBar.contains(point)
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
            ?? screenContaining(axPoint: point)
            ?? NSScreen.screens.first
        if let frame = screen?.frame {
            x = min(max(x, frame.minX), frame.maxX - panelSize.width)
            y = min(max(y, frame.minY), frame.maxY - panelSize.height)
        }
        return CGPoint(x: x, y: y)
    }
}
