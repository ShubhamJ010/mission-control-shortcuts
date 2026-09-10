import Cocoa

// MARK: - Size Actions

/// Expands the window at `point` to fill its screen's full bounds.
struct FillScreenAction: ShortcutAction {
    func perform(at point: CGPoint, service: AccessibilityServiceProtocol) {
        guard let element = service.getElement(at: point),
              let window = service.getWindow(for: element) else { return }

        guard let screen = ScreenGeometry.screenContaining(axPoint: point) else { return }
        let axScreenBounds = ScreenGeometry.axBounds(for: screen)
        _ = service.setFrame(axScreenBounds, for: window)
    }
}

/// Increases the size of the target window by 33% (anchored at center, clamped to screen bounds).
struct MakeLargerAction: ShortcutAction {
    /// Multiplier used to scale window dimensions (+33%).
    private let scaleFactor: CGFloat = 1.33

    func perform(at point: CGPoint, service: AccessibilityServiceProtocol) {
        guard let element = service.getElement(at: point),
              let window = service.getWindow(for: element),
              let currentFrame = service.getFrame(for: window) else { return }

        guard let screen = ScreenGeometry.screenContaining(axPoint: point) else { return }
        let axScreenBounds = ScreenGeometry.axBounds(for: screen)

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

        _ = service.setFrame(CGRect(x: newX, y: newY, width: newWidth, height: newHeight), for: window)
    }
}

/// Shrinks the window at `point` by ~33% (anchored at center, clamped to a
/// minimum size of 200×100 pt and to screen bounds). Uses 1/1.33 so a
/// Make Larger → Make Smaller cycle restores the original size.
struct MakeSmallerAction: ShortcutAction {
    /// Multiplier used to scale window dimensions (÷33% ≈ ×0.75).
    private let scaleFactor: CGFloat = 1.0 / 1.33
    /// Floor so windows cannot collapse into unusable slivers.
    private let minWidth: CGFloat = 200
    private let minHeight: CGFloat = 100

    func perform(at point: CGPoint, service: AccessibilityServiceProtocol) {
        guard let element = service.getElement(at: point),
              let window = service.getWindow(for: element),
              let currentFrame = service.getFrame(for: window) else { return }

        guard let screen = ScreenGeometry.screenContaining(axPoint: point) else { return }
        let axScreenBounds = ScreenGeometry.axBounds(for: screen)

        let targetWidth = max((currentFrame.width * scaleFactor).rounded(), minWidth)
        let targetHeight = max((currentFrame.height * scaleFactor).rounded(), minHeight)

        // Clamp dimensions to screen bounds
        let newWidth = min(targetWidth, axScreenBounds.width)
        let newHeight = min(targetHeight, axScreenBounds.height)

        // Shrink symmetrically from center
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

        _ = service.setFrame(CGRect(x: newX, y: newY, width: newWidth, height: newHeight), for: window)
    }
}

struct ReasonableSizeAction: ShortcutAction {
    func perform(at point: CGPoint, service: AccessibilityServiceProtocol) {
        guard let element = service.getElement(at: point),
              let window = service.getWindow(for: element) else { return }
        guard let screen = ScreenGeometry.screenContaining(axPoint: point) else { return }
        let axBounds = ScreenGeometry.axBounds(for: screen)
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
        guard let screen = ScreenGeometry.screenContaining(axPoint: point) else { return }
        let axBounds = ScreenGeometry.axBounds(for: screen)
        let w = (axBounds.width * 0.904).rounded()
        let h = (axBounds.height * 0.872).rounded()
        let x = (axBounds.origin.x + (axBounds.width - w) / 2).rounded()
        let y = (axBounds.origin.y + (axBounds.height - h) / 2).rounded()
        _ = service.setFrame(CGRect(x: x, y: y, width: w, height: h), for: window)
    }
}

// MARK: - Native Snap Actions

enum SnapPosition {
    case leftHalf
    case rightHalf
    case leftThird
    case rightThird

    func frame(for visibleBounds: CGRect) -> CGRect {
        switch self {
        case .leftHalf:
            let w = (visibleBounds.width / 2.0).rounded()
            return CGRect(x: visibleBounds.origin.x, y: visibleBounds.origin.y, width: w, height: visibleBounds.height)
        case .rightHalf:
            let leftW = (visibleBounds.width / 2.0).rounded()
            let w = visibleBounds.width - leftW
            let x = visibleBounds.origin.x + leftW
            return CGRect(x: x, y: visibleBounds.origin.y, width: w, height: visibleBounds.height)
        case .leftThird:
            let w = (visibleBounds.width / 3.0).rounded()
            return CGRect(x: visibleBounds.origin.x, y: visibleBounds.origin.y, width: w, height: visibleBounds.height)
        case .rightThird:
            let w = (visibleBounds.width / 3.0).rounded()
            let x = visibleBounds.origin.x + visibleBounds.width - w
            return CGRect(x: x, y: visibleBounds.origin.y, width: w, height: visibleBounds.height)
        }
    }
}

private func performSnapAction(_ position: SnapPosition, at point: CGPoint, service: AccessibilityServiceProtocol) {
    guard let element = service.getElement(at: point),
          let window = service.getWindow(for: element) else { return }
    guard let screen = ScreenGeometry.screenContaining(axPoint: point) else { return }
    let visibleBounds = ScreenGeometry.axVisibleBounds(for: screen)
    _ = service.setFrame(position.frame(for: visibleBounds), for: window)
}

struct LeftHalfSnapAction: ShortcutAction {
    func perform(at point: CGPoint, service: AccessibilityServiceProtocol) {
        performSnapAction(.leftHalf, at: point, service: service)
    }
}

struct RightHalfSnapAction: ShortcutAction {
    func perform(at point: CGPoint, service: AccessibilityServiceProtocol) {
        performSnapAction(.rightHalf, at: point, service: service)
    }
}

struct LeftThirdSnapAction: ShortcutAction {
    func perform(at point: CGPoint, service: AccessibilityServiceProtocol) {
        performSnapAction(.leftThird, at: point, service: service)
    }
}

struct RightThirdSnapAction: ShortcutAction {
    func perform(at point: CGPoint, service: AccessibilityServiceProtocol) {
        performSnapAction(.rightThird, at: point, service: service)
    }
}
