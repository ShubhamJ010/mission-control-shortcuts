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
    private weak var twoFingerTapRecognizer: TwoFingerDoubleTapRecognizer?
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
        suppressor.onUserClick = { [weak self] in
            guard let self else { return }
            self.holdDetector.cancelForCurrentTouchSession()
            self.cursorFeedback.hide()
            self.twoFingerTapRecognizer?.reset()
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

    var holdDetector = TwoFingerHoldDetector()

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

        holdDetector.config.holdDuration = config.twoFingerHoldDuration
        setupCallbacks()

        // Cooldown after Mission Control activates to avoid false gesture detection, and notify hoverService.
        missionControlService.onActivated = { [weak self] in
            self?.isCoolingDown = true
            self?.hoverService.handleActivated()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.isCoolingDown = false
            }
        }
        missionControlService.onDeactivated = { [weak self] in
            self?.hoverService.handleDeactivated()
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
        let cmdHeldProvider: () -> Bool = { [weak self] in
            guard let self else { return false }
            return NSEvent.modifierFlags.contains(.command)
                || (self.config.isTwoFingerHoldEnabled && self.holdDetector.isHoldActive)
        }
        let twoFingerTapRecognizer = TwoFingerDoubleTapRecognizer()
        twoFingerTapRecognizer.isCmdHeld = cmdHeldProvider
        twoFingerTapRecognizer.isEnabled = { [weak self] in self?.config.isTwoFingerDoubleTapEnabled ?? false }
        twoFingerTapRecognizer.onStateChanged = { [weak self] isInProgress in
            guard let self else { return }
            let mcActive = self.missionControlService.isMissionControlActive
            let axPoint = self.currentAXMouseLocation()
            let dockHovered = self.isDockTargeted(at: axPoint, mcActive: mcActive)

            self.dockSuppressor.isSuppressing = isInProgress && dockHovered
        }
        self.twoFingerTapRecognizer = twoFingerTapRecognizer
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

    private func isDockTargeted(at point: CGPoint, mcActive: Bool) -> Bool {
        !mcActive
            && config.isDockActionsOutsideMCEnabled
            && accessibilityService.isDockRegion(at: point)
    }

    /// MultitouchService → GestureEngine pump. Hot path is streamlined:
    /// - Touch lift (`isEmpty`) and 1-finger frames exit early with zero AX IPC.
    /// - 2+ finger frames are throttled to 30 Hz without per-frame AX title-bar queries.
    /// - Target validation happens once upon gesture completion or hold threshold.
    private func setupMultitouchFrameHandler() {
        multitouchService.onFrame = { [weak self] touches, timestamp in
            guard let self,
                  self.config.isGesturesEnabled,
                  !self.isCoolingDown else { return }

            // Instantly hide Mission Control close overlay on 3+ finger contact (MC swipe down / space switch)
            // Evaluated before throttling so dismissal is immediate.
            if touches.count >= 3 && self.hoverService.isTracking {
                self.hoverService.hideOverlay()
            }

            // Handle touch lift immediately without throttling or AX overhead
            if touches.isEmpty {
                self.holdDetector.handleTouchesEnded(timestamp: timestamp)
                self.gestureEngine.processFrame([], timestamp: timestamp)
                if !(self.twoFingerTapRecognizer?.isGestureInProgress ?? false) {
                    self.dockSuppressor.isSuppressing = false
                }
                return
            }

            // Early exit for 1 finger (normal cursor motion/scroll):
            // notify holdDetector so it aborts any pending/held state, then exit with zero AX IPC.
            guard touches.count >= 2 else {
                self.dockSuppressor.isSuppressing = false
                _ = self.holdDetector.processFrame(touches, timestamp: timestamp)
                return
            }

            // Throttle 60-120 Hz multitouch to 30 Hz (~33ms) for 2+ finger gestures.
            let frameTime = timestamp > 0 ? timestamp : CACurrentMediaTime()
            guard frameTime - self.lastGestureFrameTime >= self.gestureFrameInterval else { return }
            self.lastGestureFrameTime = frameTime

            // Two-finger hold: only validate target region ONCE on activation frame
            if self.config.isTwoFingerHoldEnabled {
                let holdJustActivated = self.holdDetector.processFrame(touches, timestamp: timestamp)
                if holdJustActivated {
                    let mcActive = self.missionControlService.isMissionControlActive
                    let axPoint = self.currentAXMouseLocation()
                    let dockHovered = self.isDockTargeted(at: axPoint, mcActive: mcActive)
                    let titleBarHovered = !mcActive && !dockHovered
                        && self.config.isTitleBarActionsOutsideMCEnabled
                        && self.isTitleBarHovered(at: axPoint)
                    if mcActive || dockHovered || titleBarHovered {
                        AppLogger.gesture.info(
                            "Two-finger hold activated at point (\(axPoint.x, privacy: .public), \(axPoint.y, privacy: .public))"
                        )
                        if self.config.isCursorFeedbackEnabled {
                            self.cursorFeedback.show(at: axPoint, mode: .command)
                        }
                        if self.config.isHapticFeedbackEnabled {
                            HapticService.perform(.twoFingerHold)
                        }
                    } else {
                        // Invalid target region (e.g. empty desktop) - reset hold so Cmd modifier does not stay latched
                        self.holdDetector.reset()
                    }
                }
            }

            // Feed gesture engine directly without per-frame AX title-bar polling.
            // Target region validation happens once upon gesture completion in handleGestureResult.
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
        holdDetector.reset()
        cursorFeedback.hide()
    }
}
