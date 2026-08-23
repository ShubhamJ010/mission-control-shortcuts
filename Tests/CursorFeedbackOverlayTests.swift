import Cocoa
import Foundation
import XCTest

@MainActor
final class CursorFeedbackOverlayTests: XCTestCase {
    private let panelSize = CGSize(width: 34, height: 34)

    func testCentersPanelOnAXPoint() {
        let primary = NSScreen.screens.first?.frame ?? .zero
        guard primary != .zero, primary.width > 100, primary.height > 100 else {
            XCTFail("No usable primary screen for centering test")
            return
        }

        // A point at the middle of the primary screen, expressed in
        // Quartz/AX coordinates (origin top-left).
        let axPoint = CGPoint(x: primary.midX, y: primary.height - primary.midY)

        let anchor = CursorFeedbackOverlay.cocoaAnchorPoint(for: axPoint, panelSize: panelSize)

        // The panel center (Cocoa coords) must land exactly on the AX point.
        XCTAssertEqual(anchor.x + panelSize.width / 2, axPoint.x, accuracy: 0.5,
                       "Panel should be horizontally centered on the AX point")
        XCTAssertEqual(anchor.y + panelSize.height / 2, primary.height - axPoint.y, accuracy: 0.5,
                       "Panel should be vertically centered on the AX point")
    }

    func testClampsToScreenBounds() {
        let primary = NSScreen.screens.first?.frame ?? .zero
        guard primary != .zero else {
            XCTFail("No primary screen for clamp test")
            return
        }

        // AX point far above/left of the primary screen's top-left corner.
        let topLeft = CursorFeedbackOverlay.cocoaAnchorPoint(
            for: CGPoint(x: -200, y: -200), panelSize: panelSize
        )
        XCTAssertGreaterThanOrEqual(topLeft.x, primary.minX, "Panel x must stay inside screen")
        XCTAssertGreaterThanOrEqual(topLeft.y, primary.minY, "Panel y must stay inside screen")

        // AX point far below/right of the primary screen's bottom-right corner.
        let bottomRight = CursorFeedbackOverlay.cocoaAnchorPoint(
            for: CGPoint(x: primary.width + 200, y: primary.height + 200), panelSize: panelSize
        )
        XCTAssertLessThanOrEqual(bottomRight.x + panelSize.width, primary.maxX + 0.5,
                                 "Panel must not overflow right edge")
        XCTAssertLessThanOrEqual(bottomRight.y + panelSize.height, primary.maxY + 0.5,
                                 "Panel must not overflow bottom edge")
    }

    // MARK: - Mode descriptor integrity

    /// Renders a symbol exactly the way `CursorFeedbackOverlay` / `CloseButtonView`
    /// do (24 pt semibold, palette-tinted or multicolor). A `nil` here means the
    /// SF Symbol name is missing on the running OS, which would silently no-op
    /// the feedback for that action.
    private func renderedSymbol(symbolName: String,
                                accessibility: String,
                                palette: [NSColor]?) -> NSImage? {
        var config = NSImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        if let palette {
            config = config.applying(NSImage.SymbolConfiguration(paletteColors: palette))
        } else {
            config = config.applying(NSImage.SymbolConfiguration.preferringMulticolor())
        }
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibility)?
            .withSymbolConfiguration(config)
    }

    func testCursorFeedbackModesAllRenderSymbols() {
        // Every shortcut/gesture feedback type must resolve to a real SF
        // Symbol, otherwise its feedback silently disappears.
        XCTAssertEqual(CursorFeedbackOverlay.Mode.allCases.count, 17,
                       "Adding a feedback mode must also extend this coverage")
        for mode in CursorFeedbackOverlay.Mode.allCases {
            let image = renderedSymbol(symbolName: mode.symbolName,
                                       accessibility: mode.accessibilityDescription,
                                       palette: mode.paletteColors)
            XCTAssertNotNil(image,
                            "CursorFeedbackOverlay.Mode.\(mode) failed to render '\(mode.symbolName)'")
            XCTAssertFalse(mode.accessibilityDescription.isEmpty,
                           "CursorFeedbackOverlay.Mode.\(mode) needs an accessibility description")
        }
    }

    func testEjectModeUsesEjectCircleFillSymbolWithRedPrimary() {
        let mode = CursorFeedbackOverlay.Mode.eject
        XCTAssertEqual(mode.symbolName, "eject.circle.fill")
        XCTAssertEqual(mode.accessibilityDescription, "Eject Volume")
        let palette = mode.paletteColors
        XCTAssertEqual(palette?.count, 2)
        XCTAssertEqual(palette?[0], .white)
        XCTAssertEqual(palette?[1], .systemRed)
    }

    func testSpaceModesUseArrowCircleSymbolsWithWhiteAccentPalette() {
        // Space navigation uses a two-layer `circle.fill` glyph: white primary
        // + system accent (see `CursorFeedbackMode.paletteColors`).
        XCTAssertEqual(CursorFeedbackOverlay.Mode.spaceRight.symbolName, "arrow.right.circle.fill")
        XCTAssertEqual(CursorFeedbackOverlay.Mode.spaceRight.accessibilityDescription,
                       "Move Window to Next Desktop")
        XCTAssertEqual(CursorFeedbackOverlay.Mode.spaceLeft.symbolName, "arrow.left.circle.fill")
        XCTAssertEqual(CursorFeedbackOverlay.Mode.spaceLeft.accessibilityDescription,
                       "Move Window to Previous Desktop")
        for mode in [CursorFeedbackOverlay.Mode.spaceRight, .spaceLeft] {
            XCTAssertEqual(mode.paletteColors?.count, 2)
            XCTAssertEqual(mode.paletteColors?[0], .white)
            XCTAssertEqual(mode.paletteColors?[1], .controlAccentColor)
        }
    }

    func testHoverButtonModesAllRenderSymbols() {
        // Close / Minimize / Force-Quit / Fullscreen hover buttons must all render.
        XCTAssertEqual(PreviewCloseButtonOverlay.Mode.allCases.count, 4,
                       "Adding a hover mode must update this coverage")
        for mode in PreviewCloseButtonOverlay.Mode.allCases {
            let image = renderedSymbol(symbolName: mode.symbolName,
                                       accessibility: mode.accessibilityDescription,
                                       palette: mode.paletteColors)
            XCTAssertNotNil(image,
                            "PreviewCloseButtonOverlay.Mode.\(mode) failed to render '\(mode.symbolName)'")
            XCTAssertFalse(mode.accessibilityDescription.isEmpty,
                           "PreviewCloseButtonOverlay.Mode.\(mode) needs an accessibility description")
        }
    }

    func testFullscreenModeUsesArrowsSymbol() {
        let mode = PreviewCloseButtonOverlay.Mode.fullscreen
        XCTAssertEqual(mode.symbolName, "arrow.down.left.and.arrow.up.right.circle.fill")
    }

    func testFullscreenModePaletteIsBlackAndGreen() {
        let mode = PreviewCloseButtonOverlay.Mode.fullscreen
        let palette = mode.paletteColors
        XCTAssertEqual(palette?.count, 2)
        // First layer (glyph outline) black, second (fill) green.
        XCTAssertEqual(palette?[0], .black)
        XCTAssertEqual(palette?[1], .systemGreen)
    }
}
