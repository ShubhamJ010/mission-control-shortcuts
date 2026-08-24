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
    /// Weak ref to the shared detector so the Dock AXObserver transition can
    /// be pushed in via `markActive` instead of waiting for the lagging 350 ms
    /// window-list scan. Weak because the ViewModel owns both services.
    weak var missionControlService: MissionControlServiceProtocol?
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

    /// Internal: owned/installed by `+InputTap.swift`.
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    /// Internal: installed by `+Observers.swift`.
    var axObserver: AXObserver?
    var dockAXElement: AXUIElement?
    private var windowFetchTimer: Timer?
    /// Internal so tests can verify lifecycle without exposing to production
    /// callers outside the module.
    var spaceChangeObserver: NSObjectProtocol?

    /// Internal: read by `+KeyboardSearch.swift` for fuzzy matching.
    var windows: [[String: Any]] = []
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
    /// Internal: driven by `+Observers.swift` AXExpose notifications.
    var isMissionControlActive = false
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
    /// Internal state shared with `+KeyboardSearch.swift` (file split to stay
    /// under the SwiftLint `file_length` budget). The type remains
    /// main-actor confined.
    var keyboardTap: MCKeyboardTapServiceProtocol?
    /// Dock-styled floating pill that shows the uppercase query above the Dock.
    /// Created lazily on first typed character to avoid allocating an `NSPanel`
    /// until the feature is actually used.
    var searchOverlay: SearchBarOverlay?
    /// Pure state machine for query / selectedIndex / Effect. Never touches
    /// views or posts events; all side effects are driven by the service.
    var searchSession = WindowSearchSession()
    /// Idle timer that clears the query after 2 s of inactivity. Only armed
    /// when the "Keyboard Navigation" toggle is off; when the toggle is on the
    /// session persists until activation or Escape so Tab cycling keeps the
    /// pill visible. See `resetIdleTimer()`.
    var queryIdleTimer: Timer?
    /// Cache of the last fuzzy-match results for the current keystroke. Avoids
    /// recomputing `WindowSelectionEngine.fuzzyMatch` twice per key (once for
    /// `syncSelection` in `handleKey` and again for highlight / activation) and
    /// is invalidated on `clearSearch()` or window-list refresh.
    var currentMatches: [WindowSelectionEngine.Match] = []

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

    let isKeyboardNavigationEnabledProvider: () -> Bool

    init(accessibilityService: AccessibilityServiceProtocol,
         isMissionControlActiveProvider: @escaping () -> Bool,
         missionControlService: MissionControlServiceProtocol? = nil,
         overlay: PreviewCloseButtonOverlay? = nil,
         animationStrategy: OverlayAnimationStrategy? = nil,
         isKeyboardNavigationEnabledProvider: @escaping () -> Bool = { true }) {
        self.accessibilityService = accessibilityService
        self.isMissionControlActiveProvider = isMissionControlActiveProvider
        self.missionControlService = missionControlService
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

    // MARK: - Dock AXObserver & Input Event Tap live in the `+Observers` /

    // `+InputTap` extension files (SwiftLint file_length budget).

    // MARK: - Window Polling

    func startWindowFetchTimer() {
        stopWindowFetchTimer()
        windowFetchTimer = Timer.scheduledCommon(
            interval: HoverServiceTiming.windowPoll,
            repeats: true,
            tolerance: HoverServiceTiming.windowPollTolerance
        ) { [weak self] _ in
            Task { @MainActor in self?.fetchWindows() }
        }
    }

    func stopWindowFetchTimer() {
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

    func fetchWindows() {
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

    // MARK: - Input Event Tap lives in `+InputTap.swift`.

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

    func updateOverlay(at mouseLocation: CGPoint) {
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

    func hideOverlay() {
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
