import Cocoa

enum TargetResolution {
    case dock(NSRunningApplication)
    case window(AXUIElement)
    case none
}

enum ResolvedShortcutAction {
    case consumeAndExecute(feedbackMode: CursorFeedbackOverlay.Mode, action: () -> Void)
    case ignore
}

/// Routes keyboard shortcut events (e.g. Cmd+W, Cmd+Q, Cmd+M, Cmd+H) to their
/// corresponding actions based on current configuration and target resolution.
final class ShortcutActionRouter {
    static let kKeyW: Int64 = 13
    static let kKeyQ: Int64 = 12
    static let kKeyM: Int64 = 46
    static let kKeyH: Int64 = 4
    static let kKeyF: Int64 = 3
    static let kKeyT: Int64 = 17
    static let kKeyN: Int64 = 45
    static let kKeySpace: Int64 = 49
    // Window & Tab — additional shortcuts (off by default, gesture-only previously)
    static let kKeyE: Int64 = 14 // Close Window — ⌘+Shift+E
    static let kKeyD: Int64 = 2 // Fill Screen — ⌘+Shift+D
    static let kKeyA: Int64 = 0 // Almost Maximize — ⌘+Shift+A
    static let kKeyR: Int64 = 15 // Reasonable Size — ⌘+Shift+R
    static let kKeyL: Int64 = 37 // Make Larger — ⌘+Shift+L
    static let kKeyS: Int64 = 1 // Make Smaller — ⌘+Shift+S
    static let kKeyRight: Int64 = 124 // Move Next Desktop — ⌘+Shift+→
    static let kKeyLeft: Int64 = 123 // Move Previous Desktop — ⌘+Shift+←

    private let actions: ActionRegistry

    /// The complete set of virtual key codes any routable shortcut can use.
    /// Union of every `kKey*` constant above — Cmd+Space is handled by
    /// `MissionControlService` before routing but included so the predicate
    /// stays conservative.
    static let handledKeyCodes: Set<Int64> = [
        kKeyW, kKeyQ, kKeyM, kKeyH, kKeyF, kKeyT, kKeyN, kKeySpace,
        kKeyE, kKeyD, kKeyA, kKeyR, kKeyL, kKeyS, kKeyRight, kKeyLeft
    ]

    /// Cheap, allocation-free predicate answering "could this event possibly
    /// route to any action?". Mirrors `shouldHandle(flags:)` plus the fixed
    /// key-code switch, so a negative answer guarantees `.ignore`.
    ///
    /// Used by `ShortcutViewModel` *before* the expensive AX hit-test
    /// (`resolveTarget`) so plain typing (no Cmd) and untracked keys never pay
    /// for WindowServer/app AX IPC. Must stay in sync with `routeShortcut`:
    /// - flags need Command, without Control or Option,
    /// - key code must be one of the routed constants.
    static func isShortcutCandidate(keyCode: Int64, flags: CGEventFlags) -> Bool {
        guard flags.contains(.maskCommand),
              !flags.contains(.maskControl),
              !flags.contains(.maskAlternate) else {
            return false
        }
        return handledKeyCodes.contains(keyCode)
    }

    init(actions: ActionRegistry = ActionRegistry()) {
        self.actions = actions
    }

    // The parameter list mirrors the full routing context of a key event;
    // bundling it into a struct would touch 20+ test call sites for no
    // behavioral gain, so the count rule is waived here deliberately.
    // swiftlint:disable:next function_parameter_count
    func routeShortcut(
        keyCode: Int64,
        flags: CGEventFlags,
        location: CGPoint,
        config: ShortcutConfiguration,
        isMissionControlActive: Bool,
        target: TargetResolution,
        service: AccessibilityServiceProtocol,
        volumeService: MountedVolumeServiceProtocol? = nil,
        isTitleBarHover: Bool = false,
        activateApp: @escaping (CGPoint) -> Void
    ) -> ResolvedShortcutAction {
        guard shouldHandle(flags: flags) else { return .ignore }
        guard isActive(
            isMissionControlActive: isMissionControlActive,
            target: target,
            config: config,
            isTitleBarHover: isTitleBarHover
        ) else {
            return .ignore
        }
        let app = resolveApp(from: target)
        let isShiftPressed = flags.contains(.maskShift)
        if isShiftPressed {
            if let action = routeShiftShortcut(
                keyCode: keyCode, config: config, target: target,
                service: service, location: location, app: app
            ) {
                return action
            }
        } else {
            if let action = routeEjectIfNeeded(
                keyCode: keyCode, config: config, target: target,
                service: service, volumeService: volumeService
            ) {
                return action
            }
            if let action = routePureCmdShortcut(
                keyCode: keyCode, config: config, service: service,
                location: location, app: app, activateApp: activateApp
            ) {
                return action
            }
        }
        return .ignore
    }
}

// MARK: - Routing internals

/// Same-file extension: SwiftLint's `type_body_length` measures only the main
/// declaration body, and `private` members remain visible to extensions within
/// this file, so the routing internals live here without widening access.
private extension ShortcutActionRouter {
    func shouldHandle(flags: CGEventFlags) -> Bool {
        flags.contains(.maskCommand)
            && !flags.contains(.maskControl)
            && !flags.contains(.maskAlternate)
    }

    private func isActive(
        isMissionControlActive: Bool,
        target: TargetResolution,
        config: ShortcutConfiguration,
        isTitleBarHover: Bool = false
    ) -> Bool {
        if isMissionControlActive {
            return true
        }
        if case .dock = target {
            return config.isDockActionsOutsideMCEnabled
        }
        if isTitleBarHover {
            return config.isTitleBarActionsOutsideMCEnabled
        }
        return false
    }

    private func resolveApp(from target: TargetResolution) -> NSRunningApplication? {
        if case let .dock(app) = target {
            return app
        }
        return nil
    }

    private func routeEjectIfNeeded(
        keyCode: Int64,
        config: ShortcutConfiguration,
        target: TargetResolution,
        service: AccessibilityServiceProtocol,
        volumeService: MountedVolumeServiceProtocol?
    ) -> ResolvedShortcutAction? {
        guard config.isAutoEjectEnabled,
              case let .window(window) = target,
              let volumeService,
              (keyCode == Self.kKeyW && config.isCmdWEnabled)
              || (keyCode == Self.kKeyQ && config.isCmdQEnabled),
              let targetApp = service.getAppFromElement(window),
              targetApp.bundleIdentifier == "com.apple.finder",
              let mountPath = volumeService.ejectableVolumePath(
                  forDocumentPath: service.getDocumentPath(for: window),
                  windowTitle: service.getWindowTitle(for: window)
              )
        else { return nil }
        return .consumeAndExecute(feedbackMode: .eject) { [weak self] in
            guard let self else { return }
            self.actions.ejectVolumeAction.perform(
                window: window, mountPath: mountPath, service: service, volumeService: volumeService
            )
        }
    }

    /// Complexity note: the switch is split across `routePureCmdCoreShortcuts`
    /// (W/Q/M/H) and `routePureCmdWindowShortcuts` (F/T/N) to keep each
    /// function's cyclomatic complexity under the SwiftLint budget.
    func routePureCmdShortcut(
        keyCode: Int64,
        config: ShortcutConfiguration,
        service: AccessibilityServiceProtocol,
        location: CGPoint,
        app: NSRunningApplication?,
        activateApp: @escaping (CGPoint) -> Void
    ) -> ResolvedShortcutAction? {
        if let action = routePureCmdCoreShortcuts(
            keyCode: keyCode, config: config, service: service,
            location: location, app: app, activateApp: activateApp
        ) {
            return action
        }
        return routePureCmdWindowShortcuts(
            keyCode: keyCode, config: config, service: service,
            location: location, app: app
        )
    }

    func routePureCmdCoreShortcuts(
        keyCode: Int64,
        config: ShortcutConfiguration,
        service: AccessibilityServiceProtocol,
        location: CGPoint,
        app: NSRunningApplication?,
        activateApp: @escaping (CGPoint) -> Void
    ) -> ResolvedShortcutAction? {
        switch (keyCode, config) {
        case (Self.kKeyW, _) where config.isCmdWEnabled:
            .consumeAndExecute(feedbackMode: .close) { [weak self] in
                guard let self else { return }
                activateApp(location)
                if let app {
                    self.actions.closeTabAppAction.perform(app: app, service: service)
                } else {
                    self.actions.closeTabAction.perform(at: location, service: service)
                }
            }
        case (Self.kKeyQ, _) where config.isCmdQEnabled:
            .consumeAndExecute(feedbackMode: .quit) { [weak self] in
                guard let self else { return }
                if let app {
                    self.actions.forceQuitAppAction.perform(app: app)
                } else {
                    self.actions.forceQuitAction.perform(at: location, service: service)
                }
            }
        case (Self.kKeyM, _) where config.isCmdMEnabled:
            .consumeAndExecute(feedbackMode: .minimize) { [weak self] in
                guard let self else { return }
                if let app {
                    self.actions.minimizeAppAction.perform(app: app, service: service)
                } else {
                    self.actions.minimizeAction.perform(at: location, service: service)
                }
            }
        case (Self.kKeyH, _) where config.isCmdHEnabled:
            .consumeAndExecute(feedbackMode: .hide) { [weak self] in
                guard let self else { return }
                if let app {
                    app.hide()
                } else {
                    self.actions.hideAction.perform(at: location, service: service)
                }
            }
        default:
            nil
        }
    }

    func routePureCmdWindowShortcuts(
        keyCode: Int64,
        config: ShortcutConfiguration,
        service: AccessibilityServiceProtocol,
        location: CGPoint,
        app: NSRunningApplication?
    ) -> ResolvedShortcutAction? {
        switch (keyCode, config) {
        case (Self.kKeyF, _) where config.isCmdFEnabled:
            return .consumeAndExecute(feedbackMode: .fullscreen) { [weak self] in
                guard let self else { return }
                if let app {
                    self.actions.toggleFullscreenAppAction.perform(app: app, service: service)
                } else {
                    self.actions.toggleFullscreenAction.perform(at: location, service: service)
                }
            }
        case (Self.kKeyT, _) where config.isCmdTEnabled:
            let mode: CursorFeedbackOverlay.Mode = (app != nil) ? .newWindow : .newTab
            return .consumeAndExecute(feedbackMode: mode) { [weak self] in
                guard let self else { return }
                if app != nil {
                    self.actions.newWindowAction.perform(at: location, service: service)
                } else {
                    self.actions.newTabAction.perform(at: location, service: service)
                }
            }
        case (Self.kKeyN, _) where config.isCmdNEnabled:
            return .consumeAndExecute(feedbackMode: .newWindow) { [weak self] in
                guard let self else { return }
                self.actions.newWindowAction.perform(at: location, service: service)
            }
        default:
            return nil
        }
    }

    private func routeShiftShortcut(
        keyCode: Int64,
        config: ShortcutConfiguration,
        target _: TargetResolution,
        service: AccessibilityServiceProtocol,
        location: CGPoint,
        app: NSRunningApplication?
    ) -> ResolvedShortcutAction? {
        if let action = routeShiftTabActions(
            keyCode: keyCode, config: config, service: service, location: location, app: app
        ) {
            return action
        }
        if let action = routeShiftWindowSizeActions(
            keyCode: keyCode, config: config, service: service, location: location, app: app
        ) {
            return action
        }
        if let action = routeShiftDesktopActions(
            keyCode: keyCode, config: config, service: service, location: location, app: app
        ) {
            return action
        }
        return nil
    }

    private func routeShiftTabActions(
        keyCode: Int64,
        config: ShortcutConfiguration,
        service: AccessibilityServiceProtocol,
        location: CGPoint,
        app: NSRunningApplication?
    ) -> ResolvedShortcutAction? {
        switch keyCode {
        case Self.kKeyW where config.isCmdShiftWEnabled:
            .consumeAndExecute(feedbackMode: .closeAllTabs) { [weak self] in
                guard let self else { return }
                self.actions.closeAllTabsAction.perform(at: location, service: service)
            }
        case Self.kKeyT where config.isCmdShiftTEnabled:
            .consumeAndExecute(feedbackMode: .reopenTab) { [weak self] in
                guard let self else { return }
                if let app {
                    self.actions.reopenTabAppAction.perform(app: app)
                } else {
                    self.actions.reopenTabAction.perform(at: location, service: service)
                }
            }
        case Self.kKeyE where config.isCloseWindowEnabled:
            .consumeAndExecute(feedbackMode: .close) { [weak self] in
                guard let self else { return }
                if let app {
                    self.actions.closeAppAction.perform(app: app, service: service)
                } else {
                    self.actions.closeAction.perform(at: location, service: service)
                }
            }
        default:
            nil
        }
    }

    /// Complexity note: split across `routeShiftFillActions` (D/A) and
    /// `routeShiftResizeActions` (R/L/S) to keep each function's cyclomatic
    /// complexity under the SwiftLint budget.
    func routeShiftWindowSizeActions(
        keyCode: Int64,
        config: ShortcutConfiguration,
        service: AccessibilityServiceProtocol,
        location: CGPoint,
        app: NSRunningApplication?
    ) -> ResolvedShortcutAction? {
        if let action = routeShiftFillActions(
            keyCode: keyCode, config: config, service: service, location: location, app: app
        ) {
            return action
        }
        return routeShiftResizeActions(
            keyCode: keyCode, config: config, service: service, location: location, app: app
        )
    }

    func routeShiftFillActions(
        keyCode: Int64,
        config: ShortcutConfiguration,
        service: AccessibilityServiceProtocol,
        location: CGPoint,
        app: NSRunningApplication?
    ) -> ResolvedShortcutAction? {
        switch keyCode {
        case Self.kKeyD where config.isFillScreenEnabled:
            .consumeAndExecute(feedbackMode: .maximize) { [weak self] in
                guard let self else { return }
                if let app {
                    self.actions.fillScreenAppAction.perform(app: app, service: service)
                } else {
                    self.actions.fillScreenAction.perform(at: location, service: service)
                }
            }
        case Self.kKeyA where config.isAlmostMaximizeEnabled:
            .consumeAndExecute(feedbackMode: .almost) { [weak self] in
                guard let self else { return }
                if let app {
                    self.actions.almostMaximizeAppAction.perform(app: app, service: service)
                } else {
                    self.actions.almostMaximizeAction.perform(at: location, service: service)
                }
            }
        default:
            nil
        }
    }

    func routeShiftResizeActions(
        keyCode: Int64,
        config: ShortcutConfiguration,
        service: AccessibilityServiceProtocol,
        location: CGPoint,
        app: NSRunningApplication?
    ) -> ResolvedShortcutAction? {
        switch keyCode {
        case Self.kKeyR where config.isReasonableSizeEnabled:
            .consumeAndExecute(feedbackMode: .reasonable) { [weak self] in
                guard let self else { return }
                if let app {
                    self.actions.reasonableSizeAppAction.perform(app: app, service: service)
                } else {
                    self.actions.reasonableSizeAction.perform(at: location, service: service)
                }
            }
        case Self.kKeyL where config.isMakeLargerEnabled:
            .consumeAndExecute(feedbackMode: .maximize) { [weak self] in
                guard let self else { return }
                if let app {
                    self.actions.makeLargerAppAction.perform(app: app, service: service)
                } else {
                    self.actions.makeLargerAction.perform(at: location, service: service)
                }
            }
        case Self.kKeyS where config.isMakeSmallerEnabled:
            .consumeAndExecute(feedbackMode: .makeSmaller) { [weak self] in
                guard let self else { return }
                if let app {
                    self.actions.makeSmallerAppAction.perform(app: app, service: service)
                } else {
                    self.actions.makeSmallerAction.perform(at: location, service: service)
                }
            }
        default:
            nil
        }
    }

    private func routeShiftDesktopActions(
        keyCode: Int64,
        config: ShortcutConfiguration,
        service: AccessibilityServiceProtocol,
        location: CGPoint,
        app: NSRunningApplication?
    ) -> ResolvedShortcutAction? {
        switch keyCode {
        case Self.kKeyRight where config.isMoveNextDesktopEnabled:
            .consumeAndExecute(feedbackMode: .spaceRight) { [weak self] in
                guard let self else { return }
                if let app {
                    self.actions.moveNextDesktopAction.perform(app: app, service: service)
                } else {
                    self.actions.moveNextDesktopAction.perform(at: location, service: service)
                }
            }
        case Self.kKeyLeft where config.isMovePreviousDesktopEnabled:
            .consumeAndExecute(feedbackMode: .spaceLeft) { [weak self] in
                guard let self else { return }
                if let app {
                    self.actions.movePreviousDesktopAction.perform(app: app, service: service)
                } else {
                    self.actions.movePreviousDesktopAction.perform(at: location, service: service)
                }
            }
        default:
            nil
        }
    }
}
