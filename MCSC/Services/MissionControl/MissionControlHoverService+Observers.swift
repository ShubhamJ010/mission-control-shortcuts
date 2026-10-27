import ApplicationServices
import Cocoa

extension MissionControlHoverService {
    static let dockNotifications = [
        "AXExposeShowAllWindows",
        "AXExposeShowFrontWindows",
        "AXExposeExit",
        "AXExposeShowDesktop"
    ]

    func setupDockProcessObservers() {
        guard dockLaunchObserver == nil, dockTerminateObserver == nil else { return }

        dockLaunchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == "com.apple.dock" else { return }
                AppLogger.dock.info("Dock launched (PID: \(app.processIdentifier)). Reconnecting AXObserver.")
                self?.setupDockObserver()
            }
        }

        dockTerminateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == "com.apple.dock" else { return }
                AppLogger.dock.notice("Dock terminated (PID: \(app.processIdentifier)). Stopping AXObserver.")
                self?.stopDockObserver()
                if self?.isMissionControlActive == true {
                    self?.handleDeactivated()
                }
            }
        }
    }

    func removeDockProcessObservers() {
        if let observer = dockLaunchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            dockLaunchObserver = nil
        }
        if let observer = dockTerminateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            dockTerminateObserver = nil
        }
    }

    func setupDockObserver() {
        stopDockObserver()

        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
              !dockApp.isTerminated
        else {
            AppLogger.dock.error("Dock process not found or terminated for AXObserver")
            return
        }

        let pid = dockApp.processIdentifier
        var observer: AXObserver?
        let result = AXObserverCreate(pid, { _, _, notification, refcon in
            guard let refcon else { return }
            let service = Unmanaged<MissionControlHoverService>.fromOpaque(refcon).takeUnretainedValue()
            let notif = notification as String
            MainActor.assumeIsolated {
                service.handleDockNotification(notif)
            }
        }, &observer)

        guard result == .success, let obs = observer else {
            AppLogger.dock.error("Failed to create AXObserver for Dock: \(result.rawValue)")
            if isTracking {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self, self.isTracking, self.axObserver == nil else { return }
                    self.setupDockObserver()
                }
            }
            return
        }

        let dockElement = AXUIElementCreateApplication(pid)
        self.dockAXElement = dockElement

        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        for notif in Self.dockNotifications {
            let addResult = AXObserverAddNotification(obs, dockElement, notif as CFString, refcon)
            if addResult != .success {
                AppLogger.dock.warning("Failed to add observer for \(notif): \(addResult.rawValue)")
            }
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        self.axObserver = obs
    }

    func stopDockObserver() {
        if let obs = axObserver {
            if let dockElement = dockAXElement {
                for notif in Self.dockNotifications {
                    AXObserverRemoveNotification(obs, dockElement, notif as CFString)
                }
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
            self.axObserver = nil
            self.dockAXElement = nil
        }
    }

    func handleActivated() {
        guard !isMissionControlActive else { return }
        debugLog("MissionControlHoverService.handleActivated called", category: AppLogger.missionControl)
        isMissionControlActive = true
        lastKnownSpaceID = spaceService.currentSpaceID()

        guard isEnabled else { return }

        fetchWindows()
        startWindowFetchTimer()
        startKeyboardSession()

        if let mouseLocation = CGEvent(source: nil)?.location {
            updateOverlay(at: mouseLocation)
        }
    }

    func handleDeactivated() {
        debugLog("MissionControlHoverService.handleDeactivated called", category: AppLogger.missionControl)
        isMissionControlActive = false
        isDragging = false
        isMouseDown = false
        isSpaceTransitioning = false
        spaceTransitionTimeoutTimer?.invalidate()
        spaceTransitionTimeoutTimer = nil
        lastKnownSpaceID = nil
        stopWindowFetchTimer()
        hideAllOverlays()
        stopKeyboardSession()
        windows = []
        currentMatches = []
        searchSession = WindowSearchSession()
    }

    func handleDockNotification(_ notification: String) {
        debugLog("handleDockNotification: \(notification)", category: AppLogger.dock)
        switch notification {
        case "AXExposeExit", "AXExposeShowDesktop":
            missionControlService?.markActive(false)
            handleDeactivated()
        case "AXExposeShowAllWindows", "AXExposeShowFrontWindows":
            missionControlService?.markActive(true)
            handleActivated()
        default:
            break
        }
    }
}
