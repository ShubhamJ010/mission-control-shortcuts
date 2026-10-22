import Cocoa

enum TargetResolution {
    case dock(NSRunningApplication)
    case window(AXUIElement)
    case missionControlPreview(windowInfo: [String: Any], windowID: CGWindowID)
    case none
}

enum ResolvedShortcutAction {
    case consumeAndExecute(feedbackMode: CursorFeedbackMode, action: () -> Void)
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

    static func runOnMainActor(_ block: @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { block() }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated { block() }
            }
        }
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
        hoverService: MissionControlHoverServiceProtocol? = nil,
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
        if case .none = target, service.isDockRegion(at: location) {
            return .ignore
        }
        let context = Context(
            location: location,
            app: resolveApp(from: target),
            config: config,
            service: service,
            activateApp: activateApp,
            target: target,
            hoverService: hoverService
        )
        if let action = routeEjectIfNeeded(
            matched: matched, config: config, target: target,
            service: service, volumeService: volumeService
        ) {
            return action
        }
        if let action = routeCoreShortcuts(matched: matched, context: context) {
            return action
        }
        if let action = routeWindowShortcuts(matched: matched, context: context) {
            return action
        }
        if let action = routeTabActions(matched: matched, context: context) {
            return action
        }
        if let action = routeWindowSizeActions(matched: matched, context: context) {
            return action
        }
        if let action = routeDesktopActions(matched: matched, context: context) {
            return action
        }
        if let action = routeAppGroupActions(matched: matched, target: target, context: context) {
            return action
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
        switch target {
        case let .dock(app):
            return app
        case let .missionControlPreview(windowInfo, _):
            if let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t {
                return NSRunningApplication(processIdentifier: pid)
            }
            return nil
        case .window, .none:
            return nil
        }
    }

    struct Context {
        let location: CGPoint
        let app: NSRunningApplication?
        let config: ShortcutConfiguration
        let service: AccessibilityServiceProtocol
        let activateApp: (CGPoint) -> Void
        let target: TargetResolution
        let hoverService: MissionControlHoverServiceProtocol?

        func execute(
            feedbackMode: CursorFeedbackMode,
            needsActivate: Bool = false,
            action: @escaping () -> Void
        ) -> ResolvedShortcutAction {
            .consumeAndExecute(feedbackMode: feedbackMode) {
                if needsActivate {
                    activateApp(location)
                }
                action()
            }
        }
    }

    private func routeEjectIfNeeded(
        matched: [RoutedAction],
        config: ShortcutConfiguration,
        target: TargetResolution,
        service: AccessibilityServiceProtocol,
        volumeService: MountedVolumeServiceProtocol?
    ) -> ResolvedShortcutAction? {
        guard config.isAutoEjectEnabled,
              let volumeService,
              matched.contains(.close) || matched.contains(.quit) else {
            return nil
        }

        switch target {
        case let .window(window):
            guard let targetApp = service.getAppFromElement(window),
                  targetApp.bundleIdentifier == "com.apple.finder",
                  let mountPath = volumeService.ejectableVolumePath(
                      forDocumentPath: service.getDocumentPath(for: window),
                      windowTitle: service.getWindowTitle(for: window)
                  ) else {
                return nil
            }
            return .consumeAndExecute(feedbackMode: .eject) { [weak self] in
                guard let self else { return }
                self.actions.ejectVolumeAction.perform(
                    window: window, mountPath: mountPath, service: service, volumeService: volumeService
                )
            }

        case let .missionControlPreview(windowInfo, _):
            guard let owner = windowInfo[kCGWindowOwnerName as String] as? String,
                  owner == "Finder" else {
                return nil
            }
            let docPath: String?
            let winTitle: String?
            if let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
               let axWin = service.getWindow(forWindowID: windowID) {
                docPath = service.getDocumentPath(for: axWin)
                winTitle = service.getWindowTitle(for: axWin) ?? (windowInfo[kCGWindowName as String] as? String)
            } else {
                docPath = nil
                winTitle = windowInfo[kCGWindowName as String] as? String
            }
            guard let mountPath = volumeService.ejectableVolumePath(
                forDocumentPath: docPath,
                windowTitle: winTitle
            ) else {
                return nil
            }
            return .consumeAndExecute(feedbackMode: .eject) { [weak self] in
                guard let self else { return }
                self.actions.ejectVolumeAction.perform(
                    windowInfo: windowInfo, mountPath: mountPath, service: service, volumeService: volumeService
                )
            }

        case .dock, .none:
            return nil
        }
    }

    private func routeCloseShortcut(
        matched: [RoutedAction],
        context: Context
    ) -> ResolvedShortcutAction? {
        let targetScope: CloseScope
        let feedback: CursorFeedbackMode

        if context.config.isSmartTabCloseEnabled {
            guard matched.contains(.close) || matched.contains(.closeTab) else { return nil }
            targetScope = .smartClose
            feedback = .close
        } else if matched.contains(.closeTab) {
            targetScope = .activeTab
            feedback = .closeTab
        } else if matched.contains(.close) {
            targetScope = .window
            feedback = .close
        } else {
            return nil
        }

        if case let .missionControlPreview(windowInfo, _) = context.target {
            return context.execute(feedbackMode: feedback) {
                let shouldTryTab: Bool
                if targetScope == .activeTab {
                    shouldTryTab = true
                } else if targetScope == .smartClose {
                    let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t
                    let app = pid.flatMap { NSRunningApplication(processIdentifier: $0) }
                    shouldTryTab = WindowCloser.isTabbedApplication(app)
                } else {
                    shouldTryTab = false
                }

                if shouldTryTab {
                    MissionControlWindowActions.performCloseTab(
                        on: windowInfo,
                        accessibilityService: context.service
                    )
                } else if let hover = context.hoverService {
                    Self.runOnMainActor {
                        hover.executeAction(mode: .close, on: windowInfo)
                    }
                } else {
                    MissionControlWindowActions.performClose(
                        on: windowInfo,
                        accessibilityService: context.service
                    )
                }
            }
        }
        return context.execute(feedbackMode: feedback, needsActivate: true) { [weak self] in
            guard let self else { return }
            // Architectural rule: Dock targeting (inside MC or outside MC) acts at the App level
            // (all windows belonging to the app), while window previews and title bars act on a singular window.
            let scope: CloseScope = (context.app != nil && targetScope == .window) ? .wholeApp : targetScope
            self.actions.close.perform(
                scope,
                at: context.location,
                fromApp: context.app,
                service: context.service,
                quitIfNoWindows: context.config.isQuitAppIfNoWindowsEnabled
            )
        }
    }

    /// Routes core lifecycle shortcuts (close, quit, minimize, hide) based on target resolution.
    func routeCoreShortcuts(
        matched: [RoutedAction],
        context: Context
    ) -> ResolvedShortcutAction? {
        if let closeAction = routeCloseShortcut(matched: matched, context: context) {
            return closeAction
        }
        if matched.contains(.quit) {
            if case let .missionControlPreview(windowInfo, _) = context.target {
                return context.execute(feedbackMode: .quit) {
                    if let hover = context.hoverService {
                        Self.runOnMainActor {
                            hover.executeAction(mode: .quit, on: windowInfo)
                        }
                    } else {
                        MissionControlWindowActions.performForceQuit(on: windowInfo)
                    }
                }
            }
            return context.execute(feedbackMode: .quit) { [weak self] in
                guard let self else { return }
                if let app = context.app {
                    self.actions.forceQuitAppAction.perform(app: app)
                } else {
                    self.actions.forceQuitAction.perform(at: context.location, service: context.service)
                }
            }
        }
        if matched.contains(.minimize) {
            if case let .missionControlPreview(windowInfo, _) = context.target {
                return context.execute(feedbackMode: .minimize) {
                    if let hover = context.hoverService {
                        Self.runOnMainActor {
                            hover.executeAction(mode: .minimize, on: windowInfo)
                        }
                    } else {
                        MissionControlWindowActions.performMinimize(
                            on: windowInfo,
                            accessibilityService: context.service
                        )
                    }
                }
            }
            return context.execute(feedbackMode: .minimize) { [weak self] in
                guard let self else { return }
                if let app = context.app {
                    self.actions.minimizeAppAction.perform(app: app, service: context.service)
                } else {
                    self.actions.minimizeAction.perform(at: context.location, service: context.service)
                }
            }
        }
        if matched.contains(.hide) {
            return context.execute(feedbackMode: .hide) { [weak self] in
                guard let self else { return }
                if let app = context.app {
                    if app.isSafeTargetProcess {
                        app.hide()
                    }
                } else {
                    self.actions.hideAction.perform(at: context.location, service: context.service)
                }
            }
        }
        return nil
    }

    /// Routes window-level chrome actions (fullscreen, new tab, new window).
    func routeWindowShortcuts(
        matched: [RoutedAction],
        context: Context
    ) -> ResolvedShortcutAction? {
        if matched.contains(.fullscreen) {
            if case let .missionControlPreview(windowInfo, _) = context.target {
                return context.execute(feedbackMode: .fullscreen) {
                    if let hover = context.hoverService {
                        Self.runOnMainActor {
                            hover.executeAction(mode: .fullscreen, on: windowInfo)
                        }
                    } else {
                        MissionControlWindowActions.performFullscreen(
                            on: windowInfo,
                            accessibilityService: context.service
                        )
                    }
                }
            }
            return context.execute(feedbackMode: .fullscreen, needsActivate: true) { [weak self] in
                guard let self else { return }
                if let app = context.app {
                    self.actions.toggleFullscreenAppAction.perform(app: app, service: context.service)
                } else {
                    self.actions.toggleFullscreenAction.perform(at: context.location, service: context.service)
                }
            }
        }
        if matched.contains(.newTab) {
            let mode: CursorFeedbackMode = (context.app != nil) ? .newWindow : .newTab
            return context.execute(feedbackMode: mode, needsActivate: true) { [weak self] in
                guard let self else { return }
                if let app = context.app {
                    self.actions.newWindowAppAction.perform(app: app)
                } else {
                    self.actions.newTabAction.perform(at: context.location, service: context.service)
                }
            }
        }
        if matched.contains(.newWindow) {
            return context.execute(feedbackMode: .newWindow, needsActivate: true) { [weak self] in
                guard let self else { return }
                if let app = context.app {
                    self.actions.newWindowAppAction.perform(app: app)
                } else {
                    self.actions.newWindowAction.perform(at: context.location, service: context.service)
                }
            }
        }
        return nil
    }

    /// Routes tab-level actions (reopen tab).
    func routeTabActions(
        matched: [RoutedAction],
        context: Context
    ) -> ResolvedShortcutAction? {
        if matched.contains(.reopenTab) {
            return context.execute(feedbackMode: .reopenTab, needsActivate: true) { [weak self] in
                guard let self else { return }
                if let app = context.app {
                    self.actions.reopenTabAppAction.perform(app: app)
                } else {
                    self.actions.reopenTabAction.perform(at: context.location, service: context.service)
                }
            }
        }
        return nil
    }

    /// Complexity note: split across `routeFillActions` (fill/almost),
    /// `routeSnapActions` (cycle snaps), and `routeResizeActions` (reasonable/larger/smaller)
    /// to keep each function's cyclomatic complexity under the SwiftLint budget.
    func routeWindowSizeActions(
        matched: [RoutedAction],
        context: Context
    ) -> ResolvedShortcutAction? {
        if let action = routeFillActions(matched: matched, context: context) {
            return action
        }
        if let action = routeSnapActions(matched: matched, context: context) {
            return action
        }
        return routeResizeActions(matched: matched, context: context)
    }

    func routeSnapActions(
        matched: [RoutedAction],
        context: Context
    ) -> ResolvedShortcutAction? {
        let snapConfigs: [(
            RoutedAction,
            CursorFeedbackMode,
            (ActionRegistry, NSRunningApplication?, CGPoint, AccessibilityServiceProtocol) -> Void
        )] = [
            (.leftCycleSnap, .leftCycleSnap, { actions, app, loc, svc in
                if let app {
                    actions.leftCycleSnapAppAction.perform(app: app, service: svc)
                } else {
                    actions.leftCycleSnapAction.perform(at: loc, service: svc)
                }
            }),
            (.rightCycleSnap, .rightCycleSnap, { actions, app, loc, svc in
                if let app {
                    actions.rightCycleSnapAppAction.perform(app: app, service: svc)
                } else {
                    actions.rightCycleSnapAction.perform(at: loc, service: svc)
                }
            })
        ]

        for (action, mode, handler) in snapConfigs where matched.contains(action) {
            if case let .missionControlPreview(windowInfo, _) = context.target {
                return context.execute(feedbackMode: mode) { [weak self] in
                    guard let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
                          let window = context.service.getWindow(forWindowID: windowID) else { return }
                    switch action {
                    case .leftCycleSnap:
                        self?.actions.leftCycleSnapAction.perform(
                            window: window,
                            at: context.location,
                            service: context.service
                        )
                    case .rightCycleSnap:
                        self?.actions.rightCycleSnapAction.perform(
                            window: window,
                            at: context.location,
                            service: context.service
                        )
                    default:
                        break
                    }
                }
            }
            return context.execute(feedbackMode: mode, needsActivate: true) { [weak self] in
                guard let self else { return }
                handler(self.actions, context.app, context.location, context.service)
            }
        }
        return nil
    }

    func routeFillActions(
        matched: [RoutedAction],
        context: Context
    ) -> ResolvedShortcutAction? {
        if matched.contains(.fillScreen) {
            if case let .missionControlPreview(windowInfo, _) = context.target {
                return context.execute(feedbackMode: .maximize) { [weak self] in
                    guard let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
                          let window = context.service.getWindow(forWindowID: windowID) else { return }
                    self?.actions.fillScreenAction.perform(
                        window: window,
                        at: context.location,
                        service: context.service
                    )
                }
            }
            return context.execute(feedbackMode: .maximize, needsActivate: true) { [weak self] in
                guard let self else { return }
                if let app = context.app {
                    self.actions.fillScreenAppAction.perform(app: app, service: context.service)
                } else {
                    self.actions.fillScreenAction.perform(at: context.location, service: context.service)
                }
            }
        }
        if matched.contains(.almostMaximize) {
            if case let .missionControlPreview(windowInfo, _) = context.target {
                return context.execute(feedbackMode: .almost) { [weak self] in
                    guard let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
                          let window = context.service.getWindow(forWindowID: windowID) else { return }
                    self?.actions.almostMaximizeAction.perform(
                        window: window,
                        at: context.location,
                        service: context.service
                    )
                }
            }
            return context.execute(feedbackMode: .almost, needsActivate: true) { [weak self] in
                guard let self else { return }
                if let app = context.app {
                    self.actions.almostMaximizeAppAction.perform(app: app, service: context.service)
                } else {
                    self.actions.almostMaximizeAction.perform(at: context.location, service: context.service)
                }
            }
        }
        return nil
    }

    func routeResizeActions(
        matched: [RoutedAction],
        context: Context
    ) -> ResolvedShortcutAction? {
        if matched.contains(.reasonableSize) {
            if case let .missionControlPreview(windowInfo, _) = context.target {
                return context.execute(feedbackMode: .reasonable) { [weak self] in
                    guard let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
                          let window = context.service.getWindow(forWindowID: windowID) else { return }
                    self?.actions.reasonableSizeAction.perform(
                        window: window,
                        at: context.location,
                        service: context.service
                    )
                }
            }
            return context.execute(feedbackMode: .reasonable, needsActivate: true) { [weak self] in
                guard let self else { return }
                if let app = context.app {
                    self.actions.reasonableSizeAppAction.perform(app: app, service: context.service)
                } else {
                    self.actions.reasonableSizeAction.perform(at: context.location, service: context.service)
                }
            }
        }
        if matched.contains(.makeLarger) {
            if case let .missionControlPreview(windowInfo, _) = context.target {
                return context.execute(feedbackMode: .maximize) { [weak self] in
                    guard let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
                          let window = context.service.getWindow(forWindowID: windowID) else { return }
                    self?.actions.makeLargerAction.perform(
                        window: window,
                        at: context.location,
                        service: context.service
                    )
                }
            }
            return context.execute(feedbackMode: .maximize, needsActivate: true) { [weak self] in
                guard let self else { return }
                if let app = context.app {
                    self.actions.makeLargerAppAction.perform(app: app, service: context.service)
                } else {
                    self.actions.makeLargerAction.perform(at: context.location, service: context.service)
                }
            }
        }
        if matched.contains(.makeSmaller) {
            if case let .missionControlPreview(windowInfo, _) = context.target {
                return context.execute(feedbackMode: .makeSmaller) { [weak self] in
                    guard let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
                          let window = context.service.getWindow(forWindowID: windowID) else { return }
                    self?.actions.makeSmallerAction.perform(
                        window: window,
                        at: context.location,
                        service: context.service
                    )
                }
            }
            return context.execute(feedbackMode: .makeSmaller, needsActivate: true) { [weak self] in
                guard let self else { return }
                if let app = context.app {
                    self.actions.makeSmallerAppAction.perform(app: app, service: context.service)
                } else {
                    self.actions.makeSmallerAction.perform(at: context.location, service: context.service)
                }
            }
        }
        return nil
    }

    /// Minimize/Unminimize *all* windows of the hovered app. The target may be
    /// either its Dock icon or any of its windows — both resolve to the owning
    /// application, since the effect is app-wide rather than per-window.
    func routeAppGroupActions(
        matched: [RoutedAction],
        target: TargetResolution,
        context: Context
    ) -> ResolvedShortcutAction? {
        if matched.contains(.unminimizeAll) {
            return context.execute(feedbackMode: .unminimizeAll, needsActivate: true) { [weak self] in
                guard let self,
                      let owner = self.resolveOwnerApp(
                          target: target,
                          app: context.app,
                          service: context.service
                      ) else { return }
                self.actions.unminimizeAllWindowsAction.perform(app: owner, service: context.service)
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
        if case let .missionControlPreview(windowInfo, _) = target,
           let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t {
            return NSRunningApplication(processIdentifier: pid)
        }
        return nil
    }

    func routeDesktopActions(
        matched: [RoutedAction],
        context: Context
    ) -> ResolvedShortcutAction? {
        if matched.contains(.moveNextDesktop) {
            return context.execute(feedbackMode: .spaceRight) { [weak self] in
                guard let self else { return }
                if case let .missionControlPreview(windowInfo, _) = context.target,
                   let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
                   let window = context.service.getWindow(forWindowID: windowID) {
                    self.actions.moveNextDesktopAction.perform(window: window, service: context.service)
                } else if let app = context.app {
                    self.actions.moveNextDesktopAction.perform(app: app, service: context.service)
                } else {
                    self.actions.moveNextDesktopAction.perform(at: context.location, service: context.service)
                }
            }
        }
        if matched.contains(.movePreviousDesktop) {
            return context.execute(feedbackMode: .spaceLeft) { [weak self] in
                guard let self else { return }
                if case let .missionControlPreview(windowInfo, _) = context.target,
                   let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
                   let window = context.service.getWindow(forWindowID: windowID) {
                    self.actions.movePreviousDesktopAction.perform(window: window, service: context.service)
                } else if let app = context.app {
                    self.actions.movePreviousDesktopAction.perform(app: app, service: context.service)
                } else {
                    self.actions.movePreviousDesktopAction.perform(at: context.location, service: context.service)
                }
            }
        }
        return nil
    }
}
