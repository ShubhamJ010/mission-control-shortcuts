import ApplicationServices
import Cocoa

/// Dock AXObserver for `MissionControlHoverService`: the Dock exposes
/// Exposé/Mission Control state transitions as AX notifications on its
/// application element (`AXExposeShowAllWindows`, `AXExposeExit`, …).
/// Split from the main file to stay under the SwiftLint `file_length` budget.
@MainActor
extension MissionControlHoverService {
    static let dockNotifications = [
        "AXExposeShowAllWindows",
        "AXExposeShowFrontWindows",
        "AXExposeShowDesktop",
        "AXExposeExit"
    ]

    func setupDockObserver() {
        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else {
            return
        }

        let pid = dockApp.processIdentifier
        let dockElement = AXUIElementCreateApplication(pid)
        self.dockAXElement = dockElement

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, notification, refcon in
            guard let refcon else { return }
            let service = Unmanaged<MissionControlHoverService>.fromOpaque(refcon).takeUnretainedValue()
            let notifName = notification as String

            DispatchQueue.main.async {
                service.handleDockNotification(notifName)
            }
        }

        guard AXObserverCreate(pid, callback, &observer) == .success, let obs = observer else {
            return
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        for notif in Self.dockNotifications {
            AXObserverAddNotification(obs, dockElement, notif as CFString, selfPtr)
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        self.axObserver = obs
    }

    func stopDockObserver() {
        if let obs = axObserver, let dockElement = dockAXElement {
            for notif in Self.dockNotifications {
                AXObserverRemoveNotification(obs, dockElement, notif as CFString)
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
            self.axObserver = nil
            self.dockAXElement = nil
        }
    }

    func handleDockNotification(_ notification: String) {
        if notification == "AXExposeExit" {
            isMissionControlActive = false
            stopWindowFetchTimer()
            hideOverlay()
            stopKeyboardSession()
        } else {
            isMissionControlActive = true

            // When the feature is disabled, track Mission Control state
            // (other services depend on it) but do NOT create the overlay,
            // start window polling, or install the keyboard tap.
            guard isEnabled else { return }

            fetchWindows()
            startWindowFetchTimer()
            startKeyboardSession()

            if let mouseLocation = CGEvent(source: nil)?.location {
                updateOverlay(at: mouseLocation)
            }
        }
    }
}
