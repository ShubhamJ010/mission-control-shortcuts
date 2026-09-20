import ApplicationServices
import Cocoa

class MockAccessibilityService: AccessibilityServiceProtocol {
    var getElementCalledWith: CGPoint?
    var mockElement: AXUIElement?
    var mockWindow: AXUIElement?
    var mockApp: NSRunningApplication?
    var performActionCalledWith: (action: String, element: AXUIElement)?
    var setFrameCalledWith: (frame: CGRect, element: AXUIElement)?
    var isDockItemValue: Bool = false
    var focusWindowCalledWith: AXUIElement?
    var focusWindowReturnValue: Bool = true
    var setMinimizedCalledWith: (minimized: Bool, element: AXUIElement)?
    var setMinimizedReturnValue: Bool = true
    var mockFocusedWindow: AXUIElement?
    var mockAppWindows: [AXUIElement]?
    var mockCloseButton: AXUIElement?
    var mockTabCloseButton: AXUIElement?
    var mockDocumentPath: String?
    var mockWindowTitle: String?
    var mockMinimizeButton: AXUIElement?
    var mockMinimizedElements: Set<AXUIElement> = []

    var getElementCallCount: Int = 0
    var getWindowCallCount: Int = 0
    var getFrameCallCount: Int = 0

    func getElement(at point: CGPoint) -> AXUIElement? {
        getElementCallCount += 1
        getElementCalledWith = point
        return mockElement
    }

    func getWindow(for _: AXUIElement) -> AXUIElement? {
        getWindowCallCount += 1
        return mockWindow
    }

    var mockWindowForWindowID: [CGWindowID: AXUIElement] = [:]
    func getWindow(forWindowID windowID: CGWindowID) -> AXUIElement? {
        mockWindowForWindowID[windowID] ?? mockWindow
    }

    var mockPreviewTile: (tileElement: AXUIElement, windowID: CGWindowID)?
    func getMissionControlPreviewTile(for element: AXUIElement) -> (tileElement: AXUIElement, windowID: CGWindowID)? {
        mockPreviewTile
    }

    func performAction(_ action: String, on element: AXUIElement) -> Bool {
        performActionCalledWith = (action, element)
        return true
    }

    func getAttributeValue<T>(_ attribute: String, for element: AXUIElement) -> T? {
        if attribute == kAXFocusedWindowAttribute, let window = mockFocusedWindow {
            return window as? T
        }
        if attribute == kAXWindowsAttribute, let windows = mockAppWindows {
            return windows as? T
        }
        if attribute == kAXCloseButtonAttribute {
            return mockCloseButton as? T
        }
        if attribute == kAXMinimizeButtonAttribute {
            return mockMinimizeButton as? T
        }
        if attribute == kAXMinimizedAttribute {
            return mockMinimizedElements.contains(element) as? T
        }
        return nil
    }

    var mockFrame: CGRect?
    func getFrame(for _: AXUIElement) -> CGRect? {
        getFrameCallCount += 1
        return mockFrame ?? CGRect(x: 100, y: 100, width: 800, height: 600)
    }

    func setFrame(_ frame: CGRect, for element: AXUIElement) -> Bool {
        setFrameCalledWith = (frame, element)
        return true
    }

    func isDockItem(_: AXUIElement) -> Bool {
        isDockItemValue
    }

    func getAppFromDockItem(_: AXUIElement) -> NSRunningApplication? {
        mockApp
    }

    func findActiveTabCloseButton(in _: AXUIElement) -> AXUIElement? {
        mockTabCloseButton
    }

    func getAppFromElement(_: AXUIElement) -> NSRunningApplication? {
        mockApp
    }

    func setMinimized(_ minimized: Bool, for element: AXUIElement) -> Bool {
        setMinimizedCalledWith = (minimized, element)
        return setMinimizedReturnValue
    }

    func focusWindow(_ window: AXUIElement) -> Bool {
        focusWindowCalledWith = window
        return focusWindowReturnValue
    }

    func getDocumentPath(for _: AXUIElement) -> String? {
        mockDocumentPath
    }

    func getWindowTitle(for _: AXUIElement) -> String? {
        mockWindowTitle
    }

    var isDockAutoHideEnabled: Bool = false

    var isDockRegionValue: Bool = false
    func isDockRegion(at _: CGPoint) -> Bool {
        isDockRegionValue
    }

    var isFrontmostWindowValue: Bool = false
    var frontmostWindowCheckedWith: AXUIElement?
    func isFrontmostWindow(_ window: AXUIElement) -> Bool {
        frontmostWindowCheckedWith = window
        return isFrontmostWindowValue
    }

    var raiseWindowCalledWith: AXUIElement?
    var raiseWindowReturnValue: Bool = true
    func raiseWindow(_ window: AXUIElement) -> Bool {
        raiseWindowCalledWith = window
        return raiseWindowReturnValue
    }

    var activateCalledWithApp: NSRunningApplication?
    var activateCalledWithWindow: AXUIElement?
    var activateReturnValue: Bool = true
    @discardableResult
    func activate(app: NSRunningApplication, window: AXUIElement?) -> Bool {
        activateCalledWithApp = app
        activateCalledWithWindow = window
        return activateReturnValue
    }
}
