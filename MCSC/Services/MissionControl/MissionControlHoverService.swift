import ApplicationServices
import Cocoa

@MainActor
protocol MissionControlHoverServiceProtocol: AnyObject {
    var isEnabled: Bool { get set }
    var isTracking: Bool { get }
    var isMissionControlActive: Bool { get }
    var isDragging: Bool { get }
    var currentHoveredWindow: [String: Any]? { get }
    var currentHoveredWindowFrame: CGRect? { get }
    var trackedWindowsCount: Int { get }

    func start()
    func stop()
    func hideOverlay()
    func hideAllOverlays()
    func handleActivated()
    func handleDeactivated()
    func clearSearch()
    func beginSpaceTransition()
    func beginSpaceTransition(duration: TimeInterval)

    /// Resolves the Mission Control preview window metadata under `point`,
    /// honoring space isolation and active preview hysteresis.
    func previewWindow(at point: CGPoint) -> (windowInfo: [String: Any], windowID: CGWindowID)?

    /// Executes an action (close, minimize, quit, fullscreen) on a Mission Control preview window,
    /// cleaning up the hover state and updating active window records.
    func executeAction(mode: PreviewCloseButtonOverlay.Mode, on windowInfo: [String: Any])
}

extension MissionControlHoverServiceProtocol {
    func beginSpaceTransition() {
        beginSpaceTransition(duration: 0.35)
    }
}

@MainActor
final class MissionControlHoverService: MissionControlHoverServiceProtocol {
    private let accessibilityService: AccessibilityServiceProtocol
    let isMissionControlActiveProvider: () -> Bool
    /// Weak ref to the shared detector so transitions can be pushed in via
    /// `markActive`. Weak because the ViewModel owns both services.
    weak var missionControlService: MissionControlServiceProtocol?
    let spaceService: SpaceManagementServiceProtocol
    private var injectedOverlay: (any PreviewCloseButtonOverlayProtocol)?
    private var createdOverlay: (any PreviewCloseButtonOverlayProtocol)?
    private var injectedSearchOverlay: (any SearchBarOverlayProtocol)?
    private var createdSearchOverlay: (any SearchBarOverlayProtocol)?

    /// Lazily created on first access so no `NSPanel` (and its GPU/IOSurface
    /// layer tree) exists until the overlay is actually needed. Tests can inject
    /// a pre-built overlay via the `init(overlay:)` parameter.
    var overlay: any PreviewCloseButtonOverlayProtocol {
        if let injectedOverlay {
            return injectedOverlay
        }
        if let createdOverlay {
            return createdOverlay
        }
        let newOverlay = PreviewCloseButtonOverlay()
        createdOverlay = newOverlay
        return newOverlay
    }

    /// Dock-styled floating pill that shows the uppercase query above the Dock.
    /// Follows the same DRY overlay lifecycle as `overlay`.
    var searchOverlay: any SearchBarOverlayProtocol {
        get {
            if let injectedSearchOverlay {
                return injectedSearchOverlay
            }
            if let createdSearchOverlay {
                return createdSearchOverlay
            }
            let newOverlay = SearchBarOverlay()
            createdSearchOverlay = newOverlay
            return newOverlay
        }
        set {
            injectedSearchOverlay = newValue
        }
    }

    /// Internal: owned/installed by `+InputTap.swift`.
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    /// Internal: installed by `+Observers.swift`.
    var axObserver: AXObserver?
    var dockAXElement: AXUIElement?
    var dockLaunchObserver: NSObjectProtocol?
    var dockTerminateObserver: NSObjectProtocol?
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
    /// Indicates whether a mouse drag operation is actively occurring.
    /// When dragging a preview or window in Mission Control, preview hover overlays (close buttons)
    /// are strictly suppressed to eliminate visual clutter and avoid interfering with drag-and-drop.
    var isDragging = false
    var isMouseDown = false
    var isSpaceTransitioning = false
    var spaceTransitionTimeoutTimer: Timer?
    private var isCmdHeld = false
    private var isOptionHeld = false
    private var isControlHeld = false
    private var hoveredWindow: [String: Any]?
    private var overlayRect: CGRect?
    /// Visual frame of the currently hovered Mission Control preview tile in AX coordinates.
    private(set) var currentPreviewFrame: CGRect?
    private var isOverlayHovered = false
    var lastKnownSpaceID: Int?
    /// Throttle high-frequency `mouseMoved` (~60-120 Hz) to 30 Hz so
    /// `isMissionControlActive` / `fetchWindows` do not IPC per pixel.
    private var lastMouseMovedTime: Double = 0
    private let mouseMoveInterval: Double = 1.0 / 30.0

    // MARK: - Keyboard fuzzy-finder state

    /// Dedicated HID tap for `keyDown` while Mission Control is open. Created
    /// lazily in `startKeyboardSession()` and torn down in `stopKeyboardSession()`
    /// / `stop()` so no global key tap persists outside Exposé.
    /// Internal state shared with `+KeyboardSearch.swift` (file split to stay
    /// under the SwiftLint `file_length` budget). The type remains
    /// main-actor confined.
    var keyboardTap: MCKeyboardTapServiceProtocol?
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
    /// neither → close (or eject if hovering an ejectable volume Finder window). Cmd takes precedence when several are
    /// held.
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
        if isAutoEjectEnabledProvider(),
           let hovered = hoveredWindow,
           ejectableMountPath(for: hovered) != nil {
            return .eject
        }
        return .close
    }

    /// Resolves an ejectable mount path for a window dictionary if it represents a Finder volume.
    func ejectableMountPath(for windowInfo: [String: Any]) -> String? {
        guard let owner = windowInfo[kCGWindowOwnerName as String] as? String,
              owner == "Finder",
              let volumeService else {
            return nil
        }
        let docPath: String?
        let winTitle: String?
        if let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
           let axWin = accessibilityService.getWindow(forWindowID: windowID) {
            docPath = accessibilityService.getDocumentPath(for: axWin)
            winTitle = accessibilityService
                .getWindowTitle(for: axWin) ?? (windowInfo[kCGWindowName as String] as? String)
        } else {
            docPath = nil
            winTitle = windowInfo[kCGWindowName as String] as? String
        }
        return volumeService.ejectableVolumePath(forDocumentPath: docPath, windowTitle: winTitle)
    }

    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            if !isEnabled {
                // Fully tear down the hover session: stop window polling,
                // keyboard navigation, and hide all overlays. The Dock
                // AXObserver and event tap remain alive so we still track
                // isMissionControlActive for other services.
                stopWindowFetchTimer()
                stopKeyboardSession()
                hideAllOverlays()
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
    weak var volumeService: MountedVolumeServiceProtocol?
    let isAutoEjectEnabledProvider: () -> Bool
    /// Filters PiP/floating windows out of the tracked window list. Weak so the
    /// view model keeps sole ownership.
    weak var componentClassifier: WindowComponentClassifier?

    init(accessibilityService: AccessibilityServiceProtocol,
         isMissionControlActiveProvider: @escaping () -> Bool,
         missionControlService: MissionControlServiceProtocol? = nil,
         spaceService: SpaceManagementServiceProtocol? = nil,
         overlay: (any PreviewCloseButtonOverlayProtocol)? = nil,
         searchOverlay: (any SearchBarOverlayProtocol)? = nil,
         volumeService: MountedVolumeServiceProtocol? = nil,
         isAutoEjectEnabledProvider: @escaping () -> Bool = { false },
         isKeyboardNavigationEnabledProvider: @escaping () -> Bool = { true },
         componentClassifier: WindowComponentClassifier? = nil) {
        self.accessibilityService = accessibilityService
        self.isMissionControlActiveProvider = isMissionControlActiveProvider
        self.missionControlService = missionControlService
        self.spaceService = spaceService ?? SpaceManagementService()
        self.injectedOverlay = overlay
        self.injectedSearchOverlay = searchOverlay
        self.volumeService = volumeService
        self.isAutoEjectEnabledProvider = isAutoEjectEnabledProvider
        self.isKeyboardNavigationEnabledProvider = isKeyboardNavigationEnabledProvider
        self.componentClassifier = componentClassifier
    }

    func start() {
        guard !isTracking else { return }
        isTracking = true

        setupDockProcessObservers()
        setupDockObserver()
        startInputTap()
        setupSpaceChangeObserver()
    }

    func stop() {
        guard isTracking else { return }
        isDragging = false
        isMouseDown = false
        spaceTransitionTimeoutTimer?.invalidate()
        spaceTransitionTimeoutTimer = nil
        isSpaceTransitioning = false
        removeDockProcessObservers()
        stopDockObserver()
        stopInputTap()
        stopWindowFetchTimer()
        removeSpaceChangeObserver()
        stopKeyboardSession()
        hideAllOverlays()
        isTracking = false
    }

    /// Suppresses overlays during in-flight space transitions (swipes or Ctrl+Arrow/Number keys).
    func beginSpaceTransition(duration: TimeInterval = 0.35) {
        if !isSpaceTransitioning {
            isSpaceTransitioning = true
            hideAllOverlays()
            clearSearch()
            hoveredWindow = nil
            currentPreviewFrame = nil
            overlayRect = nil
        }
        spaceTransitionTimeoutTimer?.invalidate()
        armSpaceTransitionTimeout(duration: duration)
    }

    private func armSpaceTransitionTimeout(duration: TimeInterval = 0.35) {
        spaceTransitionTimeoutTimer = Timer
            .scheduledCommon(interval: duration, repeats: false, tolerance: 0.05) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isSpaceTransitioning = false
                    self.spaceTransitionTimeoutTimer = nil
                    if self.isMissionControlActive {
                        self.fetchWindows()
                        if let loc = CGEvent(source: nil)?.location {
                            self.updateOverlay(at: loc)
                        }
                    }
                }
            }
    }

    // MARK: - Dock AXObserver & Input Event Tap live in the `+Observers` /

    // `+InputTap` splits.

    // MARK: - Window Polling

    func startWindowFetchTimer() {
        guard windowFetchTimer == nil else { return }
        windowFetchTimer = Timer.scheduledCommon(
            interval: HoverServiceTiming.windowPoll,
            repeats: true,
            tolerance: HoverServiceTiming.windowPollTolerance
        ) { [weak self] _ in
            self?.fetchWindows()
        }
    }

    func stopWindowFetchTimer() {
        windowFetchTimer?.invalidate()
        windowFetchTimer = nil
    }

    // MARK: - Space Change Tracking

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
        spaceTransitionTimeoutTimer?.invalidate()
        spaceTransitionTimeoutTimer = nil
        isSpaceTransitioning = false
        lastKnownSpaceID = spaceService.currentSpaceID()
        isDragging = false
        isMouseDown = false
        // Invalidate previous space hover and search state immediately so
        // stale frames and hysteresis never leak to the new space.
        hideAllOverlays()
        hoveredWindow = nil
        currentPreviewFrame = nil
        overlayRect = nil
        isOverlayHovered = false
        currentMatches = []
        searchSession = WindowSearchSession()

        fetchWindows()

        guard isMissionControlActive || isMissionControlActiveProvider() else {
            handleDeactivated()
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

    /// Fetches and filters the active window list for Mission Control tracking.
    ///
    /// ## macOS 27 WindowManager Multi-Space Isolation
    /// On macOS 27+, `com.apple.WindowManager` manages Mission Control at Layer 19.
    /// Crucially, its AX accessibility hierarchy retains preview tiles (`AXButton` elements
    /// with a `"wid"` attribute) for **all desktop spaces simultaneously** at their virtual
    /// desktop layout coordinates.
    ///
    /// If off-space windows are included in `windows`, `accessibilityService.getMissionControlPreviewTile`
    /// will hit-test and match ghost preview tiles from inactive spaces (e.g. hovering over Desktop 2
    /// hitting a Desktop 1 Ghostty window thumbnail).
    ///
    /// To ensure strict space isolation:
    /// 1. Only windows where `spaceService.isWindowOnCurrentSpace(windowID:) == true` are tracked.
    /// 2. Windows with no explicit space assignment (empty space IDs) belong to all spaces (e.g. floating Finder or
    /// panels).
    /// 3. Layers 0 through 3 are captured so floating utility and tool windows on secondary spaces are retained.
    func fetchWindows() {
        // Frozen by `_testSeedWindows` in unit tests so assertions are
        // deterministic regardless of the host's real window list.
        guard !isTestSeedingEnabled else { return }

        guard let list = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return
        }

        let filtered = list.filter { window in
            guard let layer = window[kCGWindowLayer as String] as? Int, layer >= 0, layer <= 3,
                  let owner = window[kCGWindowOwnerName as String] as? String,
                  owner != "Dock", owner != "MCSC", owner != "Window Server", owner != "WindowManager",
                  let wid = window[kCGWindowNumber as String] as? CGWindowID,
                  spaceService.isWindowOnCurrentSpace(windowID: wid) else {
                return false
            }
            // PiP and other floating components are not document windows: keep
            // them out of Mission Control tracking so no preview target exists.
            if componentClassifier?.isComponent(windowInfo: window) == true {
                return false
            }
            if let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
               let w = bounds["Width"], let h = bounds["Height"], w >= 100, h >= 100 {
                return true
            }
            return false
        }

        // Skip the assignment and overlay recomputation when the window list is
        // unchanged. A fast check on window count and IDs avoids redundant work on every 500ms poll.
        let isSame = filtered.count == windows.count && zip(filtered, windows).allSatisfy { f, w in
            (f[kCGWindowNumber as String] as? CGWindowID) == (w[kCGWindowNumber as String] as? CGWindowID)
        }
        if !isSame {
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
            debugLog(
                "handleMouseDown: click at \(location) outside overlay - hiding overlays and preparing drag",
                category: AppLogger.missionControl
            )
            isMouseDown = true
            hideAllOverlays()
            return false
        }

        debugLog("handleMouseDown: click at \(location) on overlay close button", category: AppLogger.missionControl)
        HapticService.perform(.pinchIn)
        executeAction(mode: currentOverlayMode, on: window)
        return true
    }

    func handleMouseDragged(at _: CGPoint) {
        guard isTracking, isEnabled else { return }
        isDragging = true
        hideCloseOverlay()
    }

    func handleMouseUp(at _: CGPoint) {
        guard isTracking, isEnabled else {
            isDragging = false
            isMouseDown = false
            return
        }
        let wasDragging = isDragging
        isDragging = false
        isMouseDown = false
        if wasDragging {
            hoveredWindow = nil
            currentPreviewFrame = nil
            overlayRect = nil
            if !isTestSeedingEnabled {
                fetchWindows()
            }
        }
    }

    func handleMouseMoved(at mouseLocation: CGPoint) {
        guard isTracking, isEnabled, !isDragging, !isMouseDown else {
            if isDragging || isMouseDown {
                hideCloseOverlay()
            } else {
                hideAllOverlays()
            }
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
        guard isTestSeedingEnabled || now - lastMouseMovedTime >= mouseMoveInterval else { return }
        lastMouseMovedTime = now

        let mcActive = isMissionControlActiveProvider()
        guard mcActive else {
            if isMissionControlActive {
                handleDeactivated()
            } else {
                hideAllOverlays()
            }
            return
        }

        if !isMissionControlActive {
            handleActivated()
        }

        if windows.isEmpty {
            fetchWindows()
        }

        updateOverlay(at: mouseLocation)
    }

    // MARK: - Overlay Management

    /// Updates the preview close button overlay based on the cursor position.
    ///
    /// Evaluates the cursor location in priority order:
    /// 1. Hovering the close button itself (preserves visibility so clicks register).
    /// 2. Active preview tile hysteresis (avoids jitter/repositioning within the same preview thumbnail).
    /// 3. Resolving the preview tile under cursor via Accessibility (macOS 27 WindowManager preview buttons).
    /// 4. Falls back to window frames seeded during unit testing.
    /// 5. Otherwise hides the overlay.
    func updateOverlay(at mouseLocation: CGPoint) {
        guard !isDragging, !isMouseDown, !isSpaceTransitioning else {
            hideCloseOverlay()
            return
        }
        // 0. Space tracking: detect space transitions occurring while inside Mission Control
        if let currentSpace = spaceService.currentSpaceID() {
            if let last = lastKnownSpaceID, last != currentSpace {
                lastKnownSpaceID = currentSpace
                beginSpaceTransition(duration: 0.35)
                return
            }
            lastKnownSpaceID = currentSpace
        }

        // 1. If mouse is hovering over the action button itself, keep it visible
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

        // 2. Active preview tile hysteresis:
        // If cursor is still inside the current preview tile's visual bounds and the hovered window is valid
        // on the active desktop space, keep the overlay firmly anchored.
        if let currentPreviewFrame, currentPreviewFrame.contains(mouseLocation),
           let hovered = hoveredWindow,
           let wid = hovered[kCGWindowNumber as String] as? CGWindowID,
           isTestSeedingEnabled ||
           (spaceService.isWindowOnCurrentSpace(windowID: wid) && windows
               .contains(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == wid })) {
            return
        }

        // If there are no windows tracked on this space, never show the preview close overlay.
        if windows.isEmpty, !isTestSeedingEnabled {
            hideCloseOverlay()
            return
        }

        // 3. macOS 27: Resolve the preview tile via Accessibility
        // (WindowManager exposes AXButton preview tiles with their exact visual frame and "wid" attribute).
        // Candidate windows are strictly constrained to `currentWindowIDs` (active space only)
        // to prevent matching off-screen/masked preview buttons belonging to other spaces.
        let currentWindowIDs = Set(windows.compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
        if let (tileElement, wid) = accessibilityService.getMissionControlPreviewTile(
            at: mouseLocation,
            matchingWindowIDs: currentWindowIDs
        ) {
            // Defense-in-depth: guarantee candidate belongs to active desktop space before showing overlay.
            guard isTestSeedingEnabled || spaceService.isWindowOnCurrentSpace(windowID: wid),
                  let winInfo = windows.first(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == wid })
            else {
                hideCloseOverlay()
                return
            }
            let previewFrame = accessibilityService.getFrame(for: tileElement) ?? .zero
            if !previewFrame.isEmpty {
                hoveredWindow = winInfo
                currentPreviewFrame = previewFrame
                let closeButtonFrame = accessibilityService.getPreviewCloseButtonFrame(for: tileElement)
                overlay.show(for: previewFrame, closeButtonFrame: closeButtonFrame, mode: currentOverlayMode)
                overlayRect = overlay.currentAXRect
                return
            }
        }

        // 4. Test-seeding support: when window list is seeded via _testSeedWindows in unit test harnesses
        if isTestSeedingEnabled {
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
                    currentPreviewFrame = windowFrame
                    overlay.show(for: windowFrame, mode: currentOverlayMode)
                    overlayRect = overlay.currentAXRect
                    return
                }
            }
        }

        // Cursor is not over any preview thumbnail: hide the close button overlay only.
        hideCloseOverlay()
    }

    /// Hides the close/action button overlay and clears active preview frame state.
    func hideCloseOverlay() {
        if hoveredWindow != nil || overlay.isVisible || currentPreviewFrame != nil {
            hoveredWindow = nil
            currentPreviewFrame = nil
            overlayRect = nil
            if isOverlayHovered {
                isOverlayHovered = false
                overlay.setHovered(false)
            }
            overlay.hide()
        }
    }

    /// Hides the search bar overlay and clears any ongoing search query and selection.
    func hideSearchOverlay() {
        clearSearch()
    }

    /// Synchronously hides all Mission Control overlays (both close button and search bar)
    /// following unified lifecycle management (DRY).
    func hideAllOverlays() {
        hideCloseOverlay()
        hideSearchOverlay()
    }

    /// Backwards-compatible dismissal: hides all Mission Control overlays.
    func hideOverlay() {
        hideAllOverlays()
    }

    // MARK: - Preview Tile Resolution & Actions

    var currentHoveredWindow: [String: Any]? {
        hoveredWindow
    }

    var currentHoveredWindowFrame: CGRect? {
        currentPreviewFrame
    }

    var trackedWindowsCount: Int {
        windows.count
    }

    func previewWindow(at point: CGPoint) -> (windowInfo: [String: Any], windowID: CGWindowID)? {
        // 1. Fast path: if cursor is still within the active preview thumbnail frame
        if let currentPreviewFrame, currentPreviewFrame.contains(point),
           let hovered = hoveredWindow,
           let wid = hovered[kCGWindowNumber as String] as? CGWindowID,
           isTestSeedingEnabled ||
           (spaceService.isWindowOnCurrentSpace(windowID: wid) && windows
               .contains(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == wid })) {
            return (hovered, wid)
        }

        if windows.isEmpty, !isTestSeedingEnabled {
            fetchWindows()
            if windows.isEmpty {
                return nil
            }
        }

        let currentWindowIDs = Set(windows.compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
        if let (tileElement, wid) = accessibilityService.getMissionControlPreviewTile(
            at: point,
            matchingWindowIDs: currentWindowIDs
        ) {
            guard isTestSeedingEnabled || spaceService.isWindowOnCurrentSpace(windowID: wid),
                  let winInfo = windows.first(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == wid })
            else {
                return nil
            }
            let frame = accessibilityService.getFrame(for: tileElement) ?? .zero
            if !frame.isEmpty {
                hoveredWindow = winInfo
                currentPreviewFrame = frame
            }
            return (winInfo, wid)
        }

        if isTestSeedingEnabled {
            for windowInfo in windows {
                guard let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                      let x = boundsDict["X"], let y = boundsDict["Y"],
                      let width = boundsDict["Width"], let height = boundsDict["Height"] else {
                    continue
                }
                let windowFrame = CGRect(x: x, y: y, width: width, height: height)
                if windowFrame.contains(point), let wid = windowInfo[kCGWindowNumber as String] as? CGWindowID {
                    hoveredWindow = windowInfo
                    currentPreviewFrame = windowFrame
                    return (windowInfo, wid)
                }
            }
        }

        return nil
    }

    private func performCloseWindow(on windowInfo: [String: Any]) {
        var closedNatively = false
        let targetWid = windowInfo[kCGWindowNumber as String] as? CGWindowID
        if let frame = currentPreviewFrame,
           let (tileElement, _) = accessibilityService.getMissionControlPreviewTile(
               at: CGPoint(x: frame.midX, y: frame.midY),
               matchingWindowIDs: targetWid.map { Set([$0]) }
           ),
           let nativeButton = accessibilityService.getPreviewCloseButton(for: tileElement) {
            closedNatively = accessibilityService.performAction(kAXPressAction, on: nativeButton)
        }
        if !closedNatively {
            MissionControlWindowActions.performClose(on: windowInfo, accessibilityService: accessibilityService)
        }
    }

    func executeAction(mode: PreviewCloseButtonOverlay.Mode, on windowInfo: [String: Any]) {
        switch mode {
        case .close:
            performCloseWindow(on: windowInfo)
            if isAutoEjectEnabledProvider(),
               let mountPath = ejectableMountPath(for: windowInfo),
               let volumeService {
                volumeService.ejectVolume(at: mountPath) { _ in }
            }
        case .eject:
            performCloseWindow(on: windowInfo)
            if let mountPath = ejectableMountPath(for: windowInfo),
               let volumeService {
                volumeService.ejectVolume(at: mountPath) { _ in }
            }
        case .minimize:
            MissionControlWindowActions.performMinimize(on: windowInfo, accessibilityService: accessibilityService)
        case .quit:
            MissionControlWindowActions.performForceQuit(on: windowInfo)
        case .fullscreen:
            MissionControlWindowActions.performFullscreen(on: windowInfo, accessibilityService: accessibilityService)
        }

        if let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID {
            windows.removeAll { ($0[kCGWindowNumber as String] as? CGWindowID) == windowID }
        }

        hoveredWindow = nil
        currentPreviewFrame = nil
        hideAllOverlays()
    }

    deinit {
        if let observer = dockLaunchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let observer = dockTerminateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let observer = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let obs = axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopSourceInvalidate(source)
        }
    }
}
