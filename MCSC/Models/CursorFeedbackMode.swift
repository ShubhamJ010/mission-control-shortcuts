import Cocoa

/// Tailored entry animation curves applied to an overlay symbol's layer.
///
/// Lives in the Models layer because `CursorFeedbackMode` declares which
/// curve a feedback type plays; `OverlayAnimator` turns it into keyframes.
enum OverlayAnimationStyle {
    case bouncePop
    case wiggle
    case pulseExpand
    case shrinkDown
    case slideRight
    case slideLeft
}

/// The complete visual treatment of one cursor-feedback mode.
///
/// Every descriptor a mode needs travels together in one value, so a mode is
/// declared exactly once instead of once per property.
struct CursorFeedbackDescriptor {
    /// SF Symbol name rendered by `NSImage(systemSymbolName:)`.
    let symbolName: String

    /// Accessibility description of the action the symbol represents.
    let accessibilityDescription: String

    /// Tint palette painted through the symbol (SF Symbols "palette" /
    /// variable-colour rendering). `nil` keeps the system multicolor
    /// default. Colors map to layers in order: primary → accent → none.
    let paletteColors: [NSColor]?

    /// Entry curve played when the symbol appears.
    let animationStyle: OverlayAnimationStyle

    /// Base outline symbol painted instantly before the morph into the
    /// filled target symbol. `nil` means the symbol appears without a morph.
    let baseSymbol: String?

    /// Optional neutral tint palette used for the base outline symbol before morphing.
    let basePaletteColors: [NSColor]?
}

/// The set of actions the cursor feedback overlay can flash, plus their
/// visual treatment.
///
/// Adding a new feedback type is *data-only*: add a `case` and one entry in
/// `descriptor`. The overlay derives the rendered image and behaviour from
/// that and needs no further changes.
///
/// This descriptor lives in the Models layer because three separate layers
/// consume it: the overlay that renders it (Views), the shared animation
/// engine (`OverlayAnimator`), and the action routers that pick a mode for a
/// gesture (ViewModels).
enum CursorFeedbackMode: CaseIterable, Equatable {
    case close
    case minimize
    case quit
    case hide
    case eject
    case almost
    case reasonable
    case makeSmaller
    case maximize
    case closeTab
    case reopenTab
    case newWindow
    case newTab
    case fullscreen
    case spaceRight
    case spaceLeft
    case unminimizeAll
    case command
    case leftCycleSnap
    case rightCycleSnap

    /// The visual treatment for this mode.
    var descriptor: CursorFeedbackDescriptor {
        switch self {
        case .close:
            CursorFeedbackDescriptor(
                symbolName: "xmark.circle.fill",
                accessibilityDescription: "Close Window",
                paletteColors: nil, // System multicolor (red X).
                animationStyle: .bouncePop,
                baseSymbol: nil,
                basePaletteColors: nil
            )
        case .minimize:
            CursorFeedbackDescriptor(
                symbolName: "minus.circle.fill",
                accessibilityDescription: "Minimize Window",
                paletteColors: [.black, .systemYellow],
                animationStyle: .shrinkDown,
                baseSymbol: "minus.circle",
                // Painted plain white so the pre-morph state reads as neutral.
                basePaletteColors: [.white]
            )
        case .quit:
            CursorFeedbackDescriptor(
                symbolName: "xmark.circle.fill",
                accessibilityDescription: "Force Quit",
                paletteColors: [.white, .systemPurple],
                animationStyle: .bouncePop,
                baseSymbol: nil,
                basePaletteColors: nil
            )
        case .hide:
            CursorFeedbackDescriptor(
                symbolName: "eye.slash.circle.fill",
                accessibilityDescription: "Hide Application",
                paletteColors: [.black, .systemYellow],
                animationStyle: .shrinkDown,
                baseSymbol: "eye.slash.circle",
                // Painted plain white so the pre-morph state reads as neutral.
                basePaletteColors: [.white]
            )
        case .eject:
            CursorFeedbackDescriptor(
                symbolName: "eject.circle.fill",
                accessibilityDescription: "Eject Volume",
                paletteColors: [.white, .systemRed],
                animationStyle: .bouncePop,
                baseSymbol: "eject.circle",
                basePaletteColors: nil
            )
        case .almost:
            CursorFeedbackDescriptor(
                symbolName: "inset.filled.rectangle",
                accessibilityDescription: "Almost Maximize Window",
                paletteColors: [.controlAccentColor],
                animationStyle: .pulseExpand,
                baseSymbol: "rectangle",
                basePaletteColors: nil
            )
        case .reasonable:
            CursorFeedbackDescriptor(
                symbolName: "inset.filled.center.rectangle",
                accessibilityDescription: "Small and Center",
                paletteColors: [.controlAccentColor],
                animationStyle: .pulseExpand,
                baseSymbol: "rectangle",
                basePaletteColors: nil
            )
        case .makeSmaller:
            CursorFeedbackDescriptor(
                symbolName: "arrow.up.right.and.arrow.down.left.rectangle",
                accessibilityDescription: "Make Smaller Window",
                paletteColors: [.controlAccentColor],
                animationStyle: .shrinkDown,
                baseSymbol: nil,
                basePaletteColors: nil
            )
        case .maximize:
            CursorFeedbackDescriptor(
                symbolName: "rectangle.fill",
                accessibilityDescription: "Maximize Window",
                paletteColors: [.controlAccentColor],
                animationStyle: .pulseExpand,
                baseSymbol: "rectangle",
                basePaletteColors: nil
            )
        case .closeTab:
            CursorFeedbackDescriptor(
                symbolName: "xmark.rectangle.fill",
                accessibilityDescription: "Close Tab",
                paletteColors: nil, // System multicolor (red X).
                animationStyle: .wiggle,
                baseSymbol: nil,
                basePaletteColors: nil
            )
        case .reopenTab:
            CursorFeedbackDescriptor(
                symbolName: "plus.rectangle.fill",
                accessibilityDescription: "Reopen Tab",
                // Black rectangle body + green plus, both at 100%
                // (palette layer 1: black, layer 2: green).
                paletteColors: [.black, .systemGreen],
                animationStyle: .wiggle,
                baseSymbol: nil,
                basePaletteColors: nil
            )
        case .newWindow:
            CursorFeedbackDescriptor(
                symbolName: "macwindow.badge.plus",
                accessibilityDescription: "New Window",
                // Green window, white badge, black plus — badge is layer 1,
                // window layer 2 for macwindow.badge.plus.
                paletteColors: [.white, .systemGreen, .black],
                animationStyle: .bouncePop,
                baseSymbol: nil,
                basePaletteColors: nil
            )
        case .newTab:
            CursorFeedbackDescriptor(
                symbolName: "plus.rectangle.fill.on.rectangle.fill",
                accessibilityDescription: "New Tab",
                // Primary (black) rectangles + green plus at 100% — matches
                // reopenTab/newWindow/fullscreen palette.
                paletteColors: [.black, .systemGreen],
                animationStyle: .wiggle,
                baseSymbol: "plus.rectangle.on.rectangle",
                basePaletteColors: nil
            )
        case .fullscreen:
            CursorFeedbackDescriptor(
                symbolName: "arrow.down.left.and.arrow.up.right.circle.fill",
                accessibilityDescription: "Toggle Fullscreen",
                paletteColors: [.black, .systemGreen],
                animationStyle: .pulseExpand,
                baseSymbol: nil,
                basePaletteColors: nil
            )
        case .spaceRight:
            CursorFeedbackDescriptor(
                symbolName: "arrow.right.circle.fill",
                accessibilityDescription: "Move Window to Next Desktop",
                // Primary 100% + Accent 100% (two-layer palette for circle.fill).
                paletteColors: [.white, .controlAccentColor],
                animationStyle: .slideRight,
                baseSymbol: "arrow.right.circle",
                basePaletteColors: nil
            )
        case .spaceLeft:
            CursorFeedbackDescriptor(
                symbolName: "arrow.left.circle.fill",
                accessibilityDescription: "Move Window to Previous Desktop",
                // Primary 100% + Accent 100% (two-layer palette for circle.fill).
                paletteColors: [.white, .controlAccentColor],
                animationStyle: .slideLeft,
                baseSymbol: "arrow.left.circle",
                basePaletteColors: nil
            )
        case .unminimizeAll:
            CursorFeedbackDescriptor(
                symbolName: "arrow.up.square.fill",
                accessibilityDescription: "Unminimize",
                // Black glyph on yellow square, matching Minimize's palette.
                paletteColors: [.black, .systemYellow],
                animationStyle: .pulseExpand,
                baseSymbol: "arrow.up.square",
                basePaletteColors: nil
            )
        case .command:
            CursorFeedbackDescriptor(
                symbolName: "command.circle.fill",
                accessibilityDescription: "Command Modifier",
                // White glyph on accent circle.fill.
                paletteColors: [.white, .controlAccentColor],
                animationStyle: .pulseExpand,
                baseSymbol: "command.circle",
                basePaletteColors: nil
            )
        case .leftCycleSnap:
            CursorFeedbackDescriptor(
                symbolName: "rectangle.lefthalf.inset.filled.arrow.left",
                accessibilityDescription: "Left Cycle Snap",
                paletteColors: [.controlAccentColor],
                animationStyle: .pulseExpand,
                baseSymbol: "rectangle",
                basePaletteColors: nil
            )
        case .rightCycleSnap:
            CursorFeedbackDescriptor(
                symbolName: "rectangle.righthalf.inset.filled.arrow.right",
                accessibilityDescription: "Right Cycle Snap",
                paletteColors: [.controlAccentColor],
                animationStyle: .pulseExpand,
                baseSymbol: "rectangle",
                basePaletteColors: nil
            )
        }
    }

    /// SF Symbol name rendered by `NSImage(systemSymbolName:)`.
    var symbolName: String {
        descriptor.symbolName
    }

    /// Accessibility description of the action the symbol represents.
    var accessibilityDescription: String {
        descriptor.accessibilityDescription
    }

    /// Tint palette painted through the symbol.
    var paletteColors: [NSColor]? {
        descriptor.paletteColors
    }

    /// Entry curve played when the symbol appears.
    var animationStyle: OverlayAnimationStyle {
        descriptor.animationStyle
    }

    /// Base outline symbol painted instantly before the morph into the filled target symbol.
    var baseSymbol: String? {
        descriptor.baseSymbol
    }

    /// Optional neutral tint palette used for the base outline symbol before morphing.
    var basePaletteColors: [NSColor]? {
        descriptor.basePaletteColors
    }
}
