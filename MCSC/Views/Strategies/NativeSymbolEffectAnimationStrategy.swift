import Cocoa
import Symbols

/// Apple SF Symbol Effects animation strategy using `.byLayer` vector decomposition,
/// content replacement transitions, and `.disappear.byLayer` retract effects.
@MainActor
final class NativeSymbolEffectAnimationStrategy: OverlayAnimationStrategy {
    func applyEntry(
        for mode: CursorFeedbackOverlay.Mode,
        imageView: NSImageView,
        feedbackImage: NSImage
    ) {
        imageView.removeAllSymbolEffects(animated: false)

        let baseImage = mode.baseSymbol.flatMap {
            SymbolImageFactory.make(
                symbolName: $0,
                description: mode.accessibilityDescription,
                paletteColors: mode.basePaletteColors ?? mode.paletteColors
            )
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageView.image = baseImage ?? feedbackImage
        CATransaction.commit()
        CATransaction.flush()

        // Morph transition via setSymbolImage
        if let replace = mode.replaceTransition {
            switch replace {
            case .magicReveal:
                imageView.setSymbolImage(
                    feedbackImage,
                    contentTransition: .replace.magic(fallback: .upUp.byLayer),
                    options: .nonRepeating
                )
            case .magicDownUpReveal:
                imageView.setSymbolImage(
                    feedbackImage,
                    contentTransition: .replace.magic(fallback: .downUp.wholeSymbol),
                    options: .nonRepeating
                )
            case .downUpReveal:
                imageView.setSymbolImage(
                    feedbackImage,
                    contentTransition: .replace.downUp.byLayer,
                    options: .nonRepeating
                )
            case .replace:
                imageView.setSymbolImage(
                    feedbackImage,
                    contentTransition: .replace,
                    options: .nonRepeating
                )
            }
        } else {
            imageView.image = feedbackImage
        }

        // Native Symbol Effect entry animation
        if let animation = mode.entryAnimation {
            switch animation {
            case .bounceUpByLayer:
                imageView.addSymbolEffect(.bounce.up.byLayer, options: .nonRepeating)
            case .wiggleByLayer:
                imageView.addSymbolEffect(.wiggle.byLayer, options: .nonRepeating)
            }
        }

        // Subtle scale animation for close, quit, eject and fullscreen
        if mode == .close || mode == .quit || mode == .eject || mode == .fullscreen {
            imageView.layer?.transform = CATransform3DIdentity
            imageView.alphaValue = 0.97
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true
                imageView.animator().alphaValue = 1.0
                imageView.layer?.transform = CATransform3DMakeScale(1.03, 1.03, 1.0)
            }
        }
    }

    func performRetract(
        panel: NSPanel,
        imageView: NSImageView,
        duration: TimeInterval,
        completion: @escaping () -> Void
    ) {
        imageView.addSymbolEffect(.disappear.byLayer, options: .nonRepeating)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = 0.0
        } completionHandler: {
            panel.alphaValue = 0.0
            panel.orderOut(nil)
            imageView.removeAllSymbolEffects()
            imageView.layer?.transform = CATransform3DIdentity
            completion()
        }
    }

    func applyAppear(on _: NSView, imageView: NSImageView) {
        triggerAppearEffect(on: imageView)
    }

    func applyRelocationAppearance(on _: NSView, imageView: NSImageView) {
        triggerAppearEffect(on: imageView)
    }

    func applyModeChange(to image: NSImage, on imageView: NSImageView) {
        imageView.setSymbolImage(
            image,
            contentTransition: .replace.magic(fallback: .downUp.wholeSymbol),
            options: .nonRepeating
        )
    }

    func applyHover(on view: NSView, hovered: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            view.animator().alphaValue = hovered ? 1.0 : 0.97
            view.layer?.transform = hovered ? CATransform3DMakeScale(1.08, 1.08, 1.0) : CATransform3DIdentity
        }
    }

    /// Plays `.appear.byLayer` using native Symbol Effects.
    private func triggerAppearEffect(on imageView: NSImageView) {
        imageView.addSymbolEffect(.appear.byLayer, options: .nonRepeating)
    }
}
