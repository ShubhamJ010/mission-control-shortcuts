import Cocoa

/// Container that builds a settings pane out of sections.
///
/// Column widths come from the content: the label column follows its longest
/// label across every section, the item column follows whatever its items
/// need (including the width a description wants before it wraps), and the
/// leftover space becomes equal margins so the block stays centered. This
/// view owns the section spacing. Ported from usagimaru/MacAppSettingsUI.
final class SettingsLayoutView: NSView {
    /// Guide aggregating the label column width (no position, shared width only).
    private let labelColumnWidthGuide = NSLayoutGuide()
    /// Guide aggregating the item column width.
    private let itemColumnWidthGuide = NSLayoutGuide()
    /// Guide aggregating the width of both columns plus the spacing; every
    /// content-block section matches it, so their edges line up.
    private let contentBlockWidthGuide = NSLayoutGuide()

    private let stackView = NSStackView()
    /// Stands in for the item column next to the label column, so the block
    /// width can be read off its trailing edge.
    private let itemColumnMeasuringGuide = NSLayoutGuide()

    private var itemColumnShrinkConstraint: NSLayoutConstraint?
    /// Holds the narrowest width the sections declared. Inactive while no section declares one.
    private var itemColumnDeclaredWidthConstraint: NSLayoutConstraint?
    /// Pulls the stack down to the pane bottom. Inactive while no section takes in surplus height.
    private var stackFillConstraint: NSLayoutConstraint?
    /// Ties the stretching sections to one another. Rebuilt whenever the set of them changes.
    private var flexibleSectionLinkConstraints = [NSLayoutConstraint]()

    init() {
        super.init(frame: .zero)
        setUpGuides()
        setUpStackView()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    /// Lay this view into a pane view with system standard spacing on all edges.
    func install(in parentView: NSView) {
        translatesAutoresizingMaskIntoConstraints = false
        parentView.addSubview(self, positioned: .below, relativeTo: nil)

        NSLayoutConstraint.activate([
            topAnchor.constraint(equalToSystemSpacingBelow: parentView.topAnchor, multiplier: 1),
            leadingAnchor.constraint(equalToSystemSpacingAfter: parentView.leadingAnchor, multiplier: 1),
            parentView.trailingAnchor.constraint(equalToSystemSpacingAfter: trailingAnchor, multiplier: 1),
            parentView.bottomAnchor.constraint(equalToSystemSpacingBelow: bottomAnchor, multiplier: 1)
        ])
    }

    private func setUpGuides() {
        for guide in [labelColumnWidthGuide, itemColumnWidthGuide] {
            addLayoutGuide(guide)
            // Only the width matters, but an undefined position counts as
            // ambiguous, so pin the guide to the origin.
            NSLayoutConstraint.activate([
                guide.leadingAnchor.constraint(equalTo: leadingAnchor),
                guide.topAnchor.constraint(equalTo: topAnchor),
                guide.heightAnchor.constraint(equalToConstant: 0)
            ])
        }

        let labelColumnShrink = labelColumnWidthGuide.widthAnchor.constraint(equalToConstant: 0)
        labelColumnShrink.priority = SettingsLayoutPriority.labelColumnWidthShrink
        labelColumnShrink.isActive = true

        // Held back until a column section exists, or a pane of full-width
        // sections alone would collapse to the minimum.
        itemColumnShrinkConstraint = itemColumnWidthGuide.widthAnchor.constraint(equalToConstant: 0)
        itemColumnShrinkConstraint?.priority = SettingsLayoutPriority.itemColumnWidthShrink

        // A declaration only caps the column, so the same value comes back as
        // a lower bound and the column stops hugging narrower.
        itemColumnDeclaredWidthConstraint = itemColumnWidthGuide.widthAnchor.constraint(greaterThanOrEqualToConstant: 0)
        itemColumnDeclaredWidthConstraint?.priority = SettingsLayoutPriority.itemColumnDeclaredWidth

        [itemColumnMeasuringGuide, contentBlockWidthGuide].forEach { addLayoutGuide($0) }

        // Anchors cannot be summed, so lay a stand-in guide after the label
        // column and read the total off its trailing edge.
        NSLayoutConstraint.activate([
            itemColumnMeasuringGuide.topAnchor.constraint(equalTo: topAnchor),
            itemColumnMeasuringGuide.heightAnchor.constraint(equalToConstant: 0),
            itemColumnMeasuringGuide.leadingAnchor.constraint(equalTo: labelColumnWidthGuide.trailingAnchor,
                                                              constant: SettingsLayoutMetrics.columnSpacing),
            itemColumnMeasuringGuide.widthAnchor.constraint(equalTo: itemColumnWidthGuide.widthAnchor),

            contentBlockWidthGuide.topAnchor.constraint(equalTo: topAnchor),
            contentBlockWidthGuide.heightAnchor.constraint(equalToConstant: 0),
            contentBlockWidthGuide.leadingAnchor.constraint(equalTo: labelColumnWidthGuide.leadingAnchor),
            contentBlockWidthGuide.trailingAnchor.constraint(equalTo: itemColumnMeasuringGuide.trailingAnchor)
        ])

        // The single force that fills the container; keeping it here stops
        // separators and other sections from voting on the width.
        let blockGrow = contentBlockWidthGuide.trailingAnchor.constraint(equalTo: trailingAnchor)
        blockGrow.priority = SettingsLayoutPriority.contentWidthGrow
        blockGrow.isActive = true
    }

    private func setUpStackView() {
        stackView.orientation = .vertical
        stackView.spacing = SettingsLayoutMetrics.sectionSpacing
        stackView.alignment = .width
        stackView.distribution = .fill
        stackView.detachesHiddenViews = true
        stackView.setHuggingPriority(.defaultLow, for: .horizontal)
        // Tying the bottom with an equality would spread the slack into the
        // sections and stretch the controls vertically, so it stays an
        // inequality; a fill constraint takes over only when a section asks
        // for the surplus height.
        stackView.setHuggingPriority(.required, for: .vertical)

        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])

        // Held back until a section asks for the surplus.
        stackFillConstraint = stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        stackFillConstraint?.priority = SettingsLayoutPriority.contentHeightGrow
    }

    // MARK: - Adding sections

    /// Add a two-column label–item section. `itemColumnMaximumWidth` applies
    /// to the item column of every section in this container.
    @discardableResult
    func addColumnSection(label: String,
                          itemColumnMaximumWidth: CGFloat? = nil,
                          heightMode: SettingsSectionHeightMode = .fitsContent,
                          identifier: NSUserInterfaceItemIdentifier? = nil) -> SettingsColumnSectionView {
        let section = SettingsColumnSectionView(labelTitle: label,
                                                labelColumnWidthGuide: labelColumnWidthGuide,
                                                itemColumnWidthGuide: itemColumnWidthGuide,
                                                itemColumnMaximumWidth: itemColumnMaximumWidth,
                                                identifier: identifier)
        appendSection(section, heightMode: heightMode)
        section.activateColumnWidthConstraints()
        itemColumnShrinkConstraint?.isActive = true
        invalidateItemColumnDeclaredWidth()
        return section
    }

    /// Add a separator section spanning the whole pane.
    @discardableResult
    func addSeparatorSection(identifier: NSUserInterfaceItemIdentifier? = nil) -> SettingsSeparatorSectionView {
        let section = SettingsSeparatorSectionView(identifier: identifier)
        appendSection(section, widthMode: .fullWidth)
        return section
    }

    /// Add a section placing a single button.
    @discardableResult
    func addButtonSection(title: String,
                          controlSize: NSControl.ControlSize = .regular,
                          alignment: SettingsSectionAlignment = .center,
                          widthMode: SettingsSectionWidthMode = .fullWidth,
                          identifier: NSUserInterfaceItemIdentifier? = nil,
                          target: AnyObject?,
                          action: Selector?) -> SettingsButtonSectionView {
        let section = SettingsButtonSectionView(title: title,
                                                controlSize: controlSize,
                                                alignment: alignment,
                                                identifier: identifier,
                                                target: target,
                                                action: action)
        appendSection(section, widthMode: widthMode)
        return section
    }

    /// Add a section placing a leading-aligned checkbox with an optional description.
    @discardableResult
    func addCheckboxSection(title: String,
                            isOn: Bool = false,
                            description: String? = nil,
                            widthMode: SettingsSectionWidthMode = .fullWidth,
                            identifier: NSUserInterfaceItemIdentifier? = nil,
                            target: AnyObject?,
                            action: Selector?) -> SettingsCheckboxSectionView {
        let section = SettingsCheckboxSectionView(title: title,
                                                  isOn: isOn,
                                                  description: description,
                                                  identifier: identifier,
                                                  target: target,
                                                  action: action)
        appendSection(section, widthMode: widthMode)
        return section
    }

    /// Add an arbitrary view as a section.
    @discardableResult
    func addCustomSection(_ view: NSView,
                          widthMode: SettingsSectionWidthMode = .fullWidth,
                          heightMode: SettingsSectionHeightMode = .fitsContent,
                          identifier: NSUserInterfaceItemIdentifier? = nil) -> SettingsSectionView {
        view.translatesAutoresizingMaskIntoConstraints = false
        let section = SettingsSectionView(identifier: identifier)
        section.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: section.topAnchor),
            view.bottomAnchor.constraint(equalTo: section.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: section.contentGuide.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: section.contentGuide.trailingAnchor)
        ])
        appendSection(section, widthMode: widthMode, heightMode: heightMode)
        return section
    }

    private func appendSection(_ section: SettingsSectionView,
                               widthMode: SettingsSectionWidthMode = .contentBlock,
                               heightMode: SettingsSectionHeightMode = .fitsContent) {
        stackView.addArrangedSubview(section)
        // Assigned before the modes, so a height change reaches this container.
        section.layoutView = self
        section.adoptContentWidth(from: contentBlockWidthGuide)
        section.widthMode = widthMode
        section.heightMode = heightMode
    }

    // MARK: - Section height

    /// Rebuild the vertical setup after a section changed its height mode.
    func invalidateFlexibleSections() {
        NSLayoutConstraint.deactivate(flexibleSectionLinkConstraints)
        flexibleSectionLinkConstraints.removeAll()

        let flexibleSections = sections.filter(\.isVerticallyFlexible)

        // No section takes in the surplus, so the pane keeps stacking upward.
        guard let firstSection = flexibleSections.first else {
            stackView.setHuggingPriority(.required, for: .vertical)
            stackFillConstraint?.isActive = false
            return
        }

        stackView.setHuggingPriority(.defaultLow, for: .vertical)
        stackFillConstraint?.isActive = true

        // Sharing the surplus rather than the height keeps each lower bound independent.
        let firstMinimumHeight = firstSection.flexibleMinimumHeight ?? 0
        flexibleSectionLinkConstraints = flexibleSections.dropFirst().map { section in
            section.heightAnchor.constraint(equalTo: firstSection.heightAnchor,
                                            constant: (section.flexibleMinimumHeight ?? 0) - firstMinimumHeight)
        }
        NSLayoutConstraint.activate(flexibleSectionLinkConstraints)
    }

    /// Drop the height requests while the pane measures its lower bound.
    func setPreferredSectionHeightsActive(_ flag: Bool) {
        sections.forEach { $0.setPreferredHeightActive(flag) }
    }

    // MARK: - Item column width

    /// Take in the widths the sections declared. Only the narrowest one
    /// satisfies every declaration at once, so that becomes the column width.
    func invalidateItemColumnDeclaredWidth() {
        guard let narrowestDeclaredWidth = columnSections.compactMap(\.itemColumnMaximumWidth).min() else {
            itemColumnDeclaredWidthConstraint?.isActive = false
            return
        }

        itemColumnDeclaredWidthConstraint?.constant = narrowestDeclaredWidth
        itemColumnDeclaredWidthConstraint?.isActive = true
    }

    // MARK: - Handling sections

    /// The sections already added, in order. Separators and buttons are included.
    var sections: [SettingsSectionView] {
        stackView.arrangedSubviews.compactMap { $0 as? SettingsSectionView }
    }

    /// Only the two-column sections, in order.
    var columnSections: [SettingsColumnSectionView] {
        sections.compactMap { $0 as? SettingsColumnSectionView }
    }
}
