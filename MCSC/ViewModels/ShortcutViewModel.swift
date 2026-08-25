import Cocoa

/// Central coordinator of the MVVM layer.
///
/// `ShortcutViewModel` wires together the low-level services (`EventTapServiceProtocol`,
/// `MultitouchService`, `AccessibilityServiceProtocol`, `MissionControlServiceProtocol`) and
/// delegates shortcut and gesture routing to `ShortcutActionRouter` and `GestureActionRouter`.
///
/// - Threading: callbacks from the event taps are delivered on the main thread;
///   gesture frames arrive via `main.async`, so all state access here is main-thread-confined.
/// - Retain-cycle safety: every closure handed to a service captures `self`
///   weakly (`[weak self]`), and heavy blocking AX actions are deferred one
///   run-loop turn so the UI (feedback overlay, haptics) can commit first.
@MainActor
final class ShortcutViewModel {
    // Services shared with the `+TargetResolution` / `+Lifecycle` extension
    // files are `internal` rather than `private`; the type stays main-actor
    // confined either way.
    let eventTapService: EventTapServiceProtocol
    let accessibilityService: AccessibilityServiceProtocol
    let missionControlService: MissionControlServiceProtocol
    private let launchAtLoginService: LaunchAtLoginService

    lazy var multitouchService = MultitouchService()
    lazy var gestureEngine = GestureEngine()
    /// Animation backend shared by every overlay, chosen once at startup from
    /// UserDefaults so no runtime driver switching or bloat occurs.
    private lazy var animationStrategy: OverlayAnimationStrategy =
        config.isOptimizedAnimationModeEnabled
            ? OptimizedOverlayAnimationStrategy()
            : NativeSymbolEffectAnimationStrategy()

    lazy var hoverService: MissionControlHoverServiceProtocol = MissionControlHoverService(
        accessibilityService: accessibilityService,
        isMissionControlActiveProvider: { [weak self] in
            self?.missionControlService.isMissionControlActive ?? false
        },
        missionControlService: missionControlService,
        animationStrategy: animationStrategy,
        isKeyboardNavigationEnabledProvider: { [weak self] in
            self?.config.isKeyboardNavigationEnabled ?? true
        }
    )

    lazy var cursorFeedback: CursorFeedbackOverlay = .init(strategy: animationStrategy)

    lazy var volumeService: MountedVolumeServiceProtocol = MountedVolumeService()
    /// Lazily-created event tap that swallows App Exposé / context-menu
    /// triggers (smartMagnify, synthesized clicks) while gestures or
    /// double-taps are aimed at Dock icons outside Mission Control.
    /// Providers use `[weak self]` so the suppressor never keeps the VM alive.
    lazy var dockSuppressor: DockInteractionSuppressorProtocol = {
        let suppressor = DockInteractionSuppressor()
        suppressor.isDockHoveredProvider = { [weak self] point in
            guard let self else { return false }
            return self.accessibilityService.isDockRegion(at: point)
        }
        suppressor.isEnabledProvider = { [weak self] in
            guard let self else { return false }
            return !self.missionControlService.isMissionControlActive && self.config.isDockActionsOutsideMCEnabled
        }
        return suppressor
    }()

    /// Desktop-navigation actions need to know whether Mission Control is open
    /// so they can dismiss it before dragging a window across Spaces. Provider
    /// uses `[weak self]` so the registry never keeps the VM alive.
    private lazy var actionRegistry = ActionRegistry(isMissionControlActiveProvider: { [weak self] in
        guard let self else { return false }
        return self.missionControlService.isMissionControlActive
    })
    lazy var shortcutRouter = ShortcutActionRouter(actions: actionRegistry)
    lazy var gestureRouter = GestureActionRouter(actions: actionRegistry)

    var config = ShortcutConfiguration()

    /// Forwarding properties for configuration (keeps AppDelegate API unchanged)
    var isClosingEnabled: Bool {
        get { config.isClosingEnabled } set { config.isClosingEnabled = newValue }
    }

    var isCmdWEnabled: Bool {
        get { config.isCmdWEnabled } set { config.isCmdWEnabled = newValue }
    }

    var isCmdQEnabled: Bool {
        get { config.isCmdQEnabled } set { config.isCmdQEnabled = newValue }
    }

    var isCmdMEnabled: Bool {
        get { config.isCmdMEnabled } set { config.isCmdMEnabled = newValue }
    }

    var isCmdHEnabled: Bool {
        get { config.isCmdHEnabled } set { config.isCmdHEnabled = newValue }
    }

    var isCmdFEnabled: Bool {
        get { config.isCmdFEnabled } set { config.isCmdFEnabled = newValue }
    }

    var isCmdSpaceEnabled: Bool {
        get { config.isCmdSpaceEnabled } set { config.isCmdSpaceEnabled = newValue }
    }

    var isTabShortcutsEnabled: Bool {
        get { config.isTabShortcutsEnabled } set { config.isTabShortcutsEnabled = newValue }
    }

    var isCmdTEnabled: Bool {
        get { config.isCmdTEnabled } set { config.isCmdTEnabled = newValue }
    }

    var isCmdNEnabled: Bool {
        get { config.isCmdNEnabled } set { config.isCmdNEnabled = newValue }
    }

    var isCmdShiftTEnabled: Bool {
        get { config.isCmdShiftTEnabled } set { config.isCmdShiftTEnabled = newValue }
    }

    var isFillScreenEnabled: Bool {
        get { config.isFillScreenEnabled } set { config.isFillScreenEnabled = newValue }
    }

    var isAlmostMaximizeEnabled: Bool {
        get { config.isAlmostMaximizeEnabled } set { config.isAlmostMaximizeEnabled = newValue }
    }

    var isReasonableSizeEnabled: Bool {
        get { config.isReasonableSizeEnabled } set { config.isReasonableSizeEnabled = newValue }
    }

    var isMakeLargerEnabled: Bool {
        get { config.isMakeLargerEnabled } set { config.isMakeLargerEnabled = newValue }
    }

    var isMakeSmallerEnabled: Bool {
        get { config.isMakeSmallerEnabled } set { config.isMakeSmallerEnabled = newValue }
    }

    var isMoveNextDesktopEnabled: Bool {
        get { config.isMoveNextDesktopEnabled } set { config.isMoveNextDesktopEnabled = newValue }
    }

    var isMovePreviousDesktopEnabled: Bool {
        get { config.isMovePreviousDesktopEnabled } set { config.isMovePreviousDesktopEnabled = newValue }
    }

    var isAutoEjectEnabled: Bool {
        get { config.isAutoEjectEnabled } set { config.isAutoEjectEnabled = newValue }
    }

    var isQuitAppIfNoWindowsEnabled: Bool {
        get { config.isQuitAppIfNoWindowsEnabled } set { config.isQuitAppIfNoWindowsEnabled = newValue }
    }

    var isDockActionsOutsideMCEnabled: Bool {
        get { config.isDockActionsOutsideMCEnabled }
        set {
            config.isDockActionsOutsideMCEnabled = newValue
            syncServiceLifecycles()
        }
    }

    var isTitleBarActionsOutsideMCEnabled: Bool {
        get { config.isTitleBarActionsOutsideMCEnabled } set { config.isTitleBarActionsOutsideMCEnabled = newValue }
    }

    var isGesturesEnabled: Bool {
        get { config.isGesturesEnabled }
        set {
            config.isGesturesEnabled = newValue
            syncServiceLifecycles()
        }
    }

    var isPinchInEnabled: Bool {
        get { config.isPinchInEnabled } set { config.isPinchInEnabled = newValue }
    }

    var isPinchOutEnabled: Bool {
        get { config.isPinchOutEnabled } set { config.isPinchOutEnabled = newValue }
    }

    var isSwipeLeftEnabled: Bool {
        get { config.isSwipeLeftEnabled } set { config.isSwipeLeftEnabled = newValue }
    }

    var isSwipeRightEnabled: Bool {
        get { config.isSwipeRightEnabled } set { config.isSwipeRightEnabled = newValue }
    }

    var isSwipeDownEnabled: Bool {
        get { config.isSwipeDownEnabled } set { config.isSwipeDownEnabled = newValue }
    }

    var isSwipeUpEnabled: Bool {
        get { config.isSwipeUpEnabled } set { config.isSwipeUpEnabled = newValue }
    }

    var isTwoFingerDoubleTapEnabled: Bool {
        get { config.isTwoFingerDoubleTapEnabled } set { config.isTwoFingerDoubleTapEnabled = newValue }
    }

    var isKeyboardNavigationEnabled: Bool {
        get { config.isKeyboardNavigationEnabled } set { config.isKeyboardNavigationEnabled = newValue }
    }

    var isHapticFeedbackEnabled: Bool {
        get { config.isHapticFeedbackEnabled } set { config.isHapticFeedbackEnabled = newValue }
    }

    var isCursorFeedbackEnabled: Bool {
        get { config.isCursorFeedbackEnabled } set { config.isCursorFeedbackEnabled = newValue }
    }

    var isOptimizedAnimationModeEnabled: Bool {
        get { config.isOptimizedAnimationModeEnabled }
        set { config.isOptimizedAnimationModeEnabled = newValue }
    }

    /// Gesture action mappings
    func gestureAction(for kind: GestureKind, isCmd: Bool) -> GestureAction {
        config.action(for: kind, isCmd: isCmd)
    }

    func setGestureAction(_ action: GestureAction, for kind: GestureKind, isCmd: Bool) {
        config.setAction(
            action,
            for: kind,
            isCmd: isCmd
        )
    }

    func resetGestureMappings() {
        config.resetGestureMappings()
    }

    var isHoverCloseButtonEnabled: Bool {
        get { hoverService.isEnabled }
        set {
            hoverService.isEnabled = newValue
            syncServiceLifecycles()
        }
    }

    /// Prevents gestures from firing right after Mission Control opens via 3-finger swipe.
    private var isCoolingDown = false
    /// Throttles `MultitouchService` 60-120 Hz frames to at most 30 Hz so
    /// `isMissionControlActive` / `isDockHovered()` (both WindowServer/AX IPC)
    /// do not run per-frame. Keeps gesture latency <33ms.
    private var lastGestureFrameTime: Double = 0
    private let gestureFrameInterval: Double = 1.0 / 30.0

    var isLaunchAtLoginEnabled: Bool {
        launchAtLoginService.isEnabled
    }

    init(eventTapService: EventTapServiceProtocol,
         accessibilityService: AccessibilityServiceProtocol,
         missionControlService: MissionControlServiceProtocol,
         launchAtLoginService: LaunchAtLoginService) {
        self.eventTapService = eventTapService
        self.accessibilityService = accessibilityService
        self.missionControlService = missionControlService
        self.launchAtLoginService = launchAtLoginService

        setupCallbacks()

        // Cooldown after Mission Control activates to avoid false gesture detection
        missionControlService.onActivated = { [weak self] in
            self?.isCoolingDown = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.isCoolingDown = false
            }
        }
    }

    func toggleLaunchAtLogin() {
        launchAtLoginService.toggle()
    }

    private func setupCallbacks() {
        setupShortcutHandler()
        registerGestureRecognizers()
        setupMultitouchFrameHandler()
        setupGestureResultHandler()
    }

    // EventTapService → ShortcutActionRouter lives in
    // `ShortcutViewModel+EventHandlers.swift`.

    /// Registers every trackpad recognizer with the shared gesture engine.
    private func registerGestureRecognizers() {
        let cmdHeldProvider: () -> Bool = {
            NSEvent.modifierFlags.contains(.command)
        }
        let twoFingerTapRecognizer = TwoFingerDoubleTapRecognizer()
        twoFingerTapRecognizer.isCmdHeld = cmdHeldProvider
        twoFingerTapRecognizer.isEnabled = { [weak self] in self?.config.isTwoFingerDoubleTapEnabled ?? false }
        gestureEngine.register(twoFingerTapRecognizer)

        let pinchInRecognizer = PinchInRecognizer()
        pinchInRecognizer.isCmdHeld = cmdHeldProvider
        pinchInRecognizer.isEnabled = { [weak self] in self?.config.isPinchInEnabled ?? false }
        gestureEngine.register(pinchInRecognizer)

        let pinchOutRecognizer = PinchOutRecognizer()
        pinchOutRecognizer.isCmdHeld = cmdHeldProvider
        pinchOutRecognizer.isEnabled = { [weak self] in self?.config.isPinchOutEnabled ?? false }
        gestureEngine.register(pinchOutRecognizer)

        let swipeLeftRecognizer = TwoFingerSwipeLeftRecognizer()
        swipeLeftRecognizer.isCmdHeld = cmdHeldProvider
        swipeLeftRecognizer.isEnabled = { [weak self] in self?.config.isSwipeLeftEnabled ?? false }
        gestureEngine.register(swipeLeftRecognizer)

        let swipeRightRecognizer = TwoFingerSwipeRightRecognizer()
        swipeRightRecognizer.isCmdHeld = cmdHeldProvider
        swipeRightRecognizer.isEnabled = { [weak self] in self?.config.isSwipeRightEnabled ?? false }
        gestureEngine.register(swipeRightRecognizer)

        let swipeRecognizer = SwipeRecognizer()
        swipeRecognizer.isCmdHeld = cmdHeldProvider
        swipeRecognizer.isEnabled = { [weak self] in
            guard let self else { return false }
            return self.config.isSwipeDownEnabled || self.config.isSwipeUpEnabled
        }
        swipeRecognizer.isSwipeDownEnabled = { [weak self] in self?.config.isSwipeDownEnabled ?? false }
        swipeRecognizer.isSwipeUpEnabled = { [weak self] in self?.config.isSwipeUpEnabled ?? false }
        gestureEngine.register(swipeRecognizer)
    }

    /// MultitouchService → GestureEngine pump. Frames are throttled to 30 Hz
    /// (~33 ms) because the hot path hits WindowServer (`isMissionControlActive`)
    /// and AX IPC (dock / title-bar hover checks).
    private func setupMultitouchFrameHandler() {
        multitouchService.onFrame = { [weak self] touches, timestamp in
            guard let self,
                  self.config.isGesturesEnabled,
                  !self.isCoolingDown else { return }

            // Throttle 60-120 Hz multitouch to 30 Hz (~33ms). Hot path
            // hits WindowServer (`isMissionControlActive`) and AX IPC
            // (dock / title-bar hover checks).
            let now = CACurrentMediaTime()
            guard now - self.lastGestureFrameTime >= self.gestureFrameInterval else { return }
            self.lastGestureFrameTime = now

            let mcActive = self.missionControlService.isMissionControlActive
            let axPoint = self.currentAXMouseLocation()
            let dockHovered = !mcActive
                && self.config.isDockActionsOutsideMCEnabled
                && self.accessibilityService.isDockRegion(at: axPoint)
            let titleBarHovered = !mcActive && !dockHovered
                && self.config.isTitleBarActionsOutsideMCEnabled
                && self.isTitleBarHovered(at: axPoint)

            if dockHovered {
                self.dockSuppressor.isSuppressing = (touches.count >= 2)
            } else if !mcActive {
                self.dockSuppressor.isSuppressing = false
            }

            guard mcActive || dockHovered || titleBarHovered else { return }
            self.gestureEngine.processFrame(touches, timestamp: timestamp)
        }
    }

    // GestureEngine → GestureActionRouter dispatch lives in
    // `ShortcutViewModel+EventHandlers.swift`.

    // MARK: - Target Resolution, App Activation, and Service Lifecycle live

    // in `ShortcutViewModel+TargetResolution.swift` / `+Lifecycle.swift`.

    func start() {
        eventTapService.start()
        missionControlService.start()

        // Only spin up services whose features are actually enabled.
        // This avoids dlopen-ing MultitouchSupport.framework (~60-120 Hz
        // frame stream), creating the hover-close event tap + overlay
        // NSPanel, and installing the dock suppressor tap when none of
        // their toggles are on. Each service is started/stopped on
        // toggle change via syncServiceLifecycles().
        if needsMultitouch {
            multitouchService.start()
        }
        if needsDockSuppressor {
            dockSuppressor.start()
        }
        if isHoverCloseButtonEnabled {
            hoverService.start()
        }
    }

    func stop() {
        eventTapService.stop()
        missionControlService.stop()
        multitouchService.stop()
        hoverService.stop()
        dockSuppressor.stop()
        gestureEngine.reset()
        cursorFeedback.hide()
    }
}
