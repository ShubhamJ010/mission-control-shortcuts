import ApplicationServices
import Cocoa

extension AccessibilityService {
    /// Mission Control preview tile attribute identifying the target window ID (used by WindowManager).
    static let axMissionControlWindowIDAttribute = "wid"
    private static let maxPreviewTileDepth = 8

    /// Resolves a Mission Control preview tile element and its window ID if `element` (or an ancestor) represents one.
    func getMissionControlPreviewTile(for element: AXUIElement) -> (tileElement: AXUIElement, windowID: CGWindowID)? {
        var current: AXUIElement? = element
        var depth = 0
        while let el = current, depth < 10 {
            if let widNum: NSNumber = getAttributeValue(Self.axMissionControlWindowIDAttribute, for: el) {
                return (el, CGWindowID(widNum.uint32Value))
            }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &parent) == .success,
                  let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else {
                break
            }
            current = unsafeDowncast(parent, to: AXUIElement.self)
            depth += 1
        }
        return nil
    }

    /// Resolves a Mission Control preview tile element and its window ID at `point` in Quartz/AX coordinates.
    /// When `matchingWindowIDs` is provided, candidate tiles are filtered to match the active desktop space.
    /// If direct coordinate hit-testing hits an off-screen/masked tile from an inactive space, scans
    /// WindowManager's preview tile hierarchy to match the active space.
    func getMissionControlPreviewTile(
        at point: CGPoint,
        matchingWindowIDs: Set<CGWindowID>? = nil
    ) -> (tileElement: AXUIElement, windowID: CGWindowID)? {
        if let matchingWindowIDs, matchingWindowIDs.isEmpty {
            return nil
        }
        // 1. Direct hit-test WindowManager first (it owns Mission Control layer 19 on macOS 27)
        if let wmElement = getWindowManagerAXElement() {
            var wmChild: AXUIElement?
            if AXUIElementCopyElementAtPosition(wmElement, Float(point.x), Float(point.y), &wmChild) == .success,
               let wmChild,
               let preview = getMissionControlPreviewTile(for: wmChild) {
                if matchingWindowIDs?.contains(preview.windowID) ?? true {
                    return preview
                }
            }

            // On macOS 27, WindowManager hosts preview tiles for all spaces in its AX tree.
            // If the element hit-tested at point belongs to another space or was masked,
            // scan WindowManager's preview tiles to find the matching tile on the active desktop.
            if let matchingWindowIDs {
                if let preview = findMatchingPreviewTile(
                    in: wmElement,
                    at: point,
                    matchingWindowIDs: matchingWindowIDs
                ) {
                    return preview
                }
            }
        }

        // 2. Fall back to systemWide element hit-test
        if let hitElement = getElement(at: point),
           let preview = getMissionControlPreviewTile(for: hitElement) {
            if matchingWindowIDs?.contains(preview.windowID) ?? true {
                return preview
            }
        }

        // 3. Fall back to Dock element hit-test (classic Dock Exposé)
        if let dockElement = getDockAXElement() {
            var dockChild: AXUIElement?
            if AXUIElementCopyElementAtPosition(dockElement, Float(point.x), Float(point.y), &dockChild) == .success,
               let dockChild,
               let preview = getMissionControlPreviewTile(for: dockChild) {
                if matchingWindowIDs?.contains(preview.windowID) ?? true {
                    return preview
                }
            }
        }

        return nil
    }

    /// Recursively scans WindowManager AX children to find a preview tile matching the active desktop space.
    ///
    /// Required on macOS 27 because WindowManager retains preview tiles for all spaces concurrently in its
    /// AX hierarchy, causing direct coordinate hit-tests to occasionally hit off-screen tiles from inactive spaces.
    private func findMatchingPreviewTile(
        in parent: AXUIElement,
        at point: CGPoint,
        matchingWindowIDs: Set<CGWindowID>,
        depth: Int = 0
    ) -> (tileElement: AXUIElement, windowID: CGWindowID)? {
        guard depth < Self.maxPreviewTileDepth else { return nil }
        guard let children: [AXUIElement] = getAttributeValue(kAXChildrenAttribute, for: parent) else {
            return nil
        }
        for child in children {
            if let preview = getMissionControlPreviewTile(for: child) {
                if matchingWindowIDs.contains(preview.windowID),
                   let frame = getFrame(for: preview.tileElement),
                   frame.contains(point) {
                    return preview
                }
                continue
            }
            if let found = findMatchingPreviewTile(
                in: child,
                at: point,
                matchingWindowIDs: matchingWindowIDs,
                depth: depth + 1
            ) {
                return found
            }
        }
        return nil
    }

    /// Resolves the native close button AXUIElement in a Mission Control preview tile, if present.
    func getPreviewCloseButton(for tileElement: AXUIElement) -> AXUIElement? {
        if let closeBtn: AXUIElement = getAttributeValue(kAXCloseButtonAttribute, for: tileElement) {
            return closeBtn
        }
        if let children: [AXUIElement] = getAttributeValue(kAXChildrenAttribute, for: tileElement) {
            for child in children {
                let subrole: String? = getAttributeValue(kAXSubroleAttribute, for: child)
                if subrole == kAXCloseButtonSubrole || subrole == "AXCloseButton" {
                    return child
                }
                let role: String? = getAttributeValue(kAXRoleAttribute, for: child)
                if role == kAXButtonRole {
                    let title: String? = getAttributeValue(kAXTitleAttribute, for: child)
                    if let title, title.localizedCaseInsensitiveContains("close") {
                        return child
                    }
                }
            }
        }
        return nil
    }

    /// Resolves the frame of a native close button in a Mission Control preview tile, if present.
    func getPreviewCloseButtonFrame(for tileElement: AXUIElement) -> CGRect? {
        if let button = getPreviewCloseButton(for: tileElement),
           let frame = getFrame(for: button), !frame.isEmpty {
            return frame
        }
        return nil
    }
}
