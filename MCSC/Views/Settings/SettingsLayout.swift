import Cocoa

// Faithful port of usagimaru/MacAppSettingsUI (Sources/Layout/Section-based),
// trimmed of debug wireframes, localization and storyboard helpers.

/// Layout metrics of a settings pane.
enum SettingsLayoutMetrics {
    /// Spacing between sections.
    static let sectionSpacing: CGFloat = 20
    /// Spacing between the label column and the item column.
    static let columnSpacing: CGFloat = 8
    /// Spacing between items within a section.
    static let itemSpacing: CGFloat = 6
}

/// Ladder of layout priorities of a settings pane.
enum SettingsLayoutPriority {
    /// Width a section declares for the item column. Not required, so that wider items can still push the column open.
    static let itemColumnDeclaredWidth = NSLayoutConstraint.Priority(rawValue: 999)
    /// Width a description label asks of the item column. Loses to a declared width, beats the shrink.
    static let descriptionWidthDemand = NSLayoutConstraint.Priority(rawValue: 500)
    /// Force that hugs the item column to what its items need.
    static let itemColumnWidthShrink = NSLayoutConstraint.Priority(rawValue: 300)
    /// Force that hugs the label column to its longest label.
    static let labelColumnWidthShrink = NSLayoutConstraint.Priority(rawValue: 250)
    /// Force that fills the container. Weakest of the three, so it only takes effect while no column shrinks it.
    static let contentWidthGrow = NSLayoutConstraint.Priority(rawValue: 200)
    /// Horizontal priority of controls that take no part in deciding a column width.
    static let nonContributing = NSLayoutConstraint.Priority(rawValue: 50)
    /// Force that fills the pane vertically. Not required, so a pane dragged shorter bends instead of breaking.
    static let contentHeightGrow = NSLayoutConstraint.Priority(rawValue: 999)
    /// Height a stretching section asks for. Beats the shrink, gives way to a shorter pane.
    static let sectionPreferredHeight = NSLayoutConstraint.Priority(rawValue: 251)
    /// Force that hugs a stretching section to its lower bound. Weakest of all, so the surplus lands there.
    static let sectionHeightShrink = NSLayoutConstraint.Priority(rawValue: 1)
}

/// A description label that shrinks to its text and wraps at a width handed
/// down from the outside (its own bounds would make the width chase itself).
final class SettingsWrappingLabel: NSTextField {
    var availableWidth: CGFloat = 0 {
        didSet {
            guard availableWidth != oldValue else { return }
            preferredMaxLayoutWidth = availableWidth
            invalidateIntrinsicContentSize()
        }
    }

    init(string: String) {
        super.init(frame: .zero)
        stringValue = string
        isEditable = false
        isBezeled = false
        isBordered = false
        backgroundColor = .clear
        isSelectable = false
        usesSingleLineMode = false
        lineBreakMode = .byWordWrapping
        maximumNumberOfLines = 0
        cell?.wraps = true
        cell?.isScrollable = false
        font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        textColor = .secondaryLabelColor
        alignment = .natural

        // Take no part in deciding the column width, but do shrink the box down to the text.
        setContentCompressionResistancePriority(SettingsLayoutPriority.nonContributing, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    /// Width the text takes on a single line; the column asks for this much
    /// before settling on a narrower, wrapping box.
    var naturalTextWidth: CGFloat {
        let unbounded = NSRect(x: 0, y: 0, width: 10000, height: 10000)
        return cell?.cellSize(forBounds: unbounded).width ?? 0
    }
}

/// Width a section's content spans.
enum SettingsSectionWidthMode {
    /// Line up with the two-column block, so the edges match the column sections.
    case contentBlock
    /// Span the whole container width.
    case fullWidth
}

/// Height a section takes.
enum SettingsSectionHeightMode {
    /// Follow the height of the content.
    case fitsContent
    /// Take in the surplus height of the pane, never falling below the minimum height.
    case flexible(minimumHeight: CGFloat, preferredHeight: CGFloat)
}

/// Vertical alignment of an item in a section against its label.
enum SettingsItemVerticalAlignment {
    case firstBaseline
    case top
    case centerY
}

/// A unit of view stacked in a `SettingsLayoutView`.
class SettingsSectionView: NSView {
    /// Box holding the section content. Its width follows the width mode and it stays centered.
    let contentGuide = NSLayoutGuide()

    /// Which width the content box follows. Switching it swaps the active width constraint.
    var widthMode: SettingsSectionWidthMode = .contentBlock {
        didSet { updateContentWidthConstraint() }
    }

    /// Whether the section takes in surplus height. Switching it swaps the active height constraints.
    var heightMode: SettingsSectionHeightMode = .fitsContent {
        didSet {
            updateHeightConstraints()
            layoutView?.invalidateFlexibleSections()
        }
    }

    /// The container this section was added to.
    weak var layoutView: SettingsLayoutView?

    /// Width of the section itself, which the container has already stretched to its full width.
    private var fullWidthConstraint: NSLayoutConstraint?
    /// Width shared with the two-column block. Absent while the section stands outside a container.
    private var contentBlockWidthConstraint: NSLayoutConstraint?
    /// Lower bound the section keeps while it takes in surplus height.
    private var minimumHeightConstraint: NSLayoutConstraint?
    /// Height the section asks for. It gives way once the pane is dragged shorter.
    private var preferredHeightConstraint: NSLayoutConstraint?

    init(identifier: NSUserInterfaceItemIdentifier? = nil) {
        super.init(frame: .zero)
        self.identifier = identifier
        setUpContentGuide()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    private func setUpContentGuide() {
        addLayoutGuide(contentGuide)

        NSLayoutConstraint.activate([
            contentGuide.topAnchor.constraint(equalTo: topAnchor),
            contentGuide.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentGuide.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentGuide.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            contentGuide.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)
        ])

        fullWidthConstraint = contentGuide.widthAnchor.constraint(equalTo: widthAnchor)
        updateContentWidthConstraint()
    }

    /// Take over the container's shared block width. Whether the section actually follows it is up to the width mode.
    func adoptContentWidth(from widthGuide: NSLayoutGuide) {
        contentBlockWidthConstraint = contentGuide.widthAnchor.constraint(equalTo: widthGuide.widthAnchor)
        updateContentWidthConstraint()
    }

    private func updateContentWidthConstraint() {
        // Outside a container there is no block to follow, so the section width stays the only width available.
        let followsContentBlock = (widthMode == .contentBlock && contentBlockWidthConstraint != nil)

        // Drop the old width before putting up the new one, so the two never coexist.
        if followsContentBlock {
            fullWidthConstraint?.isActive = false
            contentBlockWidthConstraint?.isActive = true
        } else {
            contentBlockWidthConstraint?.isActive = false
            fullWidthConstraint?.isActive = true
        }
    }

    // MARK: - Height

    /// Whether this section takes in the surplus height of the pane.
    var isVerticallyFlexible: Bool {
        if case .flexible = heightMode {
            return true
        }
        return false
    }

    /// Lower bound this section keeps while stretching. nil while it follows its content.
    var flexibleMinimumHeight: CGFloat? {
        guard case let .flexible(minimumHeight, _) = heightMode else { return nil }
        return minimumHeight
    }

    private func updateHeightConstraints() {
        minimumHeightConstraint?.isActive = false
        preferredHeightConstraint?.isActive = false
        minimumHeightConstraint = nil
        preferredHeightConstraint = nil

        guard case let .flexible(minimumHeight, preferredHeight) = heightMode else {
            setContentHuggingPriority(.defaultLow, for: .vertical)
            return
        }

        // The stack hands its surplus to the least hugging section.
        setContentHuggingPriority(SettingsLayoutPriority.sectionHeightShrink, for: .vertical)

        let minimum = heightAnchor.constraint(greaterThanOrEqualToConstant: minimumHeight)
        minimum.isActive = true
        minimumHeightConstraint = minimum

        // A lower bound, so the tallest request decides the height the pane opens at.
        let preferred = heightAnchor.constraint(greaterThanOrEqualToConstant: preferredHeight)
        preferred.priority = SettingsLayoutPriority.sectionPreferredHeight
        preferred.isActive = true
        preferredHeightConstraint = preferred
    }

    /// Drop the height request while the pane measures its lower bound.
    func setPreferredHeightActive(_ flag: Bool) {
        preferredHeightConstraint?.isActive = flag
    }

    /// Apply a control size together with the font size that matches it.
    static func applyControlSize(_ controlSize: NSControl.ControlSize, to control: NSControl) {
        control.controlSize = controlSize
        if controlSize == .small {
            control.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        }
    }
}

/// A two-column section made of one trailing-aligned label and any number of
/// leading-aligned items. The label column follows its longest label across
/// every section, and the item column follows whatever its items need.
final class SettingsSeparatorSectionView: SettingsSectionView {
    private(set) var separator: NSBox!

    override init(identifier: NSUserInterfaceItemIdentifier? = nil) {
        super.init(identifier: identifier)

        separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }
}

/// A section placing a single push button in the content box.
final class SettingsButtonSectionView: SettingsSectionView {
    private(set) var button: NSButton!

    init(title: String,
         controlSize: NSControl.ControlSize = .regular,
         alignment: SettingsSectionAlignment = .center,
         identifier: NSUserInterfaceItemIdentifier? = nil,
         target: AnyObject?,
         action: Selector?) {
        super.init(identifier: identifier)

        button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .push
        Self.applyControlSize(controlSize, to: button)
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)

        var constraints = [
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
            button.leadingAnchor.constraint(greaterThanOrEqualTo: contentGuide.leadingAnchor),
            button.trailingAnchor.constraint(lessThanOrEqualTo: contentGuide.trailingAnchor)
        ]

        switch alignment {
        case .leading:
            constraints.append(button.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor))
        case .center:
            constraints.append(button.centerXAnchor.constraint(equalTo: contentGuide.centerXAnchor))
        case .trailing:
            constraints.append(button.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor))
        }

        NSLayoutConstraint.activate(constraints)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }
}

/// A section placing a leading-aligned checkbox in the content box, with an
/// optional wrapping description underneath.
final class SettingsCheckboxSectionView: SettingsSectionView {
    private(set) var checkbox: NSButton!
    private(set) var descriptionLabel: SettingsWrappingLabel?

    init(title: String,
         isOn: Bool = false,
         description: String? = nil,
         identifier: NSUserInterfaceItemIdentifier? = nil,
         target: AnyObject?,
         action: Selector?) {
        super.init(identifier: identifier)

        checkbox = NSButton(checkboxWithTitle: title, target: target, action: action)
        checkbox.state = isOn ? .on : .off
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        addSubview(checkbox)

        var constraints = [
            checkbox.topAnchor.constraint(equalTo: topAnchor),
            checkbox.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor),
            checkbox.trailingAnchor.constraint(lessThanOrEqualTo: contentGuide.trailingAnchor)
        ]

        if let description {
            let label = SettingsWrappingLabel(string: description)
            descriptionLabel = label
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)

            constraints += [
                label.topAnchor.constraint(equalTo: checkbox.bottomAnchor,
                                           constant: SettingsLayoutMetrics.itemSpacing),
                label.leadingAnchor.constraint(equalTo: checkbox.leadingAnchor),
                label.trailingAnchor.constraint(lessThanOrEqualTo: contentGuide.trailingAnchor),
                label.bottomAnchor.constraint(equalTo: bottomAnchor)
            ]
        } else {
            constraints.append(checkbox.bottomAnchor.constraint(equalTo: bottomAnchor))
        }

        NSLayoutConstraint.activate(constraints)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func layout() {
        super.layout()
        descriptionLabel?.availableWidth = contentGuide.frame.width
    }
}
