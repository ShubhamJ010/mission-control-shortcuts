import CoreGraphics
import Foundation

/// Stateful, side-effect-free keyboard session for the Mission Control
/// type-to-select fuzzy finder.
///
/// Owns the typed `query` and the `selectedIndex` into the current
/// `WindowSelectionEngine` matches. `handleKey(keyCode:characters:flags:windows:)`
/// is a pure state machine: it never posts events, touches views, or reads
/// UserDefaults. It returns an `Effect` (`ignore` / `updated` / `clear` /
/// `activate`) so `MissionControlHoverService` can decide whether to swallow
/// the key, update the `SearchBarOverlay` pill, clear the session, or
/// activate the selected thumbnail via synthetic click. Modifier handling,
/// Tab cycling scope, and whitespace filtering are all encapsulated here.
struct WindowSearchSession {
    /// Typed query. Empty means mouse-only mode.
    var query: String = ""
    /// Index into the current `fuzzyMatch` results. `-1` means no selection
    /// (opening Mission Control never moves the pointer).
    var selectedIndex: Int = -1

    enum Effect: Equatable {
        /// Let the key through to the system / other taps.
        case ignore
        /// Query or selection changed; update the search bar and highlight.
        case updated
        /// Enter on a valid selection — activate the matched thumbnail.
        case activate
        /// Escape / backspace-to-empty — hide the search bar, reset index.
        case clear
    }

    private enum KeyCode {
        static let `return`: Int64 = 36
        static let keypadEnter: Int64 = 76
        static let escape: Int64 = 53
        static let delete: Int64 = 51
        static let forwardDelete: Int64 = 117
        static let tab: Int64 = 48
        static let downArrow: Int64 = 125
        static let upArrow: Int64 = 126
    }

    mutating func clear() {
        query = ""
        selectedIndex = -1
    }

    func matches(in windows: [[String: Any]]) -> [WindowSelectionEngine.Match] {
        WindowSelectionEngine.fuzzyMatch(query: query, in: windows)
    }

    /// Modifiers that indicate a global shortcut (Cmd+W/Q/M/H, Cmd+Space) and
    /// must pass through to `EventTapService` rather than being consumed as
    /// typing. Shift is intentionally not blocked so `C` / `Shift+Tab` still
    /// reach the session.
    private static let blockedModifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl]

    mutating func handleKey(
        keyCode: Int64,
        characters: String?,
        flags: CGEventFlags,
        windows: [[String: Any]]
    ) -> Effect {
        // Raw-value mask instead of `intersection(...).isEmpty`: this runs on
        // every keystroke of the HID tap and CGEventFlags (OptionSet) has no
        // allocation-free `isDisjoint(with:)`.
        guard flags.rawValue & Self.blockedModifiers.rawValue == 0 else { return .ignore }

        switch keyCode {
        case KeyCode.return, KeyCode.keypadEnter:
            return selectedIndex >= 0 ? .activate : .ignore

        case KeyCode.escape:
            if query.isEmpty {
                return .ignore
            }
            clear()
            return .clear

        case KeyCode.delete, KeyCode.forwardDelete:
            guard !query.isEmpty else { return .ignore }
            query.removeLast()
            if query.isEmpty {
                selectedIndex = -1
                return .clear
            }
            // Recompute matches once per mutation and reuse the hits to sync
            // `selectedIndex` without a second `fuzzyMatch` scan.
            let hits = matches(in: windows)
            syncSelection(with: hits)
            return .updated

        case KeyCode.tab:
            // Shift+Tab cycles backward (standard accessibility), Tab cycles
            // forward. Tab is the only key allowed to cycle row-major with an
            // empty query so the user can Tab through thumbnails without typing.
            let isShift = flags.contains(.maskShift)
            return cycle(forward: !isShift, in: windows, allowEmptyQuery: true)

        case KeyCode.downArrow:
            return cycle(forward: true, in: windows, allowEmptyQuery: false)

        case KeyCode.upArrow:
            return cycle(forward: false, in: windows, allowEmptyQuery: false)

        default:
            return appendCharacters(characters, windows: windows)
        }
    }

    /// Cycles `selectedIndex` through `hits` with wrap-around. When `query` is
    /// empty only `Tab` ( `allowEmptyQuery == true` ) is permitted to cycle
    /// using `rowMajorSorted` order; arrow keys require an active query and
    /// return `.ignore` until the user types. When a query is active, cycling
    /// is scoped to the current fuzzy matches and the pill stays visible.
    private mutating func cycle(forward: Bool, in windows: [[String: Any]], allowEmptyQuery: Bool = false) -> Effect {
        let hits: [WindowSelectionEngine.Match]
        if query.isEmpty {
            guard allowEmptyQuery else { return .ignore }
            hits = WindowSelectionEngine.rowMajorSorted(in: windows)
            guard !hits.isEmpty else { return .ignore }
        } else {
            hits = matches(in: windows)
            guard !hits.isEmpty else { return .updated }
        }

        if selectedIndex < 0 {
            selectedIndex = 0
        } else if forward {
            selectedIndex = (selectedIndex + 1) % hits.count
        } else {
            selectedIndex = selectedIndex <= 0 ? hits.count - 1 : selectedIndex - 1
        }
        return .updated
    }

    /// Appends typed letters/numbers/whitespace to `query`, ignoring pure
    /// punctuation or symbols. Prevents a leading whitespace-only pill by
    /// rejecting whitespace when `query` is empty, then syncs `selectedIndex`
    /// to the refreshed fuzzy matches.
    private mutating func appendCharacters(_ characters: String?, windows: [[String: Any]]) -> Effect {
        guard let characters, !characters.isEmpty else { return .ignore }
        let filtered = characters.filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
        guard !filtered.isEmpty else { return .ignore }
        if query.isEmpty, filtered.trimmingCharacters(in: .whitespaces).isEmpty {
            return .ignore
        }

        query.append(contentsOf: filtered)
        let hits = matches(in: windows)
        syncSelection(with: hits)
        return .updated
    }

    /// Syncs `selectedIndex` against precomputed `hits` to avoid a second
    /// `fuzzyMatch` scan. Resets to `-1` when there are no hits, or to `0`
    /// when the previous selection is out of bounds (e.g., query narrowed).
    private mutating func syncSelection(with hits: [WindowSelectionEngine.Match]) {
        if hits.isEmpty {
            selectedIndex = -1
        } else if selectedIndex < 0 || selectedIndex >= hits.count {
            selectedIndex = 0
        }
    }
}
