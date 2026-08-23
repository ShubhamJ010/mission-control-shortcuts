import Cocoa

/// Two-column settings section: item column on the leading edge and an
/// optional detail column, with a shared content-width constraint.
final class SettingsColumnSectionView: SettingsSectionView {
    private(set) var titleLabel: NSTextField!

    /// Width this section asks of the item column. Caps and floors it alike,
    /// so the column settles there. nil follows the items instead.
    var itemColumnMaximumWidth: CGFloat? {
        didSet {
            updateItemColumnMaximumWidthConstraint()
            layoutView?.invalidateItemColumnDeclaredWidth()
        }
    }

    /// Box of the label column. Its width comes from the container guide.
    private let labelBoxGuide = NSLayoutGuide()
    /// Box of the item column. It sits on the trailing side of the label column.
    private let itemBoxGuide = NSLayoutGuide()

    private unowned let labelColumnWidthGuide: NSLayoutGuide
    private unowned let itemColumnWidthGuide: NSLayoutGuide

    private var items = [NSView]()
    private var bottomConstraint: NSLayoutConstraint?
    private var itemColumnMaximumWidthConstraint: NSLayoutConstraint?
    /// Constraints that let the label decide the height while no item has been added yet.
    private var labelOnlyVerticalConstraints = [NSLayoutConstraint]()

    init(labelTitle: String,
         labelColumnWidthGuide: NSLayoutGuide,
         itemColumnWidthGuide: NSLayoutGuide,
         itemColumnMaximumWidth: CGFloat? = nil,
         identifier: NSUserInterfaceItemIdentifier? = nil) {
        self.labelColumnWidthGuide = labelColumnWidthGuide
        self.itemColumnWidthGuide = itemColumnWidthGuide
        self.itemColumnMaximumWidth = itemColumnMaximumWidth
        super.init(identifier: identifier)

        setUpGuides()
        setUpTitleLabel(labelTitle)
        updateItemColumnMaximumWidthConstraint()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    private func setUpGuides() {
        [labelBoxGuide, itemBoxGuide].forEach { addLayoutGuide($0) }

        // The two columns fill the content box exactly, so centering and width are left to the base class.
        NSLayoutConstraint.activate([
            labelBoxGuide.topAnchor.constraint(equalTo: topAnchor),
            labelBoxGuide.bottomAnchor.constraint(equalTo: bottomAnchor),
            labelBoxGuide.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor),
            itemBoxGuide.topAnchor.constraint(equalTo: topAnchor),
            itemBoxGuide.bottomAnchor.constraint(equalTo: bottomAnchor),
            itemBoxGuide.leadingAnchor.constraint(equalTo: labelBoxGuide.trailingAnchor,
                                                  constant: SettingsLayoutMetrics.columnSpacing),
            itemBoxGuide.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor)
        ])
    }

    /// The container shares the item column width guide across every section,
    /// so the narrowest declaration wins for the whole layout.
    private func updateItemColumnMaximumWidthConstraint() {
        itemColumnMaximumWidthConstraint?.isActive = false
        itemColumnMaximumWidthConstraint = nil

        guard let itemColumnMaximumWidth else { return }

        let constraint = itemColumnWidthGuide.widthAnchor.constraint(lessThanOrEqualToConstant: itemColumnMaximumWidth)
        constraint.priority = SettingsLayoutPriority.itemColumnDeclaredWidth
        constraint.isActive = true
        itemColumnMaximumWidthConstraint = constraint
    }

    private func setUpTitleLabel(_ title: String) {
        titleLabel = NSTextField(labelWithString: "\(title):")
        titleLabel.alignment = .right
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize)

        // Left in wrapping mode the label gains no intrinsic width and the column collapses to zero.
        titleLabel.usesSingleLineMode = true
        // Truncating in the middle keeps the trailing colon, so a shortened label still reads as a label.
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.cell?.isScrollable = false
        // Recovers a truncated label on hover, so a narrow pane never hides the wording outright.
        titleLabel.allowsExpansionToolTips = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.trailingAnchor.constraint(equalTo: labelBoxGuide.trailingAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: labelBoxGuide.leadingAnchor),
            titleLabel.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])

        labelOnlyVerticalConstraints = [
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ]
        NSLayoutConstraint.activate(labelOnlyVerticalConstraints)
    }

    /// Activate the constraints crossing into the container column width
    /// guides. Call after joining the view hierarchy.
    func activateColumnWidthConstraints() {
        NSLayoutConstraint.activate([
            labelBoxGuide.widthAnchor.constraint(equalTo: labelColumnWidthGuide.widthAnchor),
            itemBoxGuide.widthAnchor.constraint(equalTo: itemColumnWidthGuide.widthAnchor),
            labelColumnWidthGuide.widthAnchor.constraint(greaterThanOrEqualTo: titleLabel.widthAnchor)
        ])
    }

    // MARK: - Adding items

    @discardableResult
    func addCheckbox(title: String, isOn: Bool = false, target: AnyObject?, action: Selector?) -> NSButton {
        let checkbox = NSButton(checkboxWithTitle: title, target: target, action: action)
        checkbox.state = isOn ? .on : .off
        appendItem(checkbox, verticalAlignment: .firstBaseline, contributesToColumnWidth: true)
        return checkbox
    }

    /// Supplementary description label; takes no part in deciding the column width.
    @discardableResult
    func addDescriptionLabel(_ string: String) -> SettingsWrappingLabel {
        let label = SettingsWrappingLabel(string: string)
        appendItem(label, verticalAlignment: .firstBaseline, contributesToColumnWidth: false)
        return label
    }

    @discardableResult
    func addButton(title: String,
                   controlSize: NSControl.ControlSize = .regular,
                   target: AnyObject?,
                   action: Selector?) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .push
        Self.applyControlSize(controlSize, to: button)
        appendItem(button, verticalAlignment: .firstBaseline, contributesToColumnWidth: true)
        return button
    }

    /// Pop-up button — mirrors DemoViewControllers.addPopUpButton usage.
    @discardableResult
    func addPopUpButton(controlSize: NSControl.ControlSize = .regular,
                        target: AnyObject?,
                        action: Selector?) -> NSPopUpButton {
        let popUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
        popUpButton.target = target
        popUpButton.action = action
        Self.applyControlSize(controlSize, to: popUpButton)
        appendItem(popUpButton, verticalAlignment: .firstBaseline, contributesToColumnWidth: true)
        return popUpButton
    }

    /// Arbitrary view.
    func addCustomView(_ view: NSView, verticalAlignment: SettingsItemVerticalAlignment = .firstBaseline) {
        appendItem(view, verticalAlignment: verticalAlignment, contributesToColumnWidth: true)
    }

    /// Attach an accessory view next to a previously added item — e.g. checkbox trailing a pop-up.
    /// Follows upstream SettingsColumnSectionView.addAccessoryView semantics.
    @discardableResult
    func addAccessoryView(_ accessoryView: NSView,
                          to item: NSView,
                          spacing: CGFloat = SettingsLayoutMetrics.columnSpacing) -> NSView {
        accessoryView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(accessoryView)

        let pairGuide = NSLayoutGuide()
        addLayoutGuide(pairGuide)

        NSLayoutConstraint.activate([
            accessoryView.centerYAnchor.constraint(equalTo: item.centerYAnchor),
            accessoryView.leadingAnchor.constraint(equalTo: item.trailingAnchor, constant: spacing),
            accessoryView.trailingAnchor.constraint(lessThanOrEqualTo: itemBoxGuide.trailingAnchor),
            accessoryView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            accessoryView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),

            pairGuide.leadingAnchor.constraint(equalTo: item.leadingAnchor),
            pairGuide.trailingAnchor.constraint(equalTo: accessoryView.trailingAnchor),
            pairGuide.topAnchor.constraint(equalTo: topAnchor),
            pairGuide.heightAnchor.constraint(equalToConstant: 0),
            itemColumnWidthGuide.widthAnchor.constraint(greaterThanOrEqualTo: pairGuide.widthAnchor)
        ])

        return accessoryView
    }

    private func appendItem(_ item: NSView,
                            verticalAlignment: SettingsItemVerticalAlignment,
                            contributesToColumnWidth: Bool) {
        let previousItem = items.last

        item.translatesAutoresizingMaskIntoConstraints = false
        addSubview(item)

        var constraints = [item.leadingAnchor.constraint(equalTo: itemBoxGuide.leadingAnchor)]

        if contributesToColumnWidth {
            constraints.append(item.trailingAnchor.constraint(lessThanOrEqualTo: itemBoxGuide.trailingAnchor))
            constraints.append(itemColumnWidthGuide.widthAnchor.constraint(greaterThanOrEqualTo: item.widthAnchor))
        } else {
            // The wrapping width arrives through `availableWidth`, so the box only needs to stay inside the column.
            constraints.append(item.trailingAnchor.constraint(lessThanOrEqualTo: itemBoxGuide.trailingAnchor))

            // Asking with the box width would be circular, because that width is what this demand decides.
            // Round up, or integralizing the box can land a point short of the text and wrap it needlessly.
            if let label = item as? SettingsWrappingLabel {
                let demand = itemColumnWidthGuide.widthAnchor
                    .constraint(greaterThanOrEqualToConstant: label.naturalTextWidth.rounded(.up))
                demand.priority = SettingsLayoutPriority.descriptionWidthDemand
                constraints.append(demand)
            }
        }

        if let previousItem {
            constraints.append(item.topAnchor.constraint(equalTo: previousItem.bottomAnchor,
                                                         constant: SettingsLayoutMetrics.itemSpacing))
        } else {
            constraints.append(item.topAnchor.constraint(equalTo: topAnchor))
        }

        NSLayoutConstraint.activate(constraints)

        if previousItem == nil {
            NSLayoutConstraint.deactivate(labelOnlyVerticalConstraints)
            switch verticalAlignment {
            case .firstBaseline:
                titleLabel.firstBaselineAnchor.constraint(equalTo: item.firstBaselineAnchor).isActive = true
            case .top:
                titleLabel.topAnchor.constraint(equalTo: item.topAnchor).isActive = true
            case .centerY:
                titleLabel.centerYAnchor.constraint(equalTo: item.centerYAnchor).isActive = true
            }
        }

        bottomConstraint?.isActive = false
        bottomConstraint = bottomAnchor.constraint(equalTo: item.bottomAnchor)
        bottomConstraint?.isActive = true

        items.append(item)
    }

    override func layout() {
        super.layout()
        let itemColumnWidth = itemBoxGuide.frame.width
        items.forEach { ($0 as? SettingsWrappingLabel)?.availableWidth = itemColumnWidth }
    }
}

/// Horizontal placement of a control inside the section content box.
enum SettingsSectionAlignment {
    case leading
    case center
    case trailing
}

// A separator spanning the whole container.
