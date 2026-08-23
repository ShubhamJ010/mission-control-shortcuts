import ApplicationServices
import Cocoa
import os

/// Abstraction over the macOS Accessibility (AX) API so higher layers can be
/// unit-tested with a mock. All methods use Quartz screen coordinates
/// (origin at the top-left of the primary display) unless noted otherwise.
protocol AccessibilityServiceProtocol {
    /// Returns the topmost AX element at `point`, or `nil` if the hit test
    /// fails (e.g. over the desktop or when Accessibility is not granted).
    func getElement(at point: CGPoint) -> AXUIElement?

    /// Returns the AX window ancestor for `element`. If `element` is itself a
    /// window, it is returned directly.
    func getWindow(for element: AXUIElement) -> AXUIElement?

    /// Performs a named AX action (e.g. `kAXPressAction`) on `element`.
    /// Returns `true` if the action was accepted by the target app.
    func performAction(_ action: String, on element: AXUIElement) -> Bool

    /// Reads a typed AX attribute value (e.g. `kAXCloseButtonAttribute`).
    /// Returns `nil` when the attribute is missing or of a different type.
    func getAttributeValue<T>(_ attribute: String, for element: AXUIElement) -> T?

    /// Returns the element's frame in Quartz/AX coordinates.
    func getFrame(for element: AXUIElement) -> CGRect?

    /// Sets the element's position and size (in Quartz/AX coordinates).
    /// Returns `true` only if both position and size updates succeeded.
    func setFrame(_ frame: CGRect, for element: AXUIElement) -> Bool

    /// Returns `true` if `element` is (or is nested inside) a Dock item.
    func isDockItem(_ element: AXUIElement) -> Bool

    /// Resolves the `NSRunningApplication` represented by a Dock item hit.
    /// Returns `nil` if the element is not a Dock item or the app is not
    /// currently running.
    func getAppFromDockItem(_ element: AXUIElement) -> NSRunningApplication?

    /// Finds the AX close button of the selected tab in a tabbed window.
    /// Returns `nil` when the window has no accessible tab group.
    func findActiveTabCloseButton(in window: AXUIElement) -> AXUIElement?

    /// Makes `window` the application's focused (key) window via the
    /// `kAXFocusedAttribute` AX attribute. Best-effort: some apps ignore
    /// programmatic focus changes. Returns `true` if the attribute was set.
    func focusWindow(_ window: AXUIElement) -> Bool

    /// Resolves the `NSRunningApplication` that owns `element` via its PID.
    func getAppFromElement(_ element: AXUIElement) -> NSRunningApplication?

    /// Reads the document file path for `window` if exposed via `kAXDocumentAttribute`.
    func getDocumentPath(for window: AXUIElement) -> String?

    /// Reads the window title if exposed via `kAXTitleAttribute`.
    func getWindowTitle(for window: AXUIElement) -> String?

    /// Fast check: is the given Quartz point inside the Dock's AX list frame?
    /// Uses a cached Dock frame (refreshed on screen changes) to avoid per-frame AX queries.
    func isDockRegion(at point: CGPoint) -> Bool

    /// `true` when `window` is the focused window of the frontmost application.
    func isFrontmostWindow(_ window: AXUIElement) -> Bool
}

final class AccessibilityService: AccessibilityServiceProtocol {
    private let systemWide = AXUIElementCreateSystemWide()
    private static let maxTabSearchDepth = 8

    /// Cached `AXUIElement` for the Dock process, keyed by its pid so a Dock
    /// relaunch invalidates it. Created lazily; see `getDockAXElement()`.
    private var cachedDockElement: AXUIElement?
    private var cachedDockPID: pid_t = 0

    /// Cached frontmost-application element for `isFrontmostWindow`, keyed by
    /// pid. The title-bar hover path calls `isFrontmostWindow` up to 30×/s per
    /// gesture frame; without the cache each call allocated a fresh
    /// `AXUIElementCreateApplication`. The pid check invalidates on app switch.
    private var cachedFrontmostAppElement: AXUIElement?
    private var cachedFrontmostAppPID: pid_t = 0

    /// Cached bounding frame of the Dock's icon list. Refreshed lazily and on
    /// screen-configuration changes to avoid per-frame AX queries.
    private var cachedDockFrame: CGRect?
    private var screenObserver: NSObjectProtocol?

    /// Extra padding (pt) around the cached Dock frame treated as "hovering
    /// the Dock". Covers magnification growth and hover-bounce overflow.
    private static let dockFramePadding: CGFloat = 15

    /// How far outside the padded Dock frame the AX hit-test fallback may run.
    /// Beyond this radius the point cannot plausibly be over the Dock, so the
    /// expensive per-frame query is skipped entirely.
    private static let dockFallbackRadius: CGFloat = 80

    /// When `true`, `getAppFromDockItem` logs the Dock item's AX attributes and
    /// which resolution strategy matched. Flip on to verify Catalyst/Electron
    /// Dock icons (e.g. WhatsApp, Beeper) without spamming normal operation.
    /// Enabled by launching with `MCSC_DOCK_DIAG=1` in the environment.
    var dockDiagnosticsEnabled = false

    init() {
        if ProcessInfo.processInfo.environment["MCSC_DOCK_DIAG"] == "1" {
            dockDiagnosticsEnabled = true
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cachedDockFrame = nil
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    /// Returns a cached `AXUIElement` for the Dock process, creating it on
    /// first use and re-creating it only if the Dock process was relaunched
    /// (detected via pid change). Caching avoids per-call element allocation.
    private func getDockAXElement() -> AXUIElement? {
        if let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first {
            if cachedDockElement == nil || cachedDockPID != dockApp.processIdentifier {
                cachedDockElement = AXUIElementCreateApplication(dockApp.processIdentifier)
                cachedDockPID = dockApp.processIdentifier
            }
            return cachedDockElement
        }
        return nil
    }

    func getElement(at point: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)

        if result == .success, let element {
            return element
        }

        // When system-wide AX hit test returns -25200 (kAXErrorCannotComplete) on Dock,
        // hit-test directly against the Dock application AXUIElement.
        if let dockElement = getDockAXElement() {
            var dockChild: AXUIElement?
            if AXUIElementCopyElementAtPosition(dockElement, Float(point.x), Float(point.y), &dockChild) == .success,
               let dockChild {
                return dockChild
            }
        }

        return nil
    }

    func getWindow(for element: AXUIElement) -> AXUIElement? {
        var window: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &window)

        if result == .success, let window, CFGetTypeID(window) == AXUIElementGetTypeID() {
            // TypeID verified above; `as?` cannot check CF types.
            return unsafeDowncast(window, to: AXUIElement.self)
        }

        // If the element itself is a window
        var role: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
           (role as? String) == kAXWindowRole {
            return element
        }

        return nil
    }

    func performAction(_ action: String, on element: AXUIElement) -> Bool {
        let result = AXUIElementPerformAction(element, action as CFString)
        return result == .success
    }

    func getAttributeValue<T>(_ attribute: String, for element: AXUIElement) -> T? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? T
    }

    func isDockItem(_ element: AXUIElement) -> Bool {
        // Walk up the AX hierarchy: the hit element over a Dock icon is often a
        // child (badge / AXImage) rather than the AXDockItem itself, especially
        // for non-native apps (Mac Catalyst, Electron). Resolve against the
        // nearest Dock item ancestor instead of demanding the hit be one.
        dockItemAncestor(for: element) != nil
    }

    /// Returns the nearest `AXDockItem` at or above `element`, climbing the
    /// parent chain up to a bounded depth. Returns `nil` if no Dock item is
    /// found — it can never escape into a window or app element.
    func dockItemAncestor(for element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        var depth = 0
        while let el = current, depth < 8 {
            var role: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role) == .success,
               (role as? String) == "AXDockItem" {
                return el
            }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &parent) == .success,
                  let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else {
                return nil
            }
            // TypeID verified above; `as?` cannot check CF types.
            current = unsafeDowncast(parent, to: AXUIElement.self)
            depth += 1
        }
        return nil
    }

    func getAppFromDockItem(_ element: AXUIElement) -> NSRunningApplication? {
        // Resolve against the actual Dock item (the hit element may be a child
        // such as a notification badge), then map it to a running app.
        guard let dockItem = dockItemAncestor(for: element) else {
            if dockDiagnosticsEnabled {
                AppLogger.dock.debug("no AXDockItem ancestor found for hit element")
            }
            return nil
        }

        let runningApps = NSWorkspace.shared.runningApplications

        // Primary: the Dock item often exposes its app URL. Matching by bundle
        // identifier is framework-agnostic and works for Mac Catalyst / Electron
        // apps whose AXTitle does not equal the running app's localizedName.
        if let url: NSURL = getAttributeValue(kAXURLAttribute, for: dockItem),
           let bundle = Bundle(url: url as URL),
           let app = runningApps.first(where: { $0.bundleIdentifier == bundle.bundleIdentifier }) {
            if dockDiagnosticsEnabled {
                AppLogger.dock
                    .debug(
                        "resolved via AXURL → bundleID '\(bundle.bundleIdentifier ?? "?", privacy: .public)' → '\(app.localizedName ?? "?", privacy: .public)'"
                    )
            }
            return app
        }

        // Fallback: tolerant (case / diacritic / whitespace-insensitive) title
        // match. The exact-equality check used previously failed for any app
        // whose Dock AXTitle differed from localizedName.
        guard let title: String = getAttributeValue(kAXTitleAttribute, for: dockItem) else {
            if dockDiagnosticsEnabled {
                let role = getAttributeValue(kAXRoleAttribute, for: dockItem) ?? "?"
                let subrole = getAttributeValue(kAXSubroleAttribute, for: dockItem) ?? "?"
                let url = (getAttributeValue(kAXURLAttribute, for: dockItem) as NSURL?)?.absoluteString ?? "nil"
                let message = "\(role), \(subrole), \(url)"
                AppLogger.dock
                    .debug("AXURL match failed; AXTitle missing — \(message, privacy: .public)")
            }
            return nil
        }
        let normalizedTitle = title.trimmingCharacters(in: .whitespaces)
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if let app = runningApps.first(where: {
            normalizedTitle.compare(($0.localizedName ?? "").trimmingCharacters(in: .whitespaces),
                                    options: opts) == .orderedSame
        }) {
            if dockDiagnosticsEnabled {
                AppLogger.dock
                    .debug(
                        "resolved via tolerant AXTitle '\(normalizedTitle, privacy: .public)' → '\(app.localizedName ?? "?", privacy: .public)'"
                    )
            }
            return app
        }
        if dockDiagnosticsEnabled {
            let role: String? = getAttributeValue(kAXRoleAttribute, for: dockItem)
            let subrole: String? = getAttributeValue(kAXSubroleAttribute, for: dockItem)
            let url: NSURL? = getAttributeValue(kAXURLAttribute, for: dockItem)
            // swiftformat:disable all
            // swiftlint:disable:next line_length
            AppLogger.dock.debug("NO match — AXTitle='\(title, privacy: .public)' role='\(role ?? "?", privacy: .public)' subrole='\(subrole ?? "?", privacy: .public)' AXURL=\(url?.absoluteString ?? "nil", privacy: .public)")
            // swiftformat:enable all
        }
        return nil
    }

    /// Finds the AX close button of the selected tab in a tabbed window.
    ///
    /// Browsers nest the `AXTabGroup` at different depths: Chrome places it one
    /// level under an `AXGroup` rather than as a direct child of the window, so
    /// a shallow, single-level scan misses it and forces the unreliable Cmd+W
    /// fallback. We therefore descend the AX subtree — but only to a bounded
    /// depth and skipping the (potentially huge) web-content area, so the scan
    /// stays cheap and can never hang on a large page.
    func findActiveTabCloseButton(in window: AXUIElement) -> AXUIElement? {
        findTabCloseButton(in: window, depth: 0)
    }

    /// Recursively searches `element`'s subtree for an `AXTabGroup` and returns
    /// the close button of its selected tab. Depth is bounded by
    /// `maxTabSearchDepth`; `AXWebArea` nodes are pruned so the search never
    /// walks an entire rendered page.
    private func findTabCloseButton(in element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth < Self.maxTabSearchDepth else { return nil }
        guard let children: [AXUIElement] = getAttributeValue(kAXChildrenAttribute, for: element) else { return nil }

        // Pass 1: is there a tab group at this level?
        for child in children {
            guard let role: String = getAttributeValue(kAXRoleAttribute, for: child) else { continue }
            if role == "AXTabGroup" {
                if let btn = closeButtonForSelectedTab(in: child) {
                    return btn
                }
            }
        }

        // Pass 2: descend, but never traverse the (enormous) web content area.
        for child in children {
            guard let role: String = getAttributeValue(kAXRoleAttribute, for: child) else { continue }
            if role == "AXWebArea" {
                continue
            }
            if let btn = findTabCloseButton(in: child, depth: depth + 1) {
                return btn
            }
        }
        return nil
    }

    /// Returns the close `AXButton` of the selected (`AXRadioButton` with
    /// `kAXValueAttribute == true`) tab within a tab group, or `nil`.
    private func closeButtonForSelectedTab(in tabGroup: AXUIElement) -> AXUIElement? {
        guard let tabs: [AXUIElement] = getAttributeValue(kAXChildrenAttribute, for: tabGroup) else { return nil }
        for tab in tabs {
            guard let tabRole: String = getAttributeValue(kAXRoleAttribute, for: tab),
                  tabRole == "AXRadioButton" else { continue }
            let isSelected: Bool? = getAttributeValue(kAXValueAttribute, for: tab)
            if isSelected == true {
                if let tabChildren: [AXUIElement] = getAttributeValue(kAXChildrenAttribute, for: tab) {
                    for tabChild in tabChildren {
                        if let childRole: String = getAttributeValue(kAXRoleAttribute, for: tabChild),
                           childRole == "AXButton" {
                            return tabChild
                        }
                    }
                }
            }
        }
        return nil
    }

    func getAppFromElement(_ element: AXUIElement) -> NSRunningApplication? {
        var pid: pid_t = 0
        let result = AXUIElementGetPid(element, &pid)
        guard result == .success else { return nil }
        return NSRunningApplication(processIdentifier: pid)
    }

    /// Makes `window` the application's focused (key) window. Used to steer the
    /// Cmd+W fallback path toward the window under the user's cursor in Mission
    /// Control rather than the app's previously focused key window.
    func focusWindow(_ window: AXUIElement) -> Bool {
        let result = AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        return result == .success
    }

    /// Retrieves the current frame (origin and size in Quartz AX coordinates) for an accessibility element.
    func getFrame(for element: AXUIElement) -> CGRect? {
        var posVal: CFTypeRef?
        var sizeVal: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posVal) == .success,
              let posVal, CFGetTypeID(posVal) == AXValueGetTypeID(),
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeVal) == .success,
              let sizeVal, CFGetTypeID(sizeVal) == AXValueGetTypeID() else {
            return nil
        }
        var point = CGPoint.zero
        var size = CGSize.zero
        // TypeIDs verified above; `as?` cannot check CF types.
        guard AXValueGetValue(unsafeDowncast(posVal, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeDowncast(sizeVal, to: AXValue.self), .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: point, size: size)
    }

    func setFrame(_ frame: CGRect, for element: AXUIElement) -> Bool {
        // Set position first, then size — some apps fail if done in one shot
        var position = CGPoint(x: frame.origin.x, y: frame.origin.y)
        guard let posValue = AXValueCreate(.cgPoint, &position) else { return false }
        let posResult = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, posValue)

        var size = CGSize(width: frame.width, height: frame.height)
        guard let sizeValue = AXValueCreate(.cgSize, &size) else { return false }
        let sizeResult = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)

        return posResult == .success && sizeResult == .success
    }

    func getDocumentPath(for window: AXUIElement) -> String? {
        if let doc: String = getAttributeValue(kAXDocumentAttribute, for: window) {
            if let url = URL(string: doc), url.isFileURL {
                return url.path
            }
            if doc.hasPrefix("/") {
                return doc
            }
        }
        return nil
    }

    func getWindowTitle(for window: AXUIElement) -> String? {
        getAttributeValue(kAXTitleAttribute, for: window)
    }

    /// Re-queries the Dock's icon-list frame (`AXList` child) and caches it.
    /// Falls back to the Dock application element's own frame if no list
    /// child is found. Called lazily and on screen-configuration changes.
    private func refreshDockFrame() {
        guard let dockElement = getDockAXElement() else {
            cachedDockFrame = nil
            return
        }
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(dockElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                var roleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef) == .success,
                   (roleRef as? String) == "AXList",
                   let frame = getFrame(for: child) {
                    cachedDockFrame = frame
                    return
                }
            }
        }
        if let frame = getFrame(for: dockElement) {
            cachedDockFrame = frame
        }
    }

    /// Fast check: is the given Quartz point inside (or near) the Dock?
    ///
    /// Three-tier strategy, cheapest first:
    /// 1. Cached Dock list frame + padding — pure geometry, no AX calls.
    /// 2. Direct AX hit-test against the Dock process — covers auto-hidden or
    ///    magnified Docks whose live frame exceeds the cached one. Only run
    ///    when the point is plausibly near the cached frame (`dockFallbackRadius`).
    /// 3. Otherwise `false` without touching the AX API, keeping the per-gesture-
    ///    frame cost at zero for cursors far from the Dock.
    func isDockRegion(at point: CGPoint) -> Bool {
        let paddedFrame = cachedDockFrame?.insetBy(dx: -Self.dockFramePadding, dy: -Self.dockFramePadding)
        if let paddedFrame {
            if paddedFrame.contains(point) {
                return true
            }
            // Point is outside the cached frame; only pay for the AX fallback
            // if it could still be over a magnified / auto-hidden Dock.
            guard paddedFrame.insetBy(dx: -Self.dockFallbackRadius, dy: -Self.dockFallbackRadius).contains(point) else {
                return false
            }
        } else {
            refreshDockFrame()
            if let frame = cachedDockFrame,
               frame.insetBy(dx: -Self.dockFramePadding, dy: -Self.dockFramePadding).contains(point) {
                return true
            }
        }
        if let dockElement = getDockAXElement() {
            var hit: AXUIElement?
            if AXUIElementCopyElementAtPosition(dockElement, Float(point.x), Float(point.y), &hit) == .success,
               let hit {
                return isDockItem(hit)
            }
        }
        return false
    }

    /// `true` when `window` is the focused window of the frontmost application.
    /// Two cheap AX reads (app element + focused-window attribute); only called
    /// when the title-bar feature is enabled and Mission Control is closed.
    /// The application element is cached per pid — `AXUIElementCreateApplication`
    /// on every gesture frame was measurable allocator churn.
    func isFrontmostWindow(_ window: AXUIElement) -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }
        if cachedFrontmostAppElement == nil || cachedFrontmostAppPID != frontApp.processIdentifier {
            cachedFrontmostAppElement = AXUIElementCreateApplication(frontApp.processIdentifier)
            cachedFrontmostAppPID = frontApp.processIdentifier
        }
        guard let appElement = cachedFrontmostAppElement,
              let focusedWindow: AXUIElement = getAttributeValue(kAXFocusedWindowAttribute, for: appElement) else {
            return false
        }
        return CFEqual(focusedWindow, window)
    }
}
