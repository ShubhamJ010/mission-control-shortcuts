import Cocoa

/// A container view that hosts an animated overlay subview (such as `CloseButtonView`
/// or an `NSImageView`) with transparent bleed margins.
///
/// WindowServer hardware backing stores strictly clip drawing to `NSWindow.frame`.
/// By embedding the visual element centered inside an expanded container with generous
/// bleed padding and setting `masksToBounds = false`, CoreAnimation transforms (scaling
/// up on hover or bounce, lateral slide translations) and layer drop shadows render
/// completely smoothly without window boundary clipping.
///
/// Hit testing delegates exclusively to the hosted view: any mouse event falling in the
/// transparent bleed margin returns `nil`, passing through cleanly to underlying
/// Mission Control preview cards and desktop elements.
@MainActor
final class OverlayBleedContainerView: NSView {
    /// The interactive/visual view hosted in this container.
    let hostedView: NSView

    /// The margin in points added on all four sides around `hostedView`.
    let bleedMargin: CGFloat

    init(hostedView: NSView, bleedMargin: CGFloat = OverlayPanelFactory.defaultBleedMargin) {
        self.hostedView = hostedView
        self.bleedMargin = bleedMargin

        let hostedSize = hostedView.frame.size
        let containerFrame = NSRect(
            x: 0,
            y: 0,
            width: hostedSize.width + bleedMargin * 2.0,
            height: hostedSize.height + bleedMargin * 2.0
        )
        super.init(frame: containerFrame)

        wantsLayer = true
        layer?.masksToBounds = false

        hostedView.frame = NSRect(
            x: bleedMargin,
            y: bleedMargin,
            width: hostedSize.width,
            height: hostedSize.height
        )
        addSubview(hostedView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let pointInHosted = hostedView.convert(point, from: self)
        if hostedView.bounds.contains(pointInHosted) {
            return hostedView.hitTest(pointInHosted)
        }
        return nil
    }
}
