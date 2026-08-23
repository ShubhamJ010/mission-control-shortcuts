import ApplicationServices
import Cocoa

/// Keyboard fuzzy-finder (type-to-select) for `MissionControlHoverService`:
/// a dedicated HID key tap installed only while Mission Control is open,
/// feeding `WindowSearchSession` / `WindowSelectionEngine`. Split from the
/// main file to stay under the SwiftLint `file_length` budget.
@MainActor
extension MissionControlHoverService {
    // MARK: - Keyboard Fuzzy-Finder (type-to-select)

    /// Resets the session and installs a fresh `MCKeyboardTapService` for the
    /// current Mission Control appearance. The HID tap is gated by the single
    /// "Keyboard Navigation" toggle in `ShortcutConfiguration` and is not
    /// created at all when the toggle is off, so keystrokes pass through.
    func startKeyboardSession() {
        searchSession.clear()
        queryIdleTimer?.invalidate()
        queryIdleTimer = nil
        searchOverlay?.hide()
        currentMatches = []

        guard isKeyboardNavigationEnabledProvider() else { return }
        guard keyboardTap == nil else { return }

        let tap = MCKeyboardTapService()
        tap.onKeyDown = { [weak self] keyCode, characters, flags in
            guard let self else { return false }
            return self.handleKeyDown(keyCode: keyCode, characters: characters, flags: flags)
        }
        tap.start()
        keyboardTap = tap
    }

    /// Tears down the HID tap and clears the query / pill / idle timer /
    /// match cache. Called on `AXExposeExit`, `stop()`, and before each new
    /// session.
    func stopKeyboardSession() {
        keyboardTap?.stop()
        keyboardTap = nil
        clearSearch()
    }

    /// Handles a raw `keyDown` from the HID tap while Mission Control is open.
    /// All Tab / Return / typing navigation is gated by the single "Keyboard
    /// Navigation" toggle. Returns `true` to swallow the event (handled) or
    /// `false` to let it pass through to the system.
    private func handleKeyDown(keyCode: Int64, characters: String?, flags: CGEventFlags) -> Bool {
        guard isTracking else { return false }
        guard isKeyboardNavigationEnabledProvider() else { return false }

        let effect = searchSession.handleKey(
            keyCode: keyCode,
            characters: characters,
            flags: flags,
            windows: windows
        )

        switch effect {
        case .ignore:
            return false
        case .updated:
            updateSearchUI()
            resetIdleTimer()
            return true
        case .clear:
            clearSearch()
            return true
        case .activate:
            activateSelectedWindow()
            return true
        }
    }

    /// Updates the pill visibility and drives the native Mission Control highlight.
    /// Shows the pill only while `query` is non-empty; row-major Tab cycling
    /// with an empty query highlights without a pill. Computes matches once
    /// per keystroke and caches them in `currentMatches` for `activateSelectedWindow()`.
    /// When `query` is empty Tab uses `rowMajorSorted` (top-to-bottom, left-to-
    /// right with 40 pt row tolerance); otherwise uses `fuzzyMatch` ranking
    /// (prefix beats substring). Posts a synthetic `mouseMoved` at the
    /// top-left shoulder point so AppKit paints the native blue highlight and
    /// syncs `hoveredWindow` for Cmd+W/Q/M shortcuts.
    private func updateSearchUI() {
        if searchSession.query.isEmpty {
            searchOverlay?.hide()
        } else {
            if searchOverlay == nil {
                searchOverlay = SearchBarOverlay()
            }
            searchOverlay?.show(query: searchSession.query)
        }

        currentMatches = searchSession.query.isEmpty
            ? WindowSelectionEngine.rowMajorSorted(in: windows)
            : searchSession.matches(in: windows)

        if searchSession.selectedIndex >= 0, searchSession.selectedIndex < currentMatches.count {
            WindowActivationAction.postSyntheticMouseMoved(
                to: currentMatches[searchSession.selectedIndex].shoulderPoint
            )
        }
    }

    /// Activates the currently selected thumbnail. Reuses `currentMatches` from
    /// the last `updateSearchUI()` to avoid a second match computation on the
    /// same keystroke; recomputes only if the cache was cleared (e.g., by
    /// `clearSearch()` or a stale window poll). Plays haptics, clears the
    /// session/pill, then injects `mouseMoved` → `leftMouseDown` → 50 ms dwell
    /// → `leftMouseUp` at `.cghidEventTap` to reliably activate the Exposé
    /// thumbnail.
    private func activateSelectedWindow() {
        let matches: [WindowSelectionEngine.Match]
        if currentMatches.isEmpty {
            matches = searchSession.query.isEmpty
                ? WindowSelectionEngine.rowMajorSorted(in: windows)
                : searchSession.matches(in: windows)
            currentMatches = matches
        } else {
            matches = currentMatches
        }
        let index = searchSession.selectedIndex
        guard index >= 0, index < matches.count else { return }

        let match = matches[index]
        HapticService.perform(.pinchIn)
        clearSearch()
        WindowActivationAction.performSyntheticClick(at: match.shoulderPoint)
    }

    /// Resets query / selection / pill / idle timer / match cache. Called on
    /// Escape, backspace-to-empty, activation, session teardown, and window-
    /// list invalidation.
    private func clearSearch() {
        searchSession.clear()
        currentMatches = []
        queryIdleTimer?.invalidate()
        queryIdleTimer = nil
        searchOverlay?.hide()
    }

    /// Arms or suppresses the 2 s idle auto-clear timer. When the "Keyboard
    /// Navigation" toggle is on (`isKeyboardNavigationEnabledProvider() == true`)
    /// the session is intentionally persistent until `Return` (activate) or
    /// `Escape` (clear) so Tab cycling keeps the pill visible without a
    /// timeout. When the toggle is off, the timer fires on the main run loop
    /// in `.common` modes with 0.2 s tolerance and clears the session.
    private func resetIdleTimer() {
        queryIdleTimer?.invalidate()
        queryIdleTimer = nil
        guard !isKeyboardNavigationEnabledProvider() else { return }
        queryIdleTimer = Timer.scheduledCommon(
            interval: HoverServiceTiming.queryIdle,
            repeats: false,
            tolerance: HoverServiceTiming.queryIdleTolerance
        ) { [weak self] _ in
            Task { @MainActor in self?.clearSearch() }
        }
    }
}
