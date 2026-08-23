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
}
