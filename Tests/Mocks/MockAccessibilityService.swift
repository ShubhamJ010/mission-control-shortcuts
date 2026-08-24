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
    var mockFocusedWindow: AXUIElement?
    var mockAppWindows: [AXUIElement]?
    var mockCloseButton: AXUIElement?
    var mockTabCloseButton: AXUIElement?
    var mockDocumentPath: String?
    var mockWindowTitle: String?

    func getElement(at point: CGPoint) -> AXUIElement? {
        getElementCalledWith = point
        return mockElement
    }

    func getWindow(for _: AXUIElement) -> AXUIElement? {
        mockWindow
    }

    func performAction(_ action: String, on element: AXUIElement) -> Bool {
        performActionCalledWith = (action, element)
        return true
    }

    func getAttributeValue<T>(_ attribute: String, for _: AXUIElement) -> T? {
        if attribute == kAXFocusedWindowAttribute, let window = mockFocusedWindow {
            return window as? T
        }
        if attribute == kAXWindowsAttribute, let windows = mockAppWindows {
            return windows as? T
        }
        if attribute == kAXCloseButtonAttribute {
            return mockCloseButton as? T
        }
        return nil
    }

    func getFrame(for _: AXUIElement) -> CGRect? {
        CGRect(x: 100, y: 100, width: 800, height: 600)
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
}
