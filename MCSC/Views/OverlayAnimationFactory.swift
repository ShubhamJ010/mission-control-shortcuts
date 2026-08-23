import Cocoa

/// Tailored animation styles executed on view layers via hardware-accelerated
/// CoreAnimation without Metal or SF SymbolKit private pipeline overhead.
enum OverlayAnimationStyle {
    case bouncePop
    case wiggle
    case pulseExpand
    case shrinkDown
    case slideRight
    case slideLeft
}

/// Shared animation factory for overlay panels (CursorFeedbackOverlay, PreviewCloseButtonOverlay).
/// Provides zero-allocation, hardware-accelerated CoreAnimation keyframe curves,
/// outline-to-filled morphing cross-fades, and smooth dissolve dismissals.
@MainActor
enum OverlayAnimationFactory {
    /// Applies a tailored entry animation curve to the given layer.
    static func applyEntryAnimation(style: OverlayAnimationStyle, on layer: CALayer) {
        layer.removeAnimation(forKey: "overlayEntryAnimation")

        switch style {
        case .bouncePop:
            let animation = CAKeyframeAnimation(keyPath: "transform.scale")
            animation.values = [0.72, 1.18, 0.94, 1.04, 1.0]
            animation.keyTimes = [0.0, 0.38, 0.65, 0.85, 1.0]
            animation.duration = 0.28
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(animation, forKey: "overlayEntryAnimation")

        case .wiggle:
            let rotAnimation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            rotAnimation.values = [0.0, -0.12, 0.12, -0.06, 0.06, 0.0]
            rotAnimation.keyTimes = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]
            rotAnimation.duration = 0.24
            rotAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            let scaleAnimation = CAKeyframeAnimation(keyPath: "transform.scale")
            scaleAnimation.values = [0.82, 1.12, 0.96, 1.0]
            scaleAnimation.keyTimes = [0.0, 0.45, 0.75, 1.0]
            scaleAnimation.duration = 0.24
            scaleAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)

            let group = CAAnimationGroup()
            group.animations = [rotAnimation, scaleAnimation]
            group.duration = 0.24
            layer.add(group, forKey: "overlayEntryAnimation")

        case .pulseExpand:
            let animation = CAKeyframeAnimation(keyPath: "transform.scale")
            animation.values = [0.82, 1.20, 0.97, 1.0]
            animation.keyTimes = [0.0, 0.45, 0.75, 1.0]
            animation.duration = 0.22
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(animation, forKey: "overlayEntryAnimation")

        case .shrinkDown:
            addTranslationScaleGroup(
                on: layer,
                translationKeyPath: "transform.translation.y",
                translationValues: [0.0, -3.5, 0.0],
                translationTimingFunction: .easeInEaseOut,
                scaleValues: [1.08, 0.92, 1.0],
                keyTimes: [0.0, 0.5, 1.0],
                duration: 0.22
            )

        case .slideRight:
            addTranslationScaleGroup(
                on: layer,
                translationKeyPath: "transform.translation.x",
                translationValues: [-9.0, 3.0, 0.0],
                translationTimingFunction: .easeOut,
                scaleValues: [0.88, 1.06, 1.0],
                keyTimes: [0.0, 0.55, 1.0],
                duration: 0.24
            )

        case .slideLeft:
            addTranslationScaleGroup(
                on: layer,
                translationKeyPath: "transform.translation.x",
                translationValues: [9.0, -3.0, 0.0],
                translationTimingFunction: .easeOut,
                scaleValues: [0.88, 1.06, 1.0],
                keyTimes: [0.0, 0.55, 1.0],
                duration: 0.24
            )
        }
    }

    /// Shared shape for entry curves that combine a translation keyframe with a
    /// scale keyframe in one animation group (shrinkDown / slideRight / slideLeft).
    /// Both sub-animations share `keyTimes` and `duration`; only the translation
    /// axis, its values, and its easing differ per style.
    private static func addTranslationScaleGroup(
        on layer: CALayer,
        translationKeyPath: String,
        translationValues: [CGFloat],
        translationTimingFunction: CAMediaTimingFunctionName,
        scaleValues: [CGFloat],
        keyTimes: [NSNumber],
        duration: TimeInterval
    ) {
        let transAnimation = CAKeyframeAnimation(keyPath: translationKeyPath)
        transAnimation.values = translationValues
        transAnimation.keyTimes = keyTimes
        transAnimation.duration = duration
        transAnimation.timingFunction = CAMediaTimingFunction(name: translationTimingFunction)

        let scaleAnimation = CAKeyframeAnimation(keyPath: "transform.scale")
        scaleAnimation.values = scaleValues
        scaleAnimation.keyTimes = keyTimes
        scaleAnimation.duration = duration
        scaleAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let group = CAAnimationGroup()
        group.animations = [transAnimation, scaleAnimation]
        group.duration = duration
        layer.add(group, forKey: "overlayEntryAnimation")
    }

    /// Smooth cross-fade transition from a base outline silhouette to a filled colored symbol.
    static func applyMorphTransition(on layer: CALayer, duration: TimeInterval = 0.16) {
        let transition = CATransition()
        transition.type = .fade
        transition.duration = duration
        transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(transition, forKey: "overlayMorphTransition")
    }

    /// Fades out the overlay panel and shrinks the image view smoothly.
    static func performFadeOut(
        panel: NSPanel,
        imageView: NSImageView,
        duration: TimeInterval,
        completion: @escaping () -> Void
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = 0.0
            imageView.animator().layer?.transform = CATransform3DMakeScale(0.75, 0.75, 1.0)
        } completionHandler: {
            if panel.alphaValue == 0.0 {
                panel.orderOut(nil)
                imageView.layer?.transform = CATransform3DIdentity
                imageView.layer?.removeAllAnimations()
                completion()
            }
        }
    }

    /// Applies standard interactive hover scale animation to a view layer.
    static func applyHoverScale(on layer: CALayer, hovered: Bool, duration: TimeInterval = 0.15) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            layer.transform = hovered ? CATransform3DMakeScale(1.08, 1.08, 1.0) : CATransform3DIdentity
        }
    }
}
