import ApplicationServices
import Cocoa

@_silgen_name("_AXUIElementGetWindow")
@discardableResult
func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

@MainActor
protocol MissionControlHoverServiceProtocol: AnyObject {
    var isEnabled: Bool { get set }
    var isTracking: Bool { get }

    func start()
    func stop()
}

@MainActor
final class MissionControlHoverService: MissionControlHoverServiceProtocol {
    private let accessibilityService: AccessibilityServiceProtocol
    private let isMissionControlActiveProvider: () -> Bool
    private var injectedOverlay: PreviewCloseButtonOverlay?
    private var createdOverlay: PreviewCloseButtonOverlay?
    private let animationStrategy: OverlayAnimationStrategy

    /// Lazily created on first access so no `NSPanel` (and its GPU/IOSurface
    /// layer tree) exists until the overlay is actually needed. Tests can inject
    /// a pre-built overlay via the `init(overlay:)` parameter.
    private var overlay: PreviewCloseButtonOverlay {
        if let injectedOverlay {
            return injectedOverlay
        }
        if let createdOverlay {
            return createdOverlay
        }
        let newOverlay = PreviewCloseButtonOverlay(strategy: animationStrategy)
        createdOverlay = newOverlay
        return newOverlay
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var axObserver: AXObserver?
    private var dockAXElement: AXUIElement?
    private var windowFetchTimer: Timer?
    /// Internal so tests can verify lifecycle without exposing to production
    /// callers outside the module.
    var spaceChangeObserver: NSObjectProtocol?

    private var windows: [[String: Any]] = []
    /// Test-only window count for verifying dedup behavior without depending
    /// on the real CGWindowList scan. Returns the number of tracked windows.
    var _testWindowCount: Int {
        windows.count
    }
    /// Test-only seeding of the tracked window list so `handleSpaceChange`
    /// regression tests are deterministic — they do not depend on which real
    /// windows the CGWindowList IPC happens to return in the test host.
    /// Seeding also *freezes* the list: subsequent `fetchWindows()` calls are
    /// no-ops until the service stops, mirroring how `_testWindowCount`
    /// decouples assertions from the live window-list scan. Each entry needs
    /// `kCGWindowBounds` as `["X","Y","Width","Height"]`.
    func _testSeedWindows(_ seeded: [[String: Any]]) {
        isTestSeedingEnabled = true
        windows = seeded
    }
    private var isTestSeedingEnabled = false

    private(set) var isTracking = false
    private var isMissionControlActive = false
    private var isCmdHeld = false
    private var isOptionHeld = false
    private var isControlHeld = false
    private var hoveredWindow: [String: Any]?
    private var overlayRect: CGRect?
    private var isOverlayHovered = false
    /// Throttle high-frequency `mouseMoved` (~60-120 Hz) to 30 Hz so
    /// `isMissionControlActive` / `fetchWindows` do not IPC per pixel.
    private var lastMouseMovedTime: Double = 0
    private let mouseMoveInterval: Double = 1.0 / 30.0

    // MARK: - Keyboard fuzzy-finder state

    /// Dedicated HID tap for `keyDown` while Mission Control is open. Created
    /// lazily in `startKeyboardSession()` and torn down in `stopKeyboardSession()`
    /// / `stop()` / `deinit` so no global key tap persists outside Exposé.
    private var keyboardTap: MCKeyboardTapServiceProtocol?
    /// Dock-styled floating pill that shows the uppercase query above the Dock.
    /// Created lazily on first typed character to avoid allocating an `NSPanel`
    /// until the feature is actually used.
    private var searchOverlay: SearchBarOverlay?
    /// Pure state machine for query / selectedIndex / Effect. Never touches
    /// views or posts events; all side effects are driven by the service.
    private var searchSession = WindowSearchSession()
    /// Idle timer that clears the query after 2 s of inactivity. Only armed
    /// when the "Keyboard Navigation" toggle is off; when the toggle is on the
    /// session persists until activation or Escape so Tab cycling keeps the
    /// pill visible. See `resetIdleTimer()`.
    private var queryIdleTimer: Timer?
    /// Cache of the last fuzzy-match results for the current keystroke. Avoids
    /// recomputing `WindowSelectionEngine.fuzzyMatch` twice per key (once for
    /// `syncSelection` in `handleKey` and again for highlight / activation) and
    /// is invalidated on `clearSearch()` or window-list refresh.
    private var currentMatches: [WindowSelectionEngine.Match] = []

    private enum Timing {
        static let windowPoll: TimeInterval = 0.5
        static let windowPollTolerance: TimeInterval = 0.05
        static let queryIdle: TimeInterval = 2.0
        static let queryIdleTolerance: TimeInterval = 0.2
    }

    /// The action the hover button currently represents, derived from held
    /// modifiers: Cmd → force quit, Option → minimize, Control → fullscreen,
    /// neither → close. Cmd takes precedence when several are held.
    var currentOverlayMode: PreviewCloseButtonOverlay.Mode {
        if isCmdHeld {
            return .quit
        }
        if isControlHeld {
            return .fullscreen
        }
        if isOptionHeld {
            return .minimize
        }
        return .close
    }

    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            if !isEnabled {
                // Fully tear down the hover session: stop window polling,
                // keyboard navigation, and hide the overlay. The Dock
                // AXObserver and event tap remain alive so we still track
                // isMissionControlActive for other services.
                stopWindowFetchTimer()
                stopKeyboardSession()
                hideOverlay()
            } else if isMissionControlActive {
                // Re-enabled while Mission Control is already open:
                // spin up the full session so the user sees the button.
                fetchWindows()
                startWindowFetchTimer()
                startKeyboardSession()
                if let mouseLocation = CGEvent(source: nil)?.location {
                    updateOverlay(at: mouseLocation)
                }
            }
        }
    }

    private let isKeyboardNavigationEnabledProvider: () -> Bool

    init(accessibilityService: AccessibilityServiceProtocol,
         isMissionControlActiveProvider: @escaping () -> Bool,
         overlay: PreviewCloseButtonOverlay? = nil,
         animationStrategy: OverlayAnimationStrategy? = nil,
         isKeyboardNavigationEnabledProvider: @escaping () -> Bool = { true }) {
        self.accessibilityService = accessibilityService
        self.isMissionControlActiveProvider = isMissionControlActiveProvider
        self.injectedOverlay = overlay
        self.animationStrategy = animationStrategy ?? OptimizedOverlayAnimationStrategy()
        self.isKeyboardNavigationEnabledProvider = isKeyboardNavigationEnabledProvider
    }

    func start() {
        guard !isTracking else { return }
        isTracking = true

        setupDockObserver()
        startInputTap()
        setupSpaceChangeObserver()
    }

    func stop() {
        guard isTracking else { return }
        stopDockObserver()
        stopInputTap()
        stopWindowFetchTimer()
        removeSpaceChangeObserver()
        stopKeyboardSession()
        hideOverlay()
        isTracking = false
    }

    // MARK: - Dock AXObserver

    private static let dockNotifications = [
        "AXExposeShowAllWindows",
        "AXExposeShowFrontWindows",
        "AXExposeShowDesktop",
        "AXExposeExit",
    ]

    private func setupDockObserver() {
        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else {
            return
        }

        let pid = dockApp.processIdentifier
        let dockElement = AXUIElementCreateApplication(pid)
        self.dockAXElement = dockElement

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, notification, refcon in
            guard let refcon else { return }
            let service = Unmanaged<MissionControlHoverService>.fromOpaque(refcon).takeUnretainedValue()
            let notifName = notification as String

            DispatchQueue.main.async {
                service.handleDockNotification(notifName)
            }
        }

        guard AXObserverCreate(pid, callback, &observer) == .success, let obs = observer else {
            return
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        for notif in Self.dockNotifications {
            AXObserverAddNotification(obs, dockElement, notif as CFString, selfPtr)
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        self.axObserver = obs
    }

    private func stopDockObserver() {
        if let obs = axObserver, let dockElement = dockAXElement {
            for notif in Self.dockNotifications {
                AXObserverRemoveNotification(obs, dockElement, notif as CFString)
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
            self.axObserver = nil
            self.dockAXElement = nil
        }
    }

    private func handleDockNotification(_ notification: String) {
        if notification == "AXExposeExit" {
            isMissionControlActive = false
            stopWindowFetchTimer()
            hideOverlay()
            stopKeyboardSession()
        } else {
            isMissionControlActive = true

            // When the feature is disabled, track Mission Control state
            // (other services depend on it) but do NOT create the overlay,
            // start window polling, or install the keyboard tap.
            guard isEnabled else { return }

            fetchWindows()
            startWindowFetchTimer()
            startKeyboardSession()

            if let mouseLocation = CGEvent(source: nil)?.location {
                updateOverlay(at: mouseLocation)
            }
        }
    }

    // MARK: - Window Polling

    private func startWindowFetchTimer() {
        stopWindowFetchTimer()
        windowFetchTimer = Timer.scheduledCommon(
            interval: Timing.windowPoll,
            repeats: true,
            tolerance: Timing.windowPollTolerance
        ) { [weak self] _ in
            Task { @MainActor in self?.fetchWindows() }
        }
    }

    private func stopWindowFetchTimer() {
        windowFetchTimer?.invalidate()
        windowFetchTimer = nil
    }

    // MARK: - Active Space Change

    /// Refreshes the window list and overlay when the active Space changes
    /// while Mission Control is open. Without this, `windows` can reference
    /// windows that no longer exist on the new Space.
    private func setupSpaceChangeObserver() {
        guard spaceChangeObserver == nil else { return }
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleSpaceChange()
            }
        }
    }

    /// Handles `activeSpaceDidChangeNotification`.
    ///
    /// Refreshes the tracked window list so it matches the new Space, but
    /// recomputes the hover overlay **only while Mission Control is open**.
    /// A plain desktop switch (Ctrl+←/→ or three-finger swipe) must never
    /// surface the preview close button: showing it here would flash for one
    /// frame before the next `handleMouseMoved` guard hides it again.
    ///
    /// - Parameter mouseLocation: Explicit cursor position override used by
    ///   tests. When `nil`, the current global cursor position is resolved
    ///   from the event system.
    func handleSpaceChange(at mouseLocation: CGPoint? = nil) {
        fetchWindows()

        guard isMissionControlActive || isMissionControlActiveProvider() else {
            return
        }

        let location = mouseLocation ?? CGEvent(source: nil)?.location
        if let location {
            updateOverlay(at: location)
        }
    }

    private func removeSpaceChangeObserver() {
        if let observer = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            spaceChangeObserver = nil
        }
    }

    private func fetchWindows() {
        // Frozen by `_testSeedWindows` in unit tests so assertions are
        // deterministic regardless of the host's real window list.
        guard !isTestSeedingEnabled else { return }

        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return
        }

        let filtered = list.filter { window in
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let owner = window[kCGWindowOwnerName as String] as? String,
                  owner != "Dock", owner != "MCSC", owner != "Window Server" else {
                return false
            }
            if let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
               let w = bounds["Width"], let h = bounds["Height"], w >= 100, h >= 100 {
                return true
            }
            return false
        }

        // Skip the assignment and overlay recomputation when the window list is
        // unchanged. A deep compare avoids redundant work on every 500ms poll.
        if !NSArray(array: filtered).isEqual(to: windows) {
            windows = filtered
        }
    }

    // MARK: - Input Event Tap

    private func startInputTap() {
        guard eventTap == nil else { return }

        let mask = (1 << CGEventType.mouseMoved.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<MissionControlHoverService>.fromOpaque(refcon).takeUnretainedValue()

                // macOS disables event taps on timeout or user input; re-enable
                // so hover tracking survives without an app restart.
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = service.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                if type == .flagsChanged {
                    let cmdPressed = event.flags.contains(.maskCommand)
                    let optionPressed = event.flags.contains(.maskAlternate)
                    let controlPressed = event.flags.contains(.maskControl)
                    if Thread.isMainThread {
                        service.handleFlagsChanged(
                            cmdPressed: cmdPressed,
                            optionPressed: optionPressed,
                            controlPressed: controlPressed
                        )
                    } else {
                        DispatchQueue.main.async {
                            service.handleFlagsChanged(
                                cmdPressed: cmdPressed,
                                optionPressed: optionPressed,
                                controlPressed: controlPressed
                            )
                        }
                    }
                    return Unmanaged.passUnretained(event)
                }

                if type == .leftMouseDown {
                    let location = event.location
                    var intercepted = false

                    // Safely check if click hit the overlay button without blocking main thread
                    if Thread.isMainThread {
                        intercepted = service.handleMouseDown(at: location)
                    } else {
                        DispatchQueue.main.sync {
                            intercepted = service.handleMouseDown(at: location)
                        }
                    }

                    if intercepted {
                        return nil // Swallow the click so Mission Control does not dismiss prematurely
                    }
                    return Unmanaged.passUnretained(event)
                }

                let location = event.location
                if Thread.isMainThread {
                    service.handleMouseMoved(at: location)
                } else {
                    DispatchQueue.main.async {
                        service.handleMouseMoved(at: location)
                    }
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stopInputTap() {
        if let source = runLoopSource {
            CFRunLoopSourceInvalidate(source)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
    }

    func handleFlagsChanged(cmdPressed: Bool, optionPressed: Bool, controlPressed: Bool = false) {
        guard isTracking, isEnabled else { return }
        isCmdHeld = cmdPressed
        isOptionHeld = optionPressed
        isControlHeld = controlPressed
        overlay.setMode(currentOverlayMode)
    }

    func handleMouseDown(at location: CGPoint) -> Bool {
        guard isTracking && isEnabled, isMissionControlActive || isMissionControlActiveProvider() else {
            return false
        }

        guard let rect = overlayRect, rect.contains(location), let window = hoveredWindow else {
            return false
        }

        executeAction(on: window)
        return true
    }

    func handleMouseMoved(at mouseLocation: CGPoint) {
        guard isTracking && isEnabled else {
            hideOverlay()
            return
        }

        // Fast-path: if already hovering the button, keep it cheap and
        // bypass MC-active IPC throttling so hover feels instant.
        if let rect = overlayRect, rect.contains(mouseLocation), hoveredWindow != nil {
            if !isOverlayHovered {
                isOverlayHovered = true
                overlay.setHovered(true)
            }
            return
        }

        // Throttle MC-active check (WindowServer IPC) to 30 Hz.
        let now = CACurrentMediaTime()
        guard now - lastMouseMovedTime >= mouseMoveInterval else { return }
        lastMouseMovedTime = now

        guard isMissionControlActive || isMissionControlActiveProvider() else {
            hideOverlay()
            return
        }

        if windows.isEmpty {
            fetchWindows()
        }

        updateOverlay(at: mouseLocation)
    }

    private func updateOverlay(at mouseLocation: CGPoint) {
        // If mouse is hovering over the action button itself, keep it visible
        if let rect = overlayRect, rect.contains(mouseLocation), hoveredWindow != nil {
            if !isOverlayHovered {
                isOverlayHovered = true
                overlay.setHovered(true)
            }
            return
        }

        // Mouse left the button: release hover state.
        if isOverlayHovered {
            isOverlayHovered = false
            overlay.setHovered(false)
        }

        // Find window containing cursor
        for windowInfo in windows {
            guard let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"],
                  let y = boundsDict["Y"],
                  let width = boundsDict["Width"],
                  let height = boundsDict["Height"] else {
                continue
            }

            let windowFrame = CGRect(x: x, y: y, width: width, height: height)

            if windowFrame.contains(mouseLocation) {
                hoveredWindow = windowInfo
                let halfDim = PreviewCloseButtonOverlay.buttonDimension / 2.0
                overlayRect = CGRect(
                    x: x - halfDim,
                    y: y - halfDim,
                    width: PreviewCloseButtonOverlay.buttonDimension,
                    height: PreviewCloseButtonOverlay.buttonDimension
                )
                overlay.show(at: windowFrame, mode: currentOverlayMode)
                return
            }
        }

        hideOverlay()
    }

    private func hideOverlay() {
        if hoveredWindow != nil || overlay.isVisible {
            hoveredWindow = nil
            overlayRect = nil
            if isOverlayHovered {
                isOverlayHovered = false
                overlay.setHovered(false)
            }
            overlay.hide()
        }
    }

    // MARK: - Actions

    private func executeAction(on windowInfo: [String: Any]) {
        HapticService.perform(.pinchIn)

        switch currentOverlayMode {
        case .close:
            MissionControlWindowActions.performClose(on: windowInfo, accessibilityService: accessibilityService)
        case .minimize:
            MissionControlWindowActions.performMinimize(on: windowInfo, accessibilityService: accessibilityService)
        case .quit:
            MissionControlWindowActions.performForceQuit(on: windowInfo)
        case .fullscreen:
            MissionControlWindowActions.performFullscreen(on: windowInfo)
        }

        if let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID {
            windows.removeAll { ($0[kCGWindowNumber as String] as? CGWindowID) == windowID }
        }

        hideOverlay()
    }

    deinit {
        if let source = runLoopSource {
            CFRunLoopSourceInvalidate(source)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        keyboardTap?.stop()
        // Both timers must die with the service: a repeating `windowFetchTimer`
        // that survives dealloc would poll a zombie instance every 0.5 s (the
        // timer's block retains the closure target chain).
        windowFetchTimer?.invalidate()
        windowFetchTimer = nil
        queryIdleTimer?.invalidate()
        queryIdleTimer = nil
        if let obs = axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        }
        if let observer = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}

extension MissionControlHoverService {
    // MARK: - Keyboard Fuzzy-Finder (type-to-select)

    /// Resets the session and installs a fresh `MCKeyboardTapService` for the
    /// current Mission Control appearance. The HID tap is gated by the single
    /// "Keyboard Navigation" toggle in `ShortcutConfiguration` and is not
    /// created at all when the toggle is off, so keystrokes pass through.
    private func startKeyboardSession() {
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
    private func stopKeyboardSession() {
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
            interval: Timing.queryIdle,
            repeats: false,
            tolerance: Timing.queryIdleTolerance
        ) { [weak self] _ in
            Task { @MainActor in self?.clearSearch() }
        }
    }
}

/// Centralizes the `RunLoop.main` in `.common` modes + tolerance pattern used
/// for `windowFetchTimer` (0.5 s poll during Exposé) and `queryIdleTimer`
/// (2 s idle clear). Using `.common` modes ensures the timer fires while
/// Mission Control's tracking run loop is active, and tolerance allows the
/// system to coalesce the timer for power efficiency. Power-efficient and
/// consistent across future timers in this service.
private extension Timer {
    /// Creates and schedules a timer on `RunLoop.main` in `.common` modes with
    /// the given tolerance. The timer is auto-added to the run loop and
    /// returned for invalidation by the caller.
    static func scheduledCommon(
        interval: TimeInterval,
        repeats: Bool,
        tolerance: TimeInterval,
        block: @escaping (Timer) -> Void
    ) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats, block: block)
        timer.tolerance = tolerance
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
