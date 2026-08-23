import Cocoa

/// Strategy interface defining entry and retract animations for CursorFeedbackOverlay.
/// Decouples the animation mechanism (CoreAnimation vs native SF Symbol Effects) from the overlay view.
@MainActor
protocol OverlayAnimationStrategy: AnyObject {
    /// Applies entry appearance, morphing, and motion effects for the given mode.
    func applyEntry(
        for mode: CursorFeedbackOverlay.Mode,
        imageView: NSImageView,
        feedbackImage: NSImage
    )

    /// Performs the retract and fade dismissal.
    func performRetract(
        panel: NSPanel,
        imageView: NSImageView,
        duration: TimeInterval,
        completion: @escaping () -> Void
    )

    /// Plays the entrance effect when an anchored overlay (e.g. the Mission
    /// Control preview close button) first becomes visible. `view` is the
    /// container view whose layer carries the whole button; `imageView` is the
    /// symbol image view inside it for strategies that target the symbol.
    func applyAppear(on view: NSView, imageView: NSImageView)

    /// Plays when an already-visible anchored overlay jumps to a new window
    /// anchor. Strategies that should not re-animate on relocation implement
    /// this as a no-op.
    func applyRelocationAppearance(on view: NSView, imageView: NSImageView)

    /// Cross-fades the displayed symbol when an overlay switches modes while visible.
    func applyModeChange(to image: NSImage, on imageView: NSImageView)

    /// Reflects mouse-over state on an anchored overlay button.
    func applyHover(on view: NSView, hovered: Bool)
}
