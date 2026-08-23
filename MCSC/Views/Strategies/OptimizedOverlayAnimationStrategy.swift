import Cocoa

/// Zero-overhead animation strategy powered by hardware-accelerated CoreAnimation.
/// Provides smooth outline-to-filled morphing, Apple spring bounces, and clean dissolves with 0 MB GPU/Metal spike.
@MainActor
final class OptimizedOverlayAnimationStrategy: OverlayAnimationStrategy {
    func applyEntry(
        for mode: CursorFeedbackOverlay.Mode,
        imageView: NSImageView,
        feedbackImage: NSImage
    ) {
        if let baseSymbol = mode.baseSymbol,
           let baseImage = SymbolImageFactory.make(
               symbolName: baseSymbol,
               description: mode.accessibilityDescription,
               paletteColors: mode.basePaletteColors ?? mode.paletteColors
           ),
           let layer = imageView.layer {
            imageView.image = baseImage
            OverlayAnimationFactory.applyMorphTransition(on: layer)
            imageView.image = feedbackImage
        } else {
            imageView.image = feedbackImage
        }

        if let layer = imageView.layer {
            OverlayAnimationFactory.applyEntryAnimation(style: mode.animationStyle, on: layer)
        }
    }

    func applyAppear(on view: NSView, imageView _: NSImageView) {
        guard let layer = view.layer else { return }
        OverlayAnimationFactory.applyEntryAnimation(style: .bouncePop, on: layer)
    }

    func applyRelocationAppearance(on _: NSView, imageView _: NSImageView) {
        // Zero-overhead mode deliberately stays quiet on anchor moves so the
        // button does not re-bounce while tracking the cursor across previews.
    }

    func applyModeChange(to image: NSImage, on imageView: NSImageView) {
        if let layer = imageView.layer {
            OverlayAnimationFactory.applyMorphTransition(on: layer)
        }
        imageView.image = image
    }

    func applyHover(on view: NSView, hovered: Bool) {
        guard let layer = view.layer else { return }
        OverlayAnimationFactory.applyHoverScale(on: layer, hovered: hovered)
    }

    func performRetract(
        panel: NSPanel,
        imageView: NSImageView,
        duration: TimeInterval,
        completion: @escaping () -> Void
    ) {
        OverlayAnimationFactory.performFadeOut(
            panel: panel,
            imageView: imageView,
            duration: duration,
            completion: completion
        )
    }
}
