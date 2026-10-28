import ApplicationServices
import Cocoa
import Darwin
import os

/// Protocol defining operations for tracking and terminating background applications and helper daemons.
protocol BackgroundAppServiceProtocol: AnyObject {
    func recordQuitAttempt(for app: NSRunningApplication)
    func isRecentQuitAttempt(for app: NSRunningApplication) -> Bool
    func clearQuitAttempt(for app: NSRunningApplication)
    func terminateBackgroundServices(for app: NSRunningApplication, dockItem: AXUIElement?)
    func terminateLingeringDockItem(_ dockItem: AXUIElement)
    func findProcessIDs(forBundleURL bundleURL: URL) -> [pid_t]
    func stop()
}

/// Service managing process termination for applications and their background services / helper daemons,
/// resolving lingering "Running in Background" apps on macOS 27.
final class BackgroundAppService: BackgroundAppServiceProtocol {
    static let shared = BackgroundAppService()

    private struct QuitRecord {
        let timestamp: Date
        let pid: pid_t
    }

    private let lock = NSLock()
    private var quitHistory: [String: QuitRecord] = [:]
    private let recentThreshold: TimeInterval = 8.0

    private let terminationQueue = DispatchQueue(
        label: "sj010.MCSC.BackgroundAppService",
        qos: .userInitiated
    )

    private static let protectedBundleIDs: Set<String> = [
        "com.apple.dock",
        "com.apple.WindowManager",
        "com.apple.WindowServer",
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight",
        "com.apple.finder"
    ]

    private func targetKey(for app: NSRunningApplication) -> String {
        if let bundleId = app.bundleIdentifier, !bundleId.isEmpty {
            return bundleId
        }
        return "pid:\(app.processIdentifier)"
    }

    // MARK: - Quit Attempt Tracking

    func recordQuitAttempt(for app: NSRunningApplication) {
        lock.lock()
        defer { lock.unlock() }
        let key = targetKey(for: app)
        quitHistory[key] = QuitRecord(timestamp: Date(), pid: app.processIdentifier)
        AppLogger.app.info("Recorded quit attempt for '\(key, privacy: .public)'")
    }

    func isRecentQuitAttempt(for app: NSRunningApplication) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let key = targetKey(for: app)
        guard let record = quitHistory[key] else { return false }
        let elapsed = Date().timeIntervalSince(record.timestamp)
        if elapsed <= recentThreshold {
            return true
        }
        quitHistory.removeValue(forKey: key)
        return false
    }

    func clearQuitAttempt(for app: NSRunningApplication) {
        lock.lock()
        defer { lock.unlock() }
        let key = targetKey(for: app)
        quitHistory.removeValue(forKey: key)
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        quitHistory.removeAll()
    }

    // MARK: - Process Enumeration

    func findProcessIDs(forBundleURL bundleURL: URL) -> [pid_t] {
        let resolvedPath = bundleURL.resolvingSymlinksInPath().path
        guard !resolvedPath.isEmpty, resolvedPath != "/" else { return [] }

        let numberOfProcesses = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard numberOfProcesses > 0 else { return [] }

        var pidsBuffer = [pid_t](repeating: 0, count: Int(numberOfProcesses))
        let count = proc_listpids(
            UInt32(PROC_ALL_PIDS),
            0,
            &pidsBuffer,
            numberOfProcesses * Int32(MemoryLayout<pid_t>.size)
        )

        let bufferSize = 4096
        let pathBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { pathBuffer.deallocate() }

        var bsdInfo = proc_bsdinfo()
        let bsdInfoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        let currentUid = getuid()
        let myPid = NSRunningApplication.current.processIdentifier

        var matchingPids = [pid_t]()

        for i in 0 ..< Int(count) {
            let pid = pidsBuffer[i]
            guard pid > 100, pid != myPid else { continue }

            let infoRet = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, bsdInfoSize)
            guard infoRet == bsdInfoSize, bsdInfo.pbi_uid == currentUid else { continue }

            let pathRet = proc_pidpath(pid, pathBuffer, UInt32(bufferSize))
            if pathRet > 0 {
                let execPath = String(cString: pathBuffer)
                if execPath.hasPrefix(resolvedPath) {
                    matchingPids.append(pid)
                }
            }
        }
        return matchingPids
    }

    private func getDescendantProcessIDs(rootPid: pid_t) -> Set<pid_t> {
        guard rootPid > 100 else { return [] }

        let numberOfProcesses = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard numberOfProcesses > 0 else { return [] }

        var pidsBuffer = [pid_t](repeating: 0, count: Int(numberOfProcesses))
        let count = proc_listpids(
            UInt32(PROC_ALL_PIDS),
            0,
            &pidsBuffer,
            numberOfProcesses * Int32(MemoryLayout<pid_t>.size)
        )

        var parentToChildren: [pid_t: [pid_t]] = [:]
        var bsdInfo = proc_bsdinfo()
        let bsdInfoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        let currentUid = getuid()
        let myPid = NSRunningApplication.current.processIdentifier

        for i in 0 ..< Int(count) {
            let pid = pidsBuffer[i]
            guard pid > 100, pid != myPid else { continue }

            let ret = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, bsdInfoSize)
            if ret == bsdInfoSize, bsdInfo.pbi_uid == currentUid {
                let ppid = pid_t(bsdInfo.pbi_ppid)
                parentToChildren[ppid, default: []].append(pid)
            }
        }

        var descendants = Set<pid_t>()
        var queue = [rootPid]

        while !queue.isEmpty {
            let curr = queue.removeFirst()
            if let children = parentToChildren[curr] {
                for child in children where !descendants.contains(child) {
                    descendants.insert(child)
                    queue.append(child)
                }
            }
        }
        return descendants
    }

    // MARK: - Dock Stop Running in Background

    private func triggerDockStopRunningInBackground(dockItem: AXUIElement) -> Bool {
        let actionResult = AXUIElementPerformAction(dockItem, "AXShowMenu" as CFString)
        guard actionResult == .success else {
            AppLogger.dock.info(
                "AXShowMenu failed with \(actionResult.rawValue, privacy: .public)"
            )
            return false
        }

        // Short sleep off main thread to allow Dock to populate the context menu
        Thread.sleep(forTimeInterval: 0.12)

        var menuRef: CFTypeRef?
        let menuErr = AXUIElementCopyAttributeValue(dockItem, "AXShownMenuUIElement" as CFString, &menuRef)
        guard menuErr == .success, let menu = menuRef,
              CFGetTypeID(menu) == AXUIElementGetTypeID() else {
            AppLogger.dock.info(
                "Dock context menu not exposed (err \(menuErr.rawValue, privacy: .public))"
            )
            return false
        }
        let menuElement = unsafeDowncast(menu, to: AXUIElement.self)

        var childrenRef: CFTypeRef?
        let childrenErr = AXUIElementCopyAttributeValue(menuElement, kAXChildrenAttribute as CFString, &childrenRef)
        guard childrenErr == .success, let menuItems = childrenRef as? [AXUIElement] else {
            AppLogger.dock.info(
                "Dock context menu has no readable children (err \(childrenErr.rawValue, privacy: .public))"
            )
            _ = AXUIElementPerformAction(menuElement, "AXCancel" as CFString)
            return false
        }

        var stopBackgroundTitle = "Stop Running in Background"
        if let dockBundle = Bundle(path: "/System/Library/CoreServices/Dock.app") {
            stopBackgroundTitle = dockBundle.localizedString(
                forKey: "STOP_RUNNING_IN_BACKGROUND",
                value: "Stop Running in Background",
                table: "DockMenus"
            )
        }

        var pressed = false
        var seenTitles: [String] = []
        for item in menuItems {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &titleRef)
            guard let title = titleRef as? String, !title.isEmpty else { continue }
            seenTitles.append(title)

            let matches = title.localizedCaseInsensitiveContains(stopBackgroundTitle) ||
                (title.localizedCaseInsensitiveContains("Stop") && title.localizedCaseInsensitiveContains("Background"))

            if matches {
                if AXUIElementPerformAction(item, kAXPressAction as CFString) == .success {
                    pressed = true
                    AppLogger.dock.info("Triggered '\(title, privacy: .public)' on Dock item")
                    break
                }
            }
        }

        if !pressed {
            AppLogger.dock.info("No stop-background item; expected '\(stopBackgroundTitle, privacy: .public)'")
            AppLogger.dock.info("Dock menu items: \(seenTitles.joined(separator: " | "), privacy: .public)")
            _ = AXUIElementPerformAction(menuElement, "AXCancel" as CFString)
        }
        return pressed
    }

    private func findDockItem(for app: NSRunningApplication) -> AXUIElement? {
        guard let dockApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.dock"
        }) else { return nil }

        let dockElement = AXUIElementCreateApplication(dockApp.processIdentifier)
        var listRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockElement, kAXChildrenAttribute as CFString, &listRef) == .success,
              let dockList = (listRef as? [AXUIElement])?.first else {
            return nil
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockList, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return nil
        }

        for child in children {
            var urlRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, "AXURL" as CFString, &urlRef) == .success,
               let nsurl = urlRef as? NSURL,
               let targetBundle = Bundle(url: nsurl as URL) {
                if targetBundle.bundleIdentifier == app.bundleIdentifier ||
                   (app.bundleURL != nil && targetBundle.bundleURL == app.bundleURL) {
                    return child
                }
            }

            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &titleRef) == .success,
               let title = titleRef as? String,
               let name = app.localizedName,
               title.localizedCaseInsensitiveContains(name) {
                return child
            }
        }
        return nil
    }

    // MARK: - Termination Execution

    func terminateBackgroundServices(for app: NSRunningApplication, dockItem: AXUIElement?) {
        let myPid = NSRunningApplication.current.processIdentifier
        let targetPid = app.processIdentifier
        let bundleId = app.bundleIdentifier ?? "unknown"
        let bundleURL = app.bundleURL

        guard targetPid != myPid, targetPid > 100 else { return }
        guard !Self.protectedBundleIDs.contains(bundleId) else { return }

        let dockElementToUse = dockItem ?? findDockItem(for: app)
        AppLogger.app.info("Stopping background services for '\(bundleId, privacy: .public)'")
        AppLogger.app.info(
            "Quit target pid=\(targetPid, privacy: .public) dockItem=\(dockElementToUse != nil, privacy: .public)"
        )

        terminationQueue.async { [weak self] in
            guard let self = self else { return }

            // Snapshot the process tree while the main process is still alive:
            // once it exits its children reparent to launchd and can no longer
            // be reached from the pid we captured.
            var pidsToKill = self.getDescendantProcessIDs(rootPid: targetPid)
            if let bundleURL = bundleURL {
                let bundlePids = self.findProcessIDs(forBundleURL: bundleURL)
                pidsToKill.formUnion(bundlePids)
            }

            // The Dock entry goes away with the process, so the Dock's own
            // "Stop Running in Background" action has to run first.
            if let item = dockElementToUse {
                _ = self.triggerDockStopRunningInBackground(dockItem: item)
            }

            app.forceTerminate()

            pidsToKill.remove(myPid)
            pidsToKill.insert(targetPid)

            AppLogger.app.info(
                "Terminating \(pidsToKill.count, privacy: .public) processes for '\(bundleId, privacy: .public)'"
            )

            for pid in pidsToKill {
                kill(pid, SIGKILL)
            }
        }
    }

    /// Stops a macOS 27 "Running in Background" app that no longer resolves to
    /// an `NSRunningApplication`: the Dock's own stop action is the supported way
    /// to clear the background state, then every process whose executable lives
    /// inside the app bundle is killed so the icon actually disappears.
    func terminateLingeringDockItem(_ dockItem: AXUIElement) {
        var urlRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockItem, "AXURL" as CFString, &urlRef) == .success,
              let nsurl = urlRef as? NSURL else {
            AppLogger.app.info("Lingering Dock icon exposes no AXURL — cannot locate its bundle")
            return
        }
        let bundleURL = nsurl as URL
        guard let bundle = Bundle(url: bundleURL),
              let bundleId = bundle.bundleIdentifier,
              !Self.protectedBundleIDs.contains(bundleId) else {
            AppLogger.app.info("Refusing to stop a protected or unidentifiable bundle from a Dock icon")
            return
        }

        // Captured here so the termination queue never touches NSWorkspace.
        let runningPids = NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == bundleId }
            .map { $0.processIdentifier }

        AppLogger.app.info("Stopping lingering bundle '\(bundleId, privacy: .public)' from Dock icon")

        terminationQueue.async { [weak self] in
            guard let self = self else { return }

            _ = self.triggerDockStopRunningInBackground(dockItem: dockItem)

            var pidsToKill = Set(self.findProcessIDs(forBundleURL: bundleURL))
            pidsToKill.formUnion(runningPids)
            pidsToKill.remove(NSRunningApplication.current.processIdentifier)

            AppLogger.app.info(
                "Terminating \(pidsToKill.count, privacy: .public) lingering processes for '\(bundleId, privacy: .public)'"
            )

            for pid in pidsToKill {
                kill(pid, SIGKILL)
            }
        }
    }
}
