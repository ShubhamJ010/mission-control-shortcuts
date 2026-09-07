import Cocoa

enum ResolvedGestureAction {
    case execute(feedbackMode: CursorFeedbackOverlay.Mode, haptic: HapticType?, action: () -> Void)
    case none
}

/// Routes gesture recognition results to their corresponding actions
/// based on the target element under cursor and the user's configured mappings.
final class GestureActionRouter {
    private let actions: ActionRegistry

    init(actions: ActionRegistry = ActionRegistry()) {
        self.actions = actions
    }

    func routeGesture(
        _ result: GestureResult,
        at point: CGPoint,
        target: TargetResolution,
        service: AccessibilityServiceProtocol,
        volumeService: MountedVolumeServiceProtocol? = nil,
        isAutoEjectEnabled: Bool = true,
        config: ShortcutConfiguration = ShortcutConfiguration(),
        isTitleBarHover: Bool = false,
        activateApp: @escaping (CGPoint) -> Void
    ) -> ResolvedGestureAction {
        let (kind, isCmd) = result.kindAndModifier
        let haptic = kind.haptic(isCmd: isCmd)

        // Eject intercept (Finder window with ejectable volume) takes priority for
        // pinch-in and plain swipe-left — mirrors legacy behaviour.
        let shouldCheckEject = switch (kind, isCmd) {
        case (.pinchIn, _): true
        case (.swipeLeft, false): true
        default: false
        }
        if shouldCheckEject,
           isAutoEjectEnabled,
           case let .window(window) = target,
           let volumeService,
           let targetApp = service.getAppFromElement(window),
           targetApp.bundleIdentifier == "com.apple.finder",
           let mountPath = volumeService.ejectableVolumePath(
               forDocumentPath: service.getDocumentPath(for: window),
               windowTitle: service.getWindowTitle(for: window)
           ) {
            return .execute(feedbackMode: .eject, haptic: haptic) { [weak self] in
                self?.actions.ejectVolumeAction.perform(
                    window: window,
                    mountPath: mountPath,
                    service: service,
                    volumeService: volumeService
                )
            }
        }

        let action = config.action(for: kind, isCmd: isCmd)
        let context = Context(
            point: point,
            service: service,
            feedbackMode: feedbackMode(for: action),
            haptic: haptic,
            needsActivate: action.requiresAppActivation || isTitleBarHover,
            quitIfNoWindows: config.isQuitAppIfNoWindowsEnabled,
            activateApp: activateApp
        )

        switch target {
        case .none:
            return .none
        case let .dock(app):
            return dockAction(for: action, app: app, context: context)
        case .window:
            return windowAction(for: action, context: context)
        }
    }
}

// MARK: - Dispatch Context & Helpers

private extension GestureActionRouter {
    struct Context {
        let point: CGPoint
        let service: AccessibilityServiceProtocol
        let feedbackMode: CursorFeedbackOverlay.Mode
        let haptic: HapticType
        let needsActivate: Bool
        let quitIfNoWindows: Bool
        let activateApp: (CGPoint) -> Void

        func execute(
            overrideFeedbackMode: CursorFeedbackOverlay.Mode? = nil,
            block: @escaping () -> Void
        ) -> ResolvedGestureAction {
            .execute(feedbackMode: overrideFeedbackMode ?? feedbackMode, haptic: haptic) {
                if needsActivate {
                    activateApp(point)
                }
                block()
            }
        }
    }

    func dockAction(for action: GestureAction, app: NSRunningApplication, context: Context) -> ResolvedGestureAction {
        if let result = dockLifecycleAction(for: action, app: app, context: context) {
            return result
        }
        return dockWindowAndSizingAction(for: action, app: app, context: context)
    }

    func dockLifecycleAction(
        for action: GestureAction,
        app: NSRunningApplication,
        context: Context
    ) -> ResolvedGestureAction? {
        switch action {
        case .closeWindow:
            context.execute { [weak self] in
                self?.actions.close.perform(
                    .wholeApp,
                    at: context.point,
                    fromApp: app,
                    service: context.service,
                    quitIfNoWindows: context.quitIfNoWindows
                )
            }
        case .quitApp:
            context.execute { [weak self] in
                self?.actions.forceQuitAppAction.perform(app: app)
            }
        case .closeTab:
            context.execute { [weak self] in
                self?.actions.close.perform(
                    .activeTab,
                    at: context.point,
                    fromApp: app,
                    service: context.service,
                    quitIfNoWindows: context.quitIfNoWindows
                )
            }
        case .reopenTab:
            context.execute { [weak self] in
                self?.actions.reopenTabAppAction.perform(app: app)
            }
        case .newTab, .newWindow:
            // Dock has no window to add a tab to — fall back to new window with .newWindow feedback.
            context.execute(overrideFeedbackMode: .newWindow) { [weak self] in
                self?.actions.newWindowAction.perform(at: context.point, service: context.service)
            }
        case .minimize:
            context.execute { [weak self] in
                self?.actions.minimizeAppAction.perform(app: app, service: context.service)
            }
        case .hideApp:
            context.execute {
                app.hide()
            }
        case .unminimizeAll:
            context.execute { [weak self] in
                self?.actions.unminimizeAllWindowsAction.perform(app: app, service: context.service)
            }
        default:
            nil
        }
    }

    func dockWindowAndSizingAction(
        for action: GestureAction,
        app: NSRunningApplication,
        context: Context
    ) -> ResolvedGestureAction {
        switch action {
        case .toggleFullscreen:
            context.execute { [weak self] in
                self?.actions.toggleFullscreenAppAction.perform(app: app, service: context.service)
            }
        case .fillScreen:
            context.execute { [weak self] in
                self?.actions.fillScreenAppAction.perform(app: app, service: context.service)
            }
        case .almostMaximize:
            context.execute { [weak self] in
                self?.actions.almostMaximizeAppAction.perform(app: app, service: context.service)
            }
        case .makeLarger:
            context.execute { [weak self] in
                self?.actions.makeLargerAppAction.perform(app: app, service: context.service)
            }
        case .makeSmaller:
            context.execute { [weak self] in
                self?.actions.makeSmallerAppAction.perform(app: app, service: context.service)
            }
        case .reasonableSize:
            context.execute { [weak self] in
                self?.actions.reasonableSizeAppAction.perform(app: app, service: context.service)
            }
        case .moveNextDesktop:
            context.execute { [weak self] in
                self?.actions.moveNextDesktopAction.perform(app: app, service: context.service)
            }
        case .movePreviousDesktop:
            context.execute { [weak self] in
                self?.actions.movePreviousDesktopAction.perform(app: app, service: context.service)
            }
        default:
            .none
        }
    }

    func windowAction(for action: GestureAction, context: Context) -> ResolvedGestureAction {
        if let result = windowLifecycleAction(for: action, context: context) {
            return result
        }
        return windowSizingAction(for: action, context: context)
    }

    func windowLifecycleAction(for action: GestureAction, context: Context) -> ResolvedGestureAction? {
        switch action {
        case .closeWindow:
            context.execute { [weak self] in
                self?.actions.close.perform(
                    .window,
                    at: context.point,
                    fromApp: nil,
                    service: context.service,
                    quitIfNoWindows: context.quitIfNoWindows
                )
            }
        case .quitApp:
            context.execute { [weak self] in
                self?.actions.forceQuitAction.perform(at: context.point, service: context.service)
            }
        case .closeTab:
            context.execute { [weak self] in
                self?.actions.close.perform(
                    .activeTab,
                    at: context.point,
                    fromApp: nil,
                    service: context.service,
                    quitIfNoWindows: context.quitIfNoWindows
                )
            }
        case .reopenTab:
            context.execute { [weak self] in
                self?.actions.reopenTabAction.perform(at: context.point, service: context.service)
            }
        case .newTab:
            context.execute { [weak self] in
                self?.actions.newTabAction.perform(at: context.point, service: context.service)
            }
        case .newWindow:
            context.execute { [weak self] in
                self?.actions.newWindowAction.perform(at: context.point, service: context.service)
            }
        case .minimize:
            context.execute { [weak self] in
                self?.actions.minimizeAction.perform(at: context.point, service: context.service)
            }
        case .hideApp:
            context.execute { [weak self] in
                self?.actions.hideAction.perform(at: context.point, service: context.service)
            }
        case .unminimizeAll:
            context.execute { [weak self] in
                guard let self, let element = context.service.getElement(at: context.point),
                      let owner = context.service.getAppFromElement(element) else { return }
                self.actions.unminimizeAllWindowsAction.perform(app: owner, service: context.service)
            }
        default:
            nil
        }
    }

    func windowSizingAction(for action: GestureAction, context: Context) -> ResolvedGestureAction {
        switch action {
        case .toggleFullscreen:
            context.execute { [weak self] in
                self?.actions.toggleFullscreenAction.perform(at: context.point, service: context.service)
            }
        case .fillScreen:
            context.execute { [weak self] in
                self?.actions.fillScreenAction.perform(at: context.point, service: context.service)
            }
        case .almostMaximize:
            context.execute { [weak self] in
                self?.actions.almostMaximizeAction.perform(at: context.point, service: context.service)
            }
        case .makeLarger:
            context.execute { [weak self] in
                self?.actions.makeLargerAction.perform(at: context.point, service: context.service)
            }
        case .makeSmaller:
            context.execute { [weak self] in
                self?.actions.makeSmallerAction.perform(at: context.point, service: context.service)
            }
        case .reasonableSize:
            context.execute { [weak self] in
                self?.actions.reasonableSizeAction.perform(at: context.point, service: context.service)
            }
        case .moveNextDesktop:
            context.execute { [weak self] in
                self?.actions.moveNextDesktopAction.perform(at: context.point, service: context.service)
            }
        case .movePreviousDesktop:
            context.execute { [weak self] in
                self?.actions.movePreviousDesktopAction.perform(at: context.point, service: context.service)
            }
        default:
            .none
        }
    }

    private func feedbackMode(for action: GestureAction) -> CursorFeedbackOverlay.Mode {
        switch action {
        case .closeWindow: .close
        case .quitApp: .quit
        case .closeTab: .closeTab
        case .reopenTab: .reopenTab
        case .newTab: .newTab
        case .newWindow: .newWindow
        case .toggleFullscreen: .fullscreen
        case .fillScreen, .makeLarger: .maximize
        case .almostMaximize: .almost
        case .makeSmaller: .makeSmaller
        case .reasonableSize: .reasonable
        case .minimize: .minimize
        case .hideApp: .hide
        case .moveNextDesktop: .spaceRight
        case .movePreviousDesktop: .spaceLeft
        case .unminimizeAll: .unminimizeAll
        }
    }
}
