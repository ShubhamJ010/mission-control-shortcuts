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
                setSymbolImageReplacing(feedbackImage, on: imageView, onMacOS26: {
                    imageView.setSymbolImage(
                        feedbackImage,
                        contentTransition: .replace.magic(fallback: .upUp.byLayer),
                        options: .nonRepeating
                    )
                }, onMacOS14: {
                    imageView.setSymbolImage(
                        feedbackImage,
                        contentTransition: .replace.upUp.byLayer,
                        options: .nonRepeating
                    )
                })
            case .magicDownUpReveal:
                setSymbolImageReplacing(feedbackImage, on: imageView, onMacOS26: {
                    imageView.setSymbolImage(
                        feedbackImage,
                        contentTransition: .replace.magic(fallback: .downUp.wholeSymbol),
                        options: .nonRepeating
                    )
                }, onMacOS14: {
                    imageView.setSymbolImage(
                        feedbackImage,
                        contentTransition: .replace.downUp.wholeSymbol,
                        options: .nonRepeating
                    )
                })
            case .downUpReveal:
                setSymbolImageReplacing(feedbackImage, on: imageView, onMacOS14: {
                    imageView.setSymbolImage(
                        feedbackImage,
                        contentTransition: .replace.downUp.byLayer,
                        options: .nonRepeating
                    )
                })
            case .replace:
                setSymbolImageReplacing(feedbackImage, on: imageView, onMacOS14: {
                    imageView.setSymbolImage(feedbackImage, contentTransition: .replace, options: .nonRepeating)
                })
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

    /// Collapses the repeated `#available(macOS 26.0)` → `#available(macOS 14.0)`
    /// → plain-swap cascade into one call site. Each closure runs only when its
    /// OS gate passes, so the availability annotations inside stay valid; when a
    /// transition has no dedicated macOS 26 variant, pass only `onMacOS14` and it
    /// also serves macOS 26 (the macOS 14 API is available there).
    private func setSymbolImageReplacing(
        _ image: NSImage,
        on imageView: NSImageView,
        onMacOS26: (() -> Void)? = nil,
        onMacOS14: () -> Void
    ) {
        if #available(macOS 26.0, *), let onMacOS26 {
            onMacOS26()
        } else if #available(macOS 14.0, *) {
            onMacOS14()
        } else {
            imageView.image = image
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

    func applyAppear(on _: NSView, imageView: NSImageView) {
        triggerAppearEffect(on: imageView)
    }

    func applyRelocationAppearance(on _: NSView, imageView: NSImageView) {
        triggerAppearEffect(on: imageView)
    }

    func applyModeChange(to image: NSImage, on imageView: NSImageView) {
        setSymbolImageReplacing(image, on: imageView, onMacOS14: {
            imageView.setSymbolImage(
                image,
                contentTransition: .replace.magic(fallback: .downUp.wholeSymbol),
                options: .nonRepeating
            )
        })
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

    /// Plays `.appear.byLayer` when symbol effects are available.
    private func triggerAppearEffect(on imageView: NSImageView) {
        if #available(macOS 14.0, *) {
            imageView.addSymbolEffect(.appear.byLayer, options: .nonRepeating)
        }
    }
}
