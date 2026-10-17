import ApplicationServices
import Cocoa

/// Authoritative service for querying macOS Spaces and Desktop window assignments.
///
/// ## Why SkyLight / CoreGraphics Services?
/// Standard AppKit and Accessibility APIs cannot reliably associate a `CGWindowID` with its
/// virtual Desktop space (`ManagedSpaceID`).
///
/// Under macOS 27 WindowManager, Mission Control preview tiles and window records span all spaces
/// simultaneously in the window server hierarchy. To prevent "ghosting" (e.g. showing a close button
/// for a Desktop 1 window while looking at Desktop 2), `SpaceManagementService` directly queries
/// SkyLight private CGS routines:
/// - `CGSMainConnectionID`: Main window server connection identifier.
/// - `CGSCopyManagedDisplaySpaces`: Maps display UUIDs to current `ManagedSpaceID`s and space sets.
/// - `CGSCopySpacesForWindows`: Resolves space assignments for window IDs with mask `0x7` (`allSpacesMask`).
///
/// ## Windows with Empty Space IDs
/// A window returning an empty space list (`[]`) from `CGSCopySpacesForWindows` indicates it is either
/// unassigned or visible across all spaces (such as floating tool windows, Finder panels, or menus).
/// These windows are considered present on the current space.
@MainActor
protocol SpaceManagementServiceProtocol: AnyObject {
    /// Returns the ManagedSpaceID of the active space on the main display, or nil if indeterminate.
    func currentSpaceID() -> Int?

    /// Returns the list of space IDs assigned to the given window.
    func spaceIDs(for windowID: CGWindowID) -> [Int]

    /// Returns true if the window is present on the currently active desktop space.
    func isWindowOnCurrentSpace(windowID: CGWindowID) -> Bool
}

@MainActor
final class SpaceManagementService: SpaceManagementServiceProtocol {
    private typealias CGSConnectionID = Int32

    @_silgen_name("CGSMainConnectionID")
    private static func CGSMainConnectionID() -> CGSConnectionID

    @_silgen_name("CGSCopyManagedDisplaySpaces")
    private static func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray?

    @_silgen_name("CGSCopySpacesForWindows")
    private static func CGSCopySpacesForWindows(_ cid: CGSConnectionID, _ mask: Int32, _ windowIDs: CFArray) -> CFArray?

    func currentSpaceID() -> Int? {
        let cid = Self.CGSMainConnectionID()
        guard let displays = Self.CGSCopyManagedDisplaySpaces(cid) as? [[String: Any]],
              let mainDisplay = displays.first,
              let currentSpace = mainDisplay["Current Space"] as? [String: Any],
              let spaceID = currentSpace["ManagedSpaceID"] as? Int else {
            return nil
        }
        return spaceID
    }

    /// Returns the set of ManagedSpaceIDs for active spaces across all connected displays.
    func activeSpaceIDs() -> Set<Int> {
        let cid = Self.CGSMainConnectionID()
        guard let displays = Self.CGSCopyManagedDisplaySpaces(cid) as? [[String: Any]] else {
            return []
        }
        var activeSpaces = Set<Int>()
        for display in displays {
            if let currentSpace = display["Current Space"] as? [String: Any],
               let spaceID = currentSpace["ManagedSpaceID"] as? Int {
                activeSpaces.insert(spaceID)
            }
        }
        return activeSpaces
    }

    func spaceIDs(for windowID: CGWindowID) -> [Int] {
        let cid = Self.CGSMainConnectionID()
        guard let spaces = Self.CGSCopySpacesForWindows(cid, 0x7, [NSNumber(value: windowID)] as CFArray) as? [Int]
        else {
            return []
        }
        return spaces
    }

    func isWindowOnCurrentSpace(windowID: CGWindowID) -> Bool {
        let activeSpaces = activeSpaceIDs()
        if activeSpaces.isEmpty {
            // When space query is unavailable (e.g. headless or test environments without window server),
            // fall back to currentSpaceID if available, else assume the window belongs to current space.
            guard let current = currentSpaceID() else { return true }
            let spaces = spaceIDs(for: windowID)
            if spaces.isEmpty {
                return true
            }
            return spaces.contains(current)
        }
        let spaces = spaceIDs(for: windowID)
        // If window is assigned to all spaces or has no specific space assignment, allow it
        if spaces.isEmpty {
            return true
        }
        return spaces.contains(where: { activeSpaces.contains($0) })
    }
}
