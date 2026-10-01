import ApplicationServices
import Cocoa

// MARK: - Size Actions

/// Expands the window at `point` to fill its screen's visible bounds (excluding dock and menu bar).
struct FillScreenAction: ShortcutAction {
    func perform(at point: CGPoint, service: AccessibilityServiceProtocol) {
        guard let element = service.getElement(at: point),
              let window = service.getWindow(for: element) else { return }
        perform(window: window, at: point, service: service)
    }

    func perform(window: AXUIElement, at point: CGPoint, service: AccessibilityServiceProtocol) {
        guard let screen = ScreenGeometry.screenContaining(axPoint: point) else { return }
        let axScreenBounds = ScreenGeometry.axVisibleBounds(for: screen)
        _ = service.setFrame(axScreenBounds, for: window)
    }
}

/// Increases the size of the target window by 33% (anchored at center, clamped to screen bounds).
struct MakeLargerAction: ShortcutAction {
    /// Multiplier used to scale window dimensions (+33%).
    private let scaleFactor: CGFloat = 1.33

    func perform(at point: CGPoint, service: AccessibilityServiceProtocol) {
        guard let element = service.getElement(at: point),
              let window = service.getWindow(for: element) else { return }
        perform(window: window, at: point, service: service)
    }

    func perform(window: AXUIElement, at point: CGPoint, service: AccessibilityServiceProtocol) {
        guard let currentFrame = service.getFrame(for: window),
              let screen = ScreenGeometry.screenContaining(axPoint: point) else { return }
        let axScreenBounds = ScreenGeometry.axVisibleBounds(for: screen)

        let targetWidth = (currentFrame.width * scaleFactor).rounded()
        let targetHeight = (currentFrame.height * scaleFactor).rounded()

        // Clamp dimensions to screen bounds
        let newWidth = min(targetWidth, axScreenBounds.width)
        let newHeight = min(targetHeight, axScreenBounds.height)

        // Expand symmetrically from center
        var newX = (currentFrame.origin.x - (newWidth - currentFrame.width) / 2.0).rounded()
        var newY = (currentFrame.origin.y - (newHeight - currentFrame.height) / 2.0).rounded()

        // Clamp position within screen boundaries
        if newX < axScreenBounds.minX {
            newX = axScreenBounds.minX
        } else if newX + newWidth > axScreenBounds.maxX {
            newX = axScreenBounds.maxX - newWidth
        }

        if newY < axScreenBounds.minY {
            newY = axScreenBounds.minY
        } else if newY + newHeight > axScreenBounds.maxY {
            newY = axScreenBounds.maxY - newHeight
        }

        let newFrame = CGRect(x: newX, y: newY, width: newWidth, height: newHeight)
        _ = service.setFrame(newFrame, for: window)
    }
}

/// Shrinks the window at `point` by ~33% (anchored at center, clamped to a
/// minimum size of 200×100 pt and to screen bounds). Uses 1/1.33 so a
/// Make Larger → Make Smaller cycle restores the original size.
struct MakeSmallerAction: ShortcutAction {
    /// Multiplier used to scale window dimensions (÷33% ≈ ×0.75).
    private let scaleFactor: CGFloat = 1.0 / 1.33
    private let minWidth: CGFloat = 200
    private let minHeight: CGFloat = 100

    func perform(at point: CGPoint, service: AccessibilityServiceProtocol) {
        guard let element = service.getElement(at: point),
              let window = service.getWindow(for: element) else { return }
        perform(window: window, at: point, service: service)
    }

    func perform(window: AXUIElement, at point: CGPoint, service: AccessibilityServiceProtocol) {
        guard let currentFrame = service.getFrame(for: window),
              let screen = ScreenGeometry.screenContaining(axPoint: point) else { return }
        let axScreenBounds = ScreenGeometry.axVisibleBounds(for: screen)

        let targetWidth = max((currentFrame.width * scaleFactor).rounded(), minWidth)
        let targetHeight = max((currentFrame.height * scaleFactor).rounded(), minHeight)

        // Clamp dimensions to screen bounds
        let newWidth = min(targetWidth, axScreenBounds.width)
        let newHeight = min(targetHeight, axScreenBounds.height)

        // Shrink symmetrically towards center
        var newX = (currentFrame.origin.x + (currentFrame.width - newWidth) / 2.0).rounded()
        var newY = (currentFrame.origin.y + (currentFrame.height - newHeight) / 2.0).rounded()

        // Clamp position within screen boundaries
        if newX < axScreenBounds.minX {
            newX = axScreenBounds.minX
        } else if newX + newWidth > axScreenBounds.maxX {
            newX = axScreenBounds.maxX - newWidth
        }

        if newY < axScreenBounds.minY {
            newY = axScreenBounds.minY
        } else if newY + newHeight > axScreenBounds.maxY {
            newY = axScreenBounds.maxY - newHeight
        }

        let newFrame = CGRect(x: newX, y: newY, width: newWidth, height: newHeight)
        _ = service.setFrame(newFrame, for: window)
    }
}

struct ReasonableSizeAction: ShortcutAction {
    func perform(at point: CGPoint, service: AccessibilityServiceProtocol) {
        guard let element = service.getElement(at: point),
              let window = service.getWindow(for: element) else { return }
        perform(window: window, at: point, service: service)
    }

    func perform(window: AXUIElement, at point: CGPoint, service: AccessibilityServiceProtocol) {
        guard let screen = ScreenGeometry.screenContaining(axPoint: point) else { return }
        let axBounds = ScreenGeometry.axVisibleBounds(for: screen)
        let w = (axBounds.width * 0.604).rounded()
        let h = (axBounds.height * 0.58).rounded()
        let x = (axBounds.origin.x + (axBounds.width - w) / 2).rounded()
        let y = (axBounds.origin.y + (axBounds.height - h) / 2).rounded()
        _ = service.setFrame(CGRect(x: x, y: y, width: w, height: h), for: window)
    }
}

struct AlmostMaximizeAction: ShortcutAction {
    func perform(at point: CGPoint, service: AccessibilityServiceProtocol) {
        guard let element = service.getElement(at: point),
              let window = service.getWindow(for: element) else { return }
        perform(window: window, at: point, service: service)
    }

    func perform(window: AXUIElement, at point: CGPoint, service: AccessibilityServiceProtocol) {
        guard let screen = ScreenGeometry.screenContaining(axPoint: point) else { return }
        let axBounds = ScreenGeometry.axVisibleBounds(for: screen)
        let w = (axBounds.width * 0.904).rounded()
        let h = (axBounds.height * 0.872).rounded()
        let x = (axBounds.origin.x + (axBounds.width - w) / 2).rounded()
        let y = (axBounds.origin.y + (axBounds.height - h) / 2).rounded()
        _ = service.setFrame(CGRect(x: x, y: y, width: w, height: h), for: window)
    }
}

// MARK: - Native Snap Actions

enum SnapPosition {
    case leftTwoThirds
    case leftHalf
    case leftThird
    case rightTwoThirds
    case rightHalf
    case rightThird

    func frame(for visibleBounds: CGRect) -> CGRect {
        switch self {
        case .leftTwoThirds:
            let w = (visibleBounds.width * 2.0 / 3.0).rounded()
            return CGRect(x: visibleBounds.origin.x, y: visibleBounds.origin.y, width: w, height: visibleBounds.height)
        case .leftHalf:
            let w = (visibleBounds.width / 2.0).rounded()
            return CGRect(x: visibleBounds.origin.x, y: visibleBounds.origin.y, width: w, height: visibleBounds.height)
        case .leftThird:
            let w = (visibleBounds.width / 3.0).rounded()
            return CGRect(x: visibleBounds.origin.x, y: visibleBounds.origin.y, width: w, height: visibleBounds.height)
        case .rightTwoThirds:
            let leftW = (visibleBounds.width / 3.0).rounded()
            let w = visibleBounds.width - leftW
            let x = visibleBounds.origin.x + leftW
            return CGRect(x: x, y: visibleBounds.origin.y, width: w, height: visibleBounds.height)
        case .rightHalf:
            let leftW = (visibleBounds.width / 2.0).rounded()
            let w = visibleBounds.width - leftW
            let x = visibleBounds.origin.x + leftW
            return CGRect(x: x, y: visibleBounds.origin.y, width: w, height: visibleBounds.height)
        case .rightThird:
            let w = (visibleBounds.width / 3.0).rounded()
            let x = visibleBounds.origin.x + visibleBounds.width - w
            return CGRect(x: x, y: visibleBounds.origin.y, width: w, height: visibleBounds.height)
        }
    }
}

enum CycleDirection {
    case left
    case right
}

final class CycleTracker {
    static let shared = CycleTracker()
    private var lastWindowID: CGWindowID?
    private var lastDirection: CycleDirection?
    private var lastIndex: Int = 0
    private var lastTimestamp: TimeInterval = 0

    private init() {}

    func nextPosition(
        direction: CycleDirection,
        windowID: CGWindowID?,
        currentFrame: CGRect?,
        visibleBounds: CGRect
    ) -> SnapPosition {
        let sequence: [SnapPosition] = switch direction {
        case .left:
            [.leftHalf, .leftTwoThirds, .leftThird]
        case .right:
            [.rightHalf, .rightTwoThirds, .rightThird]
        }

        let now = ProcessInfo.processInfo.systemUptime
        if let windowID, let lastWindowID, windowID == lastWindowID,
           let lastDirection, lastDirection == direction,
           now - lastTimestamp < 2.5 {
            let nextIdx = (lastIndex + 1) % sequence.count
            self.lastIndex = nextIdx
            self.lastTimestamp = now
            return sequence[nextIdx]
        }

        var selectedIdx = 0
        if let current = currentFrame {
            let tolerance: CGFloat = 25.0
            for (index, position) in sequence.enumerated() {
                let expected = position.frame(for: visibleBounds)
                if abs(current.origin.x - expected.origin.x) <= tolerance &&
                   abs(current.width - expected.width) <= tolerance {
                    selectedIdx = (index + 1) % sequence.count
                    break
                }
            }
        }

        self.lastWindowID = windowID
        self.lastDirection = direction
        self.lastIndex = selectedIdx
        self.lastTimestamp = now
        return sequence[selectedIdx]
    }
}

private func performCycleSnapAction(
    _ direction: CycleDirection,
    on window: AXUIElement,
    at point: CGPoint,
    service: AccessibilityServiceProtocol
) {
    let currentFrame = service.getFrame(for: window)
    let anchor = currentFrame.map { CGPoint(x: $0.midX, y: $0.midY) } ?? point
    guard let screen = ScreenGeometry.screenContaining(axPoint: point) ?? ScreenGeometry.screenContaining(axPoint: anchor) else { return }
    let visibleBounds = ScreenGeometry.axVisibleBounds(for: screen)

    var wid: CGWindowID = 0
    _ = _AXUIElementGetWindow(window, &wid)
    let effectiveID = wid != 0 ? wid : CGWindowID(truncatingIfNeeded: CFHash(window))

    let position = CycleTracker.shared.nextPosition(
        direction: direction,
        windowID: effectiveID,
        currentFrame: currentFrame,
        visibleBounds: visibleBounds
    )
    _ = service.setFrame(position.frame(for: visibleBounds), for: window)
}

private func performCycleSnapAction(
    _ direction: CycleDirection,
    at point: CGPoint,
    service: AccessibilityServiceProtocol
) {
    guard let element = service.getElement(at: point),
          let window = service.getWindow(for: element) else { return }
    performCycleSnapAction(direction, on: window, at: point, service: service)
}

struct LeftCycleSnapAction: ShortcutAction {
    func perform(at point: CGPoint, service: AccessibilityServiceProtocol) {
        performCycleSnapAction(.left, at: point, service: service)
    }

    func perform(window: AXUIElement, at point: CGPoint, service: AccessibilityServiceProtocol) {
        performCycleSnapAction(.left, on: window, at: point, service: service)
    }
}

struct RightCycleSnapAction: ShortcutAction {
    func perform(at point: CGPoint, service: AccessibilityServiceProtocol) {
        performCycleSnapAction(.right, at: point, service: service)
    }

    func perform(window: AXUIElement, at point: CGPoint, service: AccessibilityServiceProtocol) {
        performCycleSnapAction(.right, on: window, at: point, service: service)
    }
}
