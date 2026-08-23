import Cocoa
import Symbols

/// Original Apple SF Symbol Effects animation strategy using `.byLayer` vector decomposition,
/// content replacement transitions, and `.disappear.byLayer` retract effects.
@MainActor
final class NativeSymbolEffectAnimationStrategy: OverlayAnimationStrategy {
    func applyEntry(
        for mode: CursorFeedbackOverlay.Mode,
        imageView: NSImageView,
        feedbackImage: NSImage
    ) {
        if #available(macOS 14.0, *) {
            imageView.removeAllSymbolEffects(animated: false)
        }

        let baseImage = mode.baseSymbol.flatMap {
            SymbolImageFactory.make(
                symbolName: $0,
                description: mode.accessibilityDescription,
                paletteColors: mode.basePaletteColors ?? mode.paletteColors
            )
        }

        imageView.image = baseImage ?? feedbackImage
        CATransaction.flush()

        // Morph transition via setSymbolImage
        if let replace = mode.replaceTransition {
            switch replace {
            case .magicReveal:
                if #available(macOS 26.0, *) {
                    imageView.setSymbolImage(
                        feedbackImage,
                        contentTransition: .replace.magic(fallback: .upUp.byLayer),
                        options: .nonRepeating
                    )
                } else if #available(macOS 14.0, *) {
                    imageView.setSymbolImage(
                        feedbackImage,
                        contentTransition: .replace.upUp.byLayer,
                        options: .nonRepeating
                    )
                } else {
                    imageView.image = feedbackImage
                }
            case .magicDownUpReveal:
                if #available(macOS 26.0, *) {
                    imageView.setSymbolImage(
                        feedbackImage,
                        contentTransition: .replace.magic(fallback: .downUp.wholeSymbol),
                        options: .nonRepeating
                    )
                } else if #available(macOS 14.0, *) {
                    imageView.setSymbolImage(
                        feedbackImage,
                        contentTransition: .replace.downUp.wholeSymbol,
                        options: .nonRepeating
                    )
                } else {
                    imageView.image = feedbackImage
                }
            case .downUpReveal:
                if #available(macOS 14.0, *) {
                    imageView.setSymbolImage(
                        feedbackImage,
                        contentTransition: .replace.downUp.byLayer,
                        options: .nonRepeating
                    )
                } else {
                    imageView.image = feedbackImage
                }
            case .replace:
                if #available(macOS 14.0, *) {
                    imageView.setSymbolImage(feedbackImage, contentTransition: .replace, options: .nonRepeating)
                } else {
                    imageView.image = feedbackImage
                }
            }
        } else {
            imageView.image = feedbackImage
        }

        // Native Symbol Effect entry animation
        if #available(macOS 14.0, *), let animation = mode.entryAnimation {
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
        if #available(macOS 14.0, *) {
            imageView.addSymbolEffect(.disappear.byLayer, options: .nonRepeating)
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            panel.animator().alphaValue = 0.0
        } completionHandler: {
            if panel.alphaValue == 0.0 {
                panel.orderOut(nil)
                if #available(macOS 14.0, *) {
                    imageView.removeAllSymbolEffects()
                }
                imageView.layer?.transform = CATransform3DIdentity
                completion()
            }
        }
    }
}
