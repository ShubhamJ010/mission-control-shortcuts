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
    static let kKeyD: Int64 = 2 // Fill Screen — ⌘+Shift+D
    static let kKeyA: Int64 = 0 // Almost Maximize — ⌘+Shift+A
    static let kKeyR: Int64 = 15 // Reasonable Size — ⌘+Shift+R
    static let kKeyL: Int64 = 37 // Make Larger — ⌘+Shift+L
    static let kKeyS: Int64 = 1 // Make Smaller — ⌘+Shift+S
    static let kKeyRight: Int64 = 124 // Move Next Desktop — ⌘+Shift+→
    static let kKeyLeft: Int64 = 123 // Move Previous Desktop — ⌘+Shift+←

    private let actions: ActionRegistry

    /// Cheap, allocation-free predicate answering "could this event possibly
    /// route to any action?". Mirrors `shouldHandle(flags:)`, so a negative
    /// answer guarantees `.ignore`.
    ///
    /// Used by `ShortcutViewModel` *before* the expensive AX hit-test
    /// (`resolveTarget`) so plain typing (no Cmd) and unbound keys never pay
    /// for WindowServer/app AX IPC. Must stay in sync with `routeShortcut`:
    /// - flags need Command, without Control or Option,
    /// - key code must be bound to some action (⌘Space is always admitted;
    ///   its fixed handling lives in `MissionControlService`).
    static func isShortcutCandidate(
        keyCode: Int64,
        flags: CGEventFlags,
        boundKeyCodes: Set<Int64> = []
    ) -> Bool {
        guard flags.contains(.maskCommand),
              !flags.contains(.maskControl),
              !flags.contains(.maskAlternate) else {
            return false
        }
        return keyCode == kKeySpace || boundKeyCodes.contains(keyCode)
    }

    init(actions: ActionRegistry = ActionRegistry()) {
        self.actions = actions
    }

    // The parameter list mirrors the full routing context of a key event;
    // bundling it into a struct would touch 20+ test call sites for no
    // behavioral gain, so the count rule is waived here deliberately.
    // swiftlint:disable:next function_parameter_count
    func routeShortcut(
        keyCode: Int64, flags: CGEventFlags, location: CGPoint,
        config: ShortcutConfiguration, isMissionControlActive: Bool,
        target: TargetResolution, service: AccessibilityServiceProtocol,
        volumeService: MountedVolumeServiceProtocol? = nil,
        isTitleBarHover: Bool = false, activateApp: @escaping (CGPoint) -> Void
    ) -> ResolvedShortcutAction {
        guard shouldHandle(flags: flags) else { return .ignore }
        let includesShift = flags.contains(.maskShift)
        // Binding-table match: which configured actions claim this exact
        // combination? Empty ⇒ nothing to do, skip the AX work entirely.
        let matched = config.matchedActions(keyCode: keyCode, includesShift: includesShift)
        guard !matched.isEmpty else { return .ignore }
        guard isActive(isMissionControlActive: isMissionControlActive, target: target,
                       config: config, isTitleBarHover: isTitleBarHover) else {
            return .ignore
        }
        let app = resolveApp(from: target)
        if includesShift {
            if let action = routeShiftShortcut(
                matched: matched, config: config, target: target,
                service: service, location: location, app: app
            ) {
                return action
            }
        } else {
            if let action = routeEjectIfNeeded(
                matched: matched, config: config, target: target,
                service: service, volumeService: volumeService
            ) {
                return action
            }
            if let action = routePureCmdShortcut(
                matched: matched, config: config, service: service,
                location: location, app: app, activateApp: activateApp
            ) {
                return action
            }
        }
        return .ignore
    }
}

// MARK: - Routing internals

private extension ShortcutActionRouter {
    func shouldHandle(flags: CGEventFlags) -> Bool {
        flags.contains(.maskCommand) && !flags.contains(.maskControl) && !flags.contains(.maskAlternate)
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
        matched: [RoutedAction],
        config: ShortcutConfiguration,
        target: TargetResolution,
        service: AccessibilityServiceProtocol,
        volumeService: MountedVolumeServiceProtocol?
    ) -> ResolvedShortcutAction? {
        guard config.isAutoEjectEnabled,
              case let .window(window) = target,
              let volumeService,
              matched.contains(.close) || matched.contains(.quit),
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

    /// Complexity note: the dispatch is split across `routePureCmdCoreShortcuts`
    /// (close/quit/minimize/hide) and `routePureCmdWindowShortcuts`
    /// (fullscreen/new tab/new window) to keep each function's cyclomatic
    /// complexity under the SwiftLint budget. `matched` arrives in
    /// `RoutedAction.routeOrder` precedence.
    func routePureCmdShortcut(
        matched: [RoutedAction],
        config: ShortcutConfiguration,
        service: AccessibilityServiceProtocol,
        location: CGPoint,
        app: NSRunningApplication?,
        activateApp: @escaping (CGPoint) -> Void
    ) -> ResolvedShortcutAction? {
        if let action = routePureCmdCoreShortcuts(
            matched: matched, config: config, service: service,
            location: location, app: app, activateApp: activateApp
        ) {
            return action
        }
        return routePureCmdWindowShortcuts(
            matched: matched, config: config, service: service,
            location: location, app: app
        )
    }

    func routePureCmdCoreShortcuts(
        matched: [RoutedAction],
        config: ShortcutConfiguration,
        service: AccessibilityServiceProtocol,
        location: CGPoint,
        app: NSRunningApplication?,
        activateApp: @escaping (CGPoint) -> Void
    ) -> ResolvedShortcutAction? {
        if matched.contains(.close) || matched.contains(.closeTab) {
            return .consumeAndExecute(feedbackMode: .close) { [weak self] in
                guard let self else { return }
                activateApp(location)
                let scope: CloseScope = config.isTabShortcutsEnabled ? .activeTab : .window
                self.actions.close.perform(
                    scope,
                    at: location,
                    fromApp: app,
                    service: service,
                    quitIfNoWindows: config.isQuitAppIfNoWindowsEnabled
                )
            }
        }
        if matched.contains(.quit) {
            return .consumeAndExecute(feedbackMode: .quit) { [weak self] in
                guard let self else { return }
                if let app {
                    self.actions.forceQuitAppAction.perform(app: app)
                } else {
                    self.actions.forceQuitAction.perform(at: location, service: service)
                }
            }
        }
        if matched.contains(.minimize) {
            return .consumeAndExecute(feedbackMode: .minimize) { [weak self] in
                guard let self else { return }
                if let app {
                    self.actions.minimizeAppAction.perform(app: app, service: service)
                } else {
                    self.actions.minimizeAction.perform(at: location, service: service)
                }
            }
        }
        if matched.contains(.hide) {
            return .consumeAndExecute(feedbackMode: .hide) { [weak self] in
                guard let self else { return }
                if let app {
                    app.hide()
                } else {
                    self.actions.hideAction.perform(at: location, service: service)
                }
            }
        }
        return nil
    }

    func routePureCmdWindowShortcuts(
        matched: [RoutedAction],
        config _: ShortcutConfiguration,
        service: AccessibilityServiceProtocol,
        location: CGPoint,
        app: NSRunningApplication?
    ) -> ResolvedShortcutAction? {
        if matched.contains(.fullscreen) {
            return .consumeAndExecute(feedbackMode: .fullscreen) { [weak self] in
                guard let self else { return }
                if let app {
                    self.actions.toggleFullscreenAppAction.perform(app: app, service: service)
                } else {
                    self.actions.toggleFullscreenAction.perform(at: location, service: service)
                }
            }
        }
        if matched.contains(.newTab) {
            let mode: CursorFeedbackOverlay.Mode = (app != nil) ? .newWindow : .newTab
            return .consumeAndExecute(feedbackMode: mode) { [weak self] in
                guard let self else { return }
                if app != nil {
                    self.actions.newWindowAction.perform(at: location, service: service)
                } else {
                    self.actions.newTabAction.perform(at: location, service: service)
                }
            }
        }
        if matched.contains(.newWindow) {
            return .consumeAndExecute(feedbackMode: .newWindow) { [weak self] in
                guard let self else { return }
                self.actions.newWindowAction.perform(at: location, service: service)
            }
        }
        return nil
    }

    private func routeShiftShortcut(
        matched: [RoutedAction],
        config: ShortcutConfiguration,
        target: TargetResolution,
        service: AccessibilityServiceProtocol,
        location: CGPoint,
        app: NSRunningApplication?
    ) -> ResolvedShortcutAction? {
        if let action = routeShiftTabActions(
            matched: matched, config: config, service: service, location: location, app: app
        ) { return action }
        if let action = routeShiftAppGroupActions(
            matched: matched, config: config, target: target, service: service, location: location, app: app
        ) { return action }
        if let action = routeShiftWindowSizeActions(
            matched: matched, config: config, service: service, location: location, app: app
        ) { return action }
        if let action = routeShiftDesktopActions(
            matched: matched, config: config, service: service, location: location, app: app
        ) { return action }
        return nil
    }

    private func routeShiftTabActions(
        matched: [RoutedAction],
        config: ShortcutConfiguration,
        service: AccessibilityServiceProtocol,
        location: CGPoint,
        app: NSRunningApplication?
    ) -> ResolvedShortcutAction? {
        if matched.contains(.closeAllTabs) {
            return .consumeAndExecute(feedbackMode: .closeAllTabs) { [weak self] in
                guard let self else { return }
                self.actions.close.perform(
                    .allTabs,
                    at: location,
                    fromApp: app,
                    service: service,
                    quitIfNoWindows: config.isQuitAppIfNoWindowsEnabled
                )
            }
        }
        if matched.contains(.reopenTab) {
            return .consumeAndExecute(feedbackMode: .reopenTab) { [weak self] in
                guard let self else { return }
                if let app {
                    self.actions.reopenTabAppAction.perform(app: app)
                } else {
                    self.actions.reopenTabAction.perform(at: location, service: service)
                }
            }
        }
        return nil
    }

    /// Complexity note: split across `routeShiftFillActions` (fill/almost) and
    /// `routeShiftResizeActions` (reasonable/larger/smaller) to keep each
    /// function's cyclomatic complexity under the SwiftLint budget.
    func routeShiftWindowSizeActions(
        matched: [RoutedAction],
        config: ShortcutConfiguration,
        service: AccessibilityServiceProtocol,
        location: CGPoint,
        app: NSRunningApplication?
    ) -> ResolvedShortcutAction? {
        if let action = routeShiftFillActions(
            matched: matched, config: config, service: service, location: location, app: app
        ) {
            return action
        }
        return routeShiftResizeActions(
            matched: matched, config: config, service: service, location: location, app: app
        )
    }

    func routeShiftFillActions(
        matched: [RoutedAction],
        config _: ShortcutConfiguration,
        service: AccessibilityServiceProtocol,
        location: CGPoint,
        app: NSRunningApplication?
    ) -> ResolvedShortcutAction? {
        if matched.contains(.fillScreen) {
            return .consumeAndExecute(feedbackMode: .maximize) { [weak self] in
                guard let self else { return }
                if let app {
                    self.actions.fillScreenAppAction.perform(app: app, service: service)
                } else {
                    self.actions.fillScreenAction.perform(at: location, service: service)
                }
            }
        }
        if matched.contains(.almostMaximize) {
            return .consumeAndExecute(feedbackMode: .almost) { [weak self] in
                guard let self else { return }
                if let app {
                    self.actions.almostMaximizeAppAction.perform(app: app, service: service)
                } else {
                    self.actions.almostMaximizeAction.perform(at: location, service: service)
                }
            }
        }
        return nil
    }

    func routeShiftResizeActions(
        matched: [RoutedAction],
        config _: ShortcutConfiguration,
        service: AccessibilityServiceProtocol,
        location: CGPoint,
        app: NSRunningApplication?
    ) -> ResolvedShortcutAction? {
        if matched.contains(.reasonableSize) {
            return .consumeAndExecute(feedbackMode: .reasonable) { [weak self] in
                guard let self else { return }
                if let app {
                    self.actions.reasonableSizeAppAction.perform(app: app, service: service)
                } else {
                    self.actions.reasonableSizeAction.perform(at: location, service: service)
                }
            }
        }
        if matched.contains(.makeLarger) {
            return .consumeAndExecute(feedbackMode: .maximize) { [weak self] in
                guard let self else { return }
                if let app {
                    self.actions.makeLargerAppAction.perform(app: app, service: service)
                } else {
                    self.actions.makeLargerAction.perform(at: location, service: service)
                }
            }
        }
        if matched.contains(.makeSmaller) {
            return .consumeAndExecute(feedbackMode: .makeSmaller) { [weak self] in
                guard let self else { return }
                if let app {
                    self.actions.makeSmallerAppAction.perform(app: app, service: service)
                } else {
                    self.actions.makeSmallerAction.perform(at: location, service: service)
                }
            }
        }
        return nil
    }

    /// Minimize/Unminimize *all* windows of the hovered app. The target may be
    /// either its Dock icon or any of its windows — both resolve to the owning
    /// application, since the effect is app-wide rather than per-window.
    private func routeShiftAppGroupActions(
        matched: [RoutedAction],
        config _: ShortcutConfiguration,
        target: TargetResolution,
        service: AccessibilityServiceProtocol,
        location _: CGPoint,
        app: NSRunningApplication?
    ) -> ResolvedShortcutAction? {
        if matched.contains(.minimizeAll) {
            return .consumeAndExecute(feedbackMode: .minimizeAll) { [weak self] in
                guard let self,
                      let owner = self.resolveOwnerApp(target: target, app: app, service: service) else { return }
                self.actions.minimizeAllWindowsAction.perform(app: owner, service: service)
            }
        }
        if matched.contains(.unminimizeAll) {
            return .consumeAndExecute(feedbackMode: .unminimizeAll) { [weak self] in
                guard let self,
                      let owner = self.resolveOwnerApp(target: target, app: app, service: service) else { return }
                self.actions.unminimizeAllWindowsAction.perform(app: owner, service: service)
            }
        }
        return nil
    }

    /// Resolves the app an app-wide action should touch: a Dock hit yields the
    /// Dock item's app; a window hover yields the window's owner via PID.
    private func resolveOwnerApp(
        target: TargetResolution,
        app: NSRunningApplication?,
        service: AccessibilityServiceProtocol
    ) -> NSRunningApplication? {
        if let app {
            return app
        }
        if case let .window(window) = target {
            return service.getAppFromElement(window)
        }
        return nil
    }

    private func routeShiftDesktopActions(
        matched: [RoutedAction],
        config _: ShortcutConfiguration,
        service: AccessibilityServiceProtocol,
        location: CGPoint,
        app: NSRunningApplication?
    ) -> ResolvedShortcutAction? {
        if matched.contains(.moveNextDesktop) {
            return .consumeAndExecute(feedbackMode: .spaceRight) { [weak self] in
                guard let self else { return }
                if let app {
                    self.actions.moveNextDesktopAction.perform(app: app, service: service)
                } else {
                    self.actions.moveNextDesktopAction.perform(at: location, service: service)
                }
            }
        }
        if matched.contains(.movePreviousDesktop) {
            return .consumeAndExecute(feedbackMode: .spaceLeft) { [weak self] in
                guard let self else { return }
                if let app {
                    self.actions.movePreviousDesktopAction.perform(app: app, service: service)
                } else {
                    self.actions.movePreviousDesktopAction.perform(at: location, service: service)
                }
            }
        }
        return nil
    }
}
