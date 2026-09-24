import ApplicationServices
import Foundation

@MainActor
final class MockSpaceManagementService: SpaceManagementServiceProtocol {
    var mockCurrentSpaceID: Int? = 1
    var mockWindowSpaces: [CGWindowID: [Int]] = [:]

    var isWindowOnCurrentSpaceCalledWith: [CGWindowID] = []

    func currentSpaceID() -> Int? {
        mockCurrentSpaceID
    }

    func spaceIDs(for windowID: CGWindowID) -> [Int] {
        mockWindowSpaces[windowID] ?? []
    }

    func isWindowOnCurrentSpace(windowID: CGWindowID) -> Bool {
        isWindowOnCurrentSpaceCalledWith.append(windowID)
        guard let current = mockCurrentSpaceID else { return true }
        let spaces = spaceIDs(for: windowID)
        if spaces.isEmpty { return true }
        return spaces.contains(current)
    }
}
