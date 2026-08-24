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
        let feedbackMode = feedbackMode(for: action)
        // Swipe-left auto-activates target app before closing tab (legacy).
        let needsActivate = (kind == .swipeLeft && !isCmd)

        switch target {
        case .none:
            return .none
        case let .dock(app):
            return dockAction(
                for: action,
                app: app,
                point: point,
                service: service,
                feedbackMode: feedbackMode,
                haptic: haptic,
                needsActivate: needsActivate,
                activateApp: activateApp
            )
        case .window:
            return windowAction(
                for: action,
                point: point,
                service: service,
                feedbackMode: feedbackMode,
                haptic: haptic,
                needsActivate: needsActivate,
                activateApp: activateApp
            )
        }
    }

    // MARK: - Action dispatch per target

    private func dockAction(
        for action: GestureAction,
        app: NSRunningApplication,
        point: CGPoint,
        service: AccessibilityServiceProtocol,
        feedbackMode: CursorFeedbackOverlay.Mode,
        haptic: HapticType,
        needsActivate: Bool,
        activateApp: @escaping (CGPoint) -> Void
    ) -> ResolvedGestureAction {
        switch action {
        case .closeWindow:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                self?.actions.close.perform(.wholeApp, at: point, fromApp: app, service: service)
            }
        case .quitApp:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                self?.actions.forceQuitAppAction.perform(app: app)
            }
        case .closeTab:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                if needsActivate {
                    activateApp(point)
                }
                self?.actions.close.perform(.activeTab, at: point, fromApp: app, service: service)
            }
        case .closeAllTabs:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                self?.actions.close.perform(.allTabs, at: point, fromApp: app, service: service)
            }
        case .reopenTab:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                self?.actions.reopenTabAppAction.perform(app: app)
            }
        case .newTab:
            // Dock has no window to add a tab to — fall back to new window.
            .execute(feedbackMode: .newWindow, haptic: haptic) { [weak self] in
                self?.actions.newWindowAction.perform(at: point, service: service)
            }
        case .newWindow:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                self?.actions.newWindowAction.perform(at: point, service: service)
            }
        case .toggleFullscreen:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                self?.actions.toggleFullscreenAppAction.perform(app: app, service: service)
            }
        case .fillScreen:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                self?.actions.fillScreenAppAction.perform(app: app, service: service)
            }
        case .almostMaximize:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                self?.actions.almostMaximizeAppAction.perform(app: app, service: service)
            }
        case .makeLarger:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                self?.actions.makeLargerAppAction.perform(app: app, service: service)
            }
        case .makeSmaller:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                self?.actions.makeSmallerAppAction.perform(app: app, service: service)
            }
        case .reasonableSize:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                self?.actions.reasonableSizeAppAction.perform(app: app, service: service)
            }
        case .minimize:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                self?.actions.minimizeAppAction.perform(app: app, service: service)
            }
        case .hideApp:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                guard self != nil else { return }
                app.hide()
            }
        case .moveNextDesktop:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                guard let self else { return }
                self.actions.moveNextDesktopAction.perform(app: app, service: service)
            }
        case .movePreviousDesktop:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                guard let self else { return }
                self.actions.movePreviousDesktopAction.perform(app: app, service: service)
            }
        }
    }

    private func windowAction(
        for action: GestureAction,
        point: CGPoint,
        service: AccessibilityServiceProtocol,
        feedbackMode: CursorFeedbackOverlay.Mode,
        haptic: HapticType,
        needsActivate: Bool,
        activateApp: @escaping (CGPoint) -> Void
    ) -> ResolvedGestureAction {
        switch action {
        case .closeWindow:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                self?.actions.close.perform(.window, at: point, fromApp: nil, service: service)
            }
        case .quitApp:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                self?.actions.forceQuitAction.perform(at: point, service: service)
            }
        case .closeTab:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                if needsActivate {
                    activateApp(point)
                }
                self?.actions.close.perform(.activeTab, at: point, fromApp: nil, service: service)
            }
        case .closeAllTabs:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                self?.actions.close.perform(.allTabs, at: point, fromApp: nil, service: service)
            }
        case .reopenTab:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                self?.actions.reopenTabAction.perform(at: point, service: service)
            }
        case .newTab:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                self?.actions.newTabAction.perform(at: point, service: service)
            }
        case .newWindow:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                self?.actions.newWindowAction.perform(at: point, service: service)
            }
        case .toggleFullscreen:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                self?.actions.toggleFullscreenAction.perform(at: point, service: service)
            }
        case .fillScreen:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                self?.actions.fillScreenAction.perform(at: point, service: service)
            }
        case .almostMaximize:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                self?.actions.almostMaximizeAction.perform(at: point, service: service)
            }
        case .makeLarger:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                self?.actions.makeLargerAction.perform(at: point, service: service)
            }
        case .makeSmaller:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                self?.actions.makeSmallerAction.perform(at: point, service: service)
            }
        case .reasonableSize:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                self?.actions.reasonableSizeAction.perform(at: point, service: service)
            }
        case .minimize:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                self?.actions.minimizeAction.perform(at: point, service: service)
            }
        case .hideApp:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                self?.actions.hideAction.perform(at: point, service: service)
            }
        case .moveNextDesktop:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                self?.actions.moveNextDesktopAction.perform(at: point, service: service)
            }
        case .movePreviousDesktop:
            .execute(feedbackMode: feedbackMode, haptic: haptic) { [weak self] in
                self?.actions.movePreviousDesktopAction.perform(at: point, service: service)
            }
        }
    }

    private func feedbackMode(for action: GestureAction) -> CursorFeedbackOverlay.Mode {
        switch action {
        case .closeWindow: .close
        case .quitApp: .quit
        case .closeTab: .closeTab
        case .closeAllTabs: .closeAllTabs
        case .reopenTab: .reopenTab
        case .newTab: .newTab
        case .newWindow: .newWindow
        case .toggleFullscreen: .fullscreen
        case .fillScreen: .maximize
        case .almostMaximize: .almost
        case .makeLarger: .maximize
        case .makeSmaller: .makeSmaller
        case .reasonableSize: .reasonable
        case .minimize: .minimize
        case .hideApp: .hide
        case .moveNextDesktop: .spaceRight
        case .movePreviousDesktop: .spaceLeft
        }
    }
}
