import Cocoa
import Foundation
import XCTest

@MainActor
final class OverlayAnimationStrategyTests: XCTestCase {

    override func setUp() {
        super.setUp()
        clearStoredToggles()
    }

    override func tearDown() {
        clearStoredToggles()
        super.tearDown()
    }

    private func clearStoredToggles() {
        for entry in ShortcutConfiguration.toggleDefaults {
            UserDefaults.standard.removeObject(forKey: entry.key)
        }
    }

    func testOptimizedAnimationFactoryEntryAnimations() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 34, height: 34))
        view.wantsLayer = true
        guard let layer = view.layer else {
            XCTFail("Layer should be non-nil when wantsLayer is true")
            return
        }

        OverlayAnimationFactory.applyEntryAnimation(style: .bouncePop, on: layer)
        XCTAssertNotNil(layer.animation(forKey: "overlayEntryAnimation"))

        OverlayAnimationFactory.applyEntryAnimation(style: .wiggle, on: layer)
        XCTAssertNotNil(layer.animation(forKey: "overlayEntryAnimation"))

        OverlayAnimationFactory.applyEntryAnimation(style: .pulseExpand, on: layer)
        XCTAssertNotNil(layer.animation(forKey: "overlayEntryAnimation"))
    }

    func testCursorFeedbackOverlayAppliesOptimizedStrategy() {
        let strategy = OptimizedOverlayAnimationStrategy()
        let overlay = CursorFeedbackOverlay(strategy: strategy)

        let point = CGPoint(x: 200, y: 200)
        overlay.show(at: point, mode: .close)
        overlay.hide()
    }

    func testCursorFeedbackOverlayAppliesNativeStrategy() {
        let strategy = NativeSymbolEffectAnimationStrategy()
        let overlay = CursorFeedbackOverlay(strategy: strategy)

        let point = CGPoint(x: 200, y: 200)
        overlay.show(at: point, mode: .almost)
        overlay.hide()
    }

    func testPreviewCloseButtonOverlayStrategyInitialization() {
        let optimizedOverlay = PreviewCloseButtonOverlay(strategy: OptimizedOverlayAnimationStrategy())
        XCTAssertTrue(optimizedOverlay.strategy is OptimizedOverlayAnimationStrategy)

        let nativeOverlay = PreviewCloseButtonOverlay(strategy: NativeSymbolEffectAnimationStrategy())
        XCTAssertFalse(nativeOverlay.strategy is OptimizedOverlayAnimationStrategy)
    }

    func testStrategiesConformToAnchorOverlayInterface() {
        // Both backends must implement the anchored-overlay behaviours that
        // PreviewCloseButtonOverlay delegates to the strategy.
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        view.wantsLayer = true
        let imageView = NSImageView(frame: view.bounds)

        let strategies: [OverlayAnimationStrategy] = [
            OptimizedOverlayAnimationStrategy(),
            NativeSymbolEffectAnimationStrategy()
        ]
        for strategy in strategies {
            // Must not crash and must leave the view in a consistent state.
            strategy.applyAppear(on: view, imageView: imageView)
            strategy.applyRelocationAppearance(on: view, imageView: imageView)

            if let image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "test") {
                strategy.applyModeChange(to: image, on: imageView)
            }
            strategy.applyHover(on: view, hovered: true)
            strategy.applyHover(on: view, hovered: false)
        }
    }

    func testShortcutConfigurationOptimizedAnimationModePersistence() {
        var config = ShortcutConfiguration()
        XCTAssertTrue(config.isOptimizedAnimationModeEnabled, "Defaults to true for 12 MB baseline performance")

        config.isOptimizedAnimationModeEnabled = false
        XCTAssertFalse(config.isOptimizedAnimationModeEnabled)

        // Fresh instance reading from UserDefaults
        let reloadedConfig = ShortcutConfiguration()
        XCTAssertFalse(reloadedConfig.isOptimizedAnimationModeEnabled)

        // Restoring defaults sets it back to true
        var restoringConfig = ShortcutConfiguration()
        restoringConfig.restoreDefaults()
        XCTAssertTrue(restoringConfig.isOptimizedAnimationModeEnabled)
    }
}
