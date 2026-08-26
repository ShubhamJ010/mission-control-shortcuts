import Cocoa

/// Event-tap callback wiring for `ShortcutViewModel`: the keyboard shortcut
/// path (EventTapService to ShortcutActionRouter) and the recognized-gesture
/// dispatch path (GestureEngine to GestureActionRouter). Split from the main
/// file to stay under the SwiftLint file_length budget.
@MainActor
extension ShortcutViewModel {
    func setupShortcutHandler() {
        eventTapService.onShortcutDetected = { [weak self] keyCode, flags, location in
            guard let self else { return false }

            // Cheap pre-filter BEFORE any AX IPC: plain typing (no Cmd) and
            // unbound keys can never route, so skip the hit-test entirely.
            // This keeps keystroke latency in other apps free of MCSC cost.
            guard ShortcutActionRouter.isShortcutCandidate(
                keyCode: keyCode,
                flags: flags,
                boundKeyCodes: self.config.boundKeyCodes
            ) else {
                return false
            }

            let isCmdPressed = flags.contains(.maskCommand)
            let isShiftPressed = flags.contains(.maskShift)
            let isControlPressed = flags.contains(.maskControl)
            let isOptionPressed = flags.contains(.maskAlternate)

            if isCmdPressed && !isShiftPressed && !isControlPressed && !isOptionPressed {
                if keyCode == ShortcutActionRouter.kKeySpace, self.config.isCmdSpaceEnabled,
                   !self.missionControlService.isSimulating {
                    if self.missionControlService.checkMissionControlActive() {
                        self.missionControlService.executeFixSequence()
                        return true
                    }
                }
            }

            let effectiveLocation = (location == .zero) ? self.currentAXMouseLocation() : location
            let target = self.resolveTarget(at: effectiveLocation)
            // Pure hover fact only — whether the toggle admits it is the
            // router's decision (`ShortcutActionRouter.isActive`). The MC
            // guard just skips needless AX IPC; the router admits everything
            // while Mission Control is open anyway.
            var isTitleBarHover = false
            if case let .window(window) = target, !self.missionControlService.isMissionControlActive {
                isTitleBarHover = self.isTitleBarHover(window: window, at: effectiveLocation)
            }
            let resolution = self.shortcutRouter.routeShortcut(
                keyCode: keyCode,
                flags: flags,
                location: effectiveLocation,
                config: self.config,
                isMissionControlActive: self.missionControlService.isMissionControlActive,
                target: target,
                service: self.accessibilityService,
                volumeService: self.volumeService,
                isTitleBarHover: isTitleBarHover,
                activateApp: { [weak self] loc in self?.activateAppIfNeeded(at: loc) }
            )

            switch resolution {
            case let .consumeAndExecute(feedbackMode, action):
                self.executeFeedbackThenAction(
                    at: effectiveLocation,
                    feedbackMode: feedbackMode,
                    haptic: nil,
                    action: action
                )
                return true
            case .ignore:
                return false
            }
        }
    }

    // Registers every trackpad recognizer with the shared gesture engine.
    // Each recognizer consults `config` at frame time so settings toggles
    // apply live without re-registration.

    func setupGestureResultHandler() {
        gestureEngine.onGestureRecognized = { [weak self] result in
            guard let self else { return }
            self.holdDetector.reset()
            self.handleGestureResult(result)
        }
    }

    func handleGestureResult(_ result: GestureResult) {
        let axPoint = currentAXMouseLocation()
        let target = resolveTarget(at: axPoint)
        let resolution = gestureRouter.routeGesture(
            result,
            at: axPoint,
            target: target,
            service: accessibilityService,
            volumeService: volumeService,
            isAutoEjectEnabled: config.isAutoEjectEnabled,
            config: config,
            activateApp: { [weak self] loc in self?.activateAppIfNeeded(at: loc) }
        )

        switch resolution {
        case let .execute(feedbackMode, haptic, action):
            if !missionControlService.isMissionControlActive, config.isDockActionsOutsideMCEnabled {
                dockSuppressor.isSuppressing = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    self?.dockSuppressor.isSuppressing = false
                }
            }
            executeFeedbackThenAction(at: axPoint, feedbackMode: feedbackMode, haptic: haptic, action: action)
        case .none:
            break
        }
    }

    /// Shows feedback + fires haptic, then defers the action one run-loop turn
    /// so the feedback panel composites before the blocking AX call starves
    /// the run loop.
    func executeFeedbackThenAction(
        at point: CGPoint,
        feedbackMode: CursorFeedbackOverlay.Mode,
        haptic: HapticType?,
        action: @escaping () -> Void
    ) {
        if config.isCursorFeedbackEnabled {
            cursorFeedback.show(at: point, mode: feedbackMode)
        }
        if let haptic, config.isHapticFeedbackEnabled {
            HapticService.perform(haptic)
        }
        DispatchQueue.main.async { [weak self] in
            // Teardown-safety gate: cancels deferred execution if VM is deallocated before the turn fires
            guard self != nil else { return }
            action()
        }
    }
}
