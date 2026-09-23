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
        clearSearch()

        guard isKeyboardNavigationEnabledProvider() else { return }
        guard keyboardTap == nil else { return }

        debugLog("startKeyboardSession: installing MCKeyboardTapService", category: AppLogger.missionControl)
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
        debugLog("stopKeyboardSession: tearing down MCKeyboardTapService", category: AppLogger.missionControl)
        keyboardTap?.stop()
        keyboardTap = nil
        clearSearch()
    }

    /// Handles a raw `keyDown` from the HID tap while Mission Control is open.
    /// Returns `true` to swallow the event (handled) or `false` to let it
    /// pass through to the system.
    func handleKeyDown(keyCode: Int64, characters: String?, flags: CGEventFlags) -> Bool {
        guard isTracking else { return false }

        debugLog("handleKeyDown: keyCode=\(keyCode), char=\(characters ?? "nil"), flags=\(flags.rawValue)", category: AppLogger.eventTap)

        // Exit keys: F3 (99), Apple hardware MC key (160), Ctrl+Up (126 with control), Escape (53 with empty search
        // query).
        let isCtrlUp = (keyCode == 126 && flags.contains(.maskControl))
        let isF3OrMCKey = (keyCode == 99 || keyCode == 160)
        let isEscapeEmptyQuery = (keyCode == 53 && searchSession.query.isEmpty)

        if isCtrlUp || isF3OrMCKey || isEscapeEmptyQuery {
            debugLog("Exit key pressed (keyCode: \(keyCode)) - deactivating Mission Control", category: AppLogger.missionControl)
            handleDeactivated()
            return false // Pass through so WindowServer exits Mission Control
        }

        // Before consuming or routing any keystroke, verify that Mission Control is genuinely active.
        // If Mission Control was dismissed (via gesture, mouse click outside, space switch, etc.)
        // without an AX notification, tear down the keyboard session immediately and pass the event through.
        let isMCActive: Bool
        if let mcService = missionControlService {
            isMCActive = mcService.checkMissionControlActive(force: true)
        } else {
            isMCActive = isMissionControlActiveProvider()
        }

        guard isMCActive else {
            debugLog("Keystroke ignored outside Mission Control (keyCode: \(keyCode)) - stopping keyboard session", category: AppLogger.eventTap)
            handleDeactivated()
            return false
        }

        guard isKeyboardNavigationEnabledProvider() else { return false }

        if windows.isEmpty {
            fetchWindows()
        }

        let effect = searchSession.handleKey(
            keyCode: keyCode,
            characters: characters,
            flags: flags,
            windows: windows
        )

        debugLog("searchSession effect: \(effect) for query '\(searchSession.query)'", category: AppLogger.missionControl)

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

    /// Resolves the middle (center) point of a preview thumbnail.
    /// Prefers the window bounds center from `WindowSelectionEngine.centerPoint`,
    /// falling back to `match.centerPoint`.
    func previewCenter(for match: WindowSelectionEngine.Match) -> CGPoint {
        if let bounds = match.windowInfo[kCGWindowBounds as String] as? [String: Any],
           let center = WindowSelectionEngine.centerPoint(for: bounds) {
            return center
        }
        return match.centerPoint
    }

    /// Updates the pill visibility and drives the native Mission Control highlight.
    /// Shows the pill only while `query` is non-empty; row-major Tab cycling
    /// with an empty query highlights without a pill. Computes matches once
    /// per keystroke and caches them in `currentMatches` for `activateSelectedWindow()`.
    /// When `query` is empty Tab uses `rowMajorSorted` (top-to-bottom, left-to-
    /// right with 40 pt row tolerance); otherwise uses `fuzzyMatch` ranking
    /// (prefix beats substring). Posts a synthetic `mouseMoved` and warps the cursor
    /// to the middle of the preview so AppKit paints the native blue highlight and
    /// syncs `hoveredWindow` for Cmd+W/Q/M shortcuts without parking in the top-left corner.
    private func updateSearchUI() {
        if searchSession.query.isEmpty {
            searchOverlay.hide()
        } else {
            searchOverlay.show(query: searchSession.query)
        }

        currentMatches = searchSession.query.isEmpty
            ? WindowSelectionEngine.rowMajorSorted(in: windows)
            : searchSession.matches(in: windows)

        if searchSession.selectedIndex >= 0, searchSession.selectedIndex < currentMatches.count {
            let match = currentMatches[searchSession.selectedIndex]
            let center = previewCenter(for: match)
            WindowActivationAction.postSyntheticMouseMoved(to: center)
            updateOverlay(at: center)

            // If Accessibility resolved an exact visual preview frame, align cursor to its exact visual center
            if let frame = currentPreviewFrame, !frame.isEmpty {
                let axCenter = CGPoint(x: frame.midX, y: frame.midY)
                if abs(axCenter.x - center.x) > 1 || abs(axCenter.y - center.y) > 1 {
                    WindowActivationAction.postSyntheticMouseMoved(to: axCenter)
                }
            }
        }
    }

    /// Activates the currently selected thumbnail. Reuses `currentMatches` from
    /// the last `updateSearchUI()` to avoid a second match computation on the
    /// same keystroke; recomputes only if the cache was cleared (e.g., by
    /// `clearSearch()` or a stale window poll). Plays haptics, clears the
    /// session/pill, then injects `mouseMoved` → `leftMouseDown` → 50 ms dwell
    /// → `leftMouseUp` at `.cghidEventTap` in the middle of the preview to reliably
    /// activate the Exposé thumbnail.
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
        let activationPoint: CGPoint
        if let frame = currentPreviewFrame, !frame.isEmpty {
            activationPoint = CGPoint(x: frame.midX, y: frame.midY)
        } else {
            activationPoint = previewCenter(for: match)
        }
        debugLog("activateSelectedWindow: activating window at middle point \(activationPoint)", category: AppLogger.missionControl)
        handleDeactivated()
        WindowActivationAction.performSyntheticClick(at: activationPoint)
    }

    /// Resets query / selection / pill / idle timer / match cache. Called on
    /// Escape, backspace-to-empty, activation, session teardown, and window-
    /// list invalidation.
    func clearSearch() {
        debugLog("clearSearch called", category: AppLogger.missionControl)
        searchSession.clear()
        currentMatches = []
        queryIdleTimer?.invalidate()
        queryIdleTimer = nil
        searchOverlay.hide()
        hideCloseOverlay()
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
            MainActor.assumeIsolated { self?.clearSearch() }
        }
    }
}
