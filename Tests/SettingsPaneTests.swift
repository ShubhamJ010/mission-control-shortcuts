import Cocoa
import XCTest

// MARK: - Mocks

/// Inert event-tap double: records start/stop but never installs a CGEvent tap.
final class MockSettingsEventTapService: EventTapServiceProtocol {
    typealias ShortcutDetectedCallback = (Int64, CGEventFlags, CGPoint) -> Bool
    var onShortcutDetected: ShortcutDetectedCallback?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    func start() {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }
}

/// Inert Mission Control double.
final class MockSettingsMissionControlService: MissionControlServiceProtocol {
    var isMissionControlActive = false
    var isSimulating = false
    var onActivated: (() -> Void)?
    var onDeactivated: (() -> Void)?
    func checkMissionControlActive() -> Bool {
        isMissionControlActive
    }

    func executeFixSequence() {}
    func start() {}
    func stop() {}
    func markActive(_: Bool) {}
}

// MARK: - Regression tests for the settings panes

//
// Guard against the class of bug introduced in commit e5375d2, where the
// lint-refactor file split left `GestureSettingsPane.makeGestureRow` as an
// empty stub: the pane compiled, all tests passed, but the Gestures settings
// UI rendered without any gesture rows. These tests load every pane for real
// and assert the resulting control hierarchy, so a dropped builder can never
// ship silently again.

@MainActor
final class SettingsPaneTests: XCTestCase {
    override func setUp() {
        super.setUp()
        clearPersistedSettings()
    }

    override func tearDown() {
        // Panes persist every toggle/mapping to UserDefaults on mutation;
        // never leak mutated state into or out of these tests.
        clearPersistedSettings()
        super.tearDown()
    }

    private func clearPersistedSettings() {
        for entry in ShortcutConfiguration.toggleDefaults {
            UserDefaults.standard.removeObject(forKey: entry.key)
        }
        UserDefaults.standard.removeObject(forKey: "mcsc.gestures.actions")
    }

    // MARK: Fixtures

    private func makeViewModel() -> ShortcutViewModel {
        ShortcutViewModel(
            eventTapService: MockSettingsEventTapService(),
            accessibilityService: MockAccessibilityService(),
            missionControlService: MockSettingsMissionControlService(),
            launchAtLoginService: LaunchAtLoginService()
        )
    }

    private func makeGesturePane() -> GestureSettingsPane {
        GestureSettingsPane(viewModel: makeViewModel(),
                            tabName: "Gestures",
                            tabImage: nil,
                            tabIdentifier: "gestures")
    }

    /// The pane's private `gestureRows`, read via reflection so the test
    /// observes exactly what production code built — no test-only hooks that
    /// could themselves rot.
    private struct RowSnapshot {
        let kind: GestureKind
        let actionPopup: NSPopUpButton
        let cmdActionPopup: NSPopUpButton
        let enableSwitch: NSSwitch
    }

    private func gestureRows(of pane: GestureSettingsPane) -> [RowSnapshot] {
        guard let rows = Mirror(reflecting: pane).descendant("gestureRows") as? [Any] else {
            return []
        }
        return rows.map { row in
            let mirror = Mirror(reflecting: row)
            func child(_ name: String) -> Any {
                guard let value = mirror.children.first(where: { $0.label == name })?.value else {
                    fatalError("GestureRow is missing expected property '\(name)' — update the test")
                }
                return value
            }
            return RowSnapshot(
                kind: child("kind") as! GestureKind,
                actionPopup: child("actionPopup") as! NSPopUpButton,
                cmdActionPopup: child("cmdActionPopup") as! NSPopUpButton,
                enableSwitch: child("enableSwitch") as! NSSwitch
            )
        }
    }

    private func allDescendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + allDescendants(of: $0) }
    }

    /// Fires a control's target/action synchronously (no NSApp dependency).
    private func sendAction(of control: NSControl) {
        guard let action = control.action, let target = control.target else {
            XCTFail("\(control) has no target/action wired — the pane dropped its control wiring")
            return
        }
        _ = target.perform(action, with: control)
    }

    // MARK: The regression: rows must actually be built

    func testLoadViewBuildsOneRowPerGestureKind() {
        let pane = makeGesturePane()
        pane.loadView()

        let rows = gestureRows(of: pane)
        XCTAssertEqual(rows.count, GestureKind.allCases.count,
                       "Gestures pane must build exactly one row per gesture kind; "
                           + "count 0 means a row builder was gutted or never called")
    }

    func testRowsCoverEveryGestureKindExactlyOnceInOrder() {
        let pane = makeGesturePane()
        pane.loadView()

        let kinds = gestureRows(of: pane).map(\.kind)
        XCTAssertEqual(kinds, GestureKind.allCases,
                       "Row order must match GestureKind.allCases with no duplicates or omissions")
    }

    func testPaneHierarchyContainsExpectedControls() {
        let pane = makeGesturePane()
        pane.loadView()

        let descendants = allDescendants(of: pane.view)
        let popups = descendants.compactMap { $0 as? NSPopUpButton }
        let switches = descendants.compactMap { $0 as? NSSwitch }
        let buttons = descendants.compactMap { $0 as? NSButton }

        // 7 rows × (plain popup + ⌘ popup) and one enable switch per row.
        XCTAssertEqual(popups.count, 14,
                       "Expected 7 plain + 7 ⌘ action pop-ups in the view tree")
        XCTAssertEqual(switches.count, 7,
                       "Expected one enable switch per gesture row in the view tree")
        XCTAssertGreaterThanOrEqual(buttons.count, 2,
                                    "Expected the master checkbox and Restore Defaults button")
        XCTAssertTrue(buttons.contains { $0.title == "Restore Defaults" },
                      "Restore Defaults button missing from the pane")
    }

    // MARK: Row wiring

    func testRowControlsAreTaggedByRowIndex() {
        let pane = makeGesturePane()
        pane.loadView()

        for (index, row) in gestureRows(of: pane).enumerated() {
            XCTAssertEqual(row.actionPopup.tag, index, "plain popup tag for row \(index)")
            XCTAssertEqual(row.cmdActionPopup.tag, index, "⌘ popup tag for row \(index)")
            XCTAssertEqual(row.enableSwitch.tag, index, "switch tag for row \(index)")
        }
    }

    func testRowPopupsOfferExactlyTheNaturalActions() {
        let pane = makeGesturePane()
        pane.loadView()

        for row in gestureRows(of: pane) {
            let expected = row.kind.naturalActions.map(\.rawValue)
            for (popup, label) in [(row.actionPopup, "plain"), (row.cmdActionPopup, "⌘")] {
                let offered = popup.itemArray.compactMap { $0.representedObject as? String }
                XCTAssertEqual(offered, expected,
                               "\(row.kind.rawValue) \(label) pop-up must offer exactly the natural actions")
            }
        }
    }

    func testRowActionsAreWiredToPaneHandlers() {
        let pane = makeGesturePane()
        pane.loadView()

        for row in gestureRows(of: pane) {
            XCTAssertEqual(row.actionPopup.target as? GestureSettingsPane, pane,
                           "plain popup target must be the pane")
            XCTAssertNotEqual(row.actionPopup.action, nil,
                              "plain popup action must be wired")
            XCTAssertEqual(row.cmdActionPopup.target as? GestureSettingsPane, pane,
                           "⌘ popup target must be the pane")
            XCTAssertEqual(row.enableSwitch.target as? GestureSettingsPane, pane,
                           "enable switch target must be the pane")
        }
    }

    // MARK: Refresh behaviour

    func testRefreshSelectsViewModelActionsInPopups() throws {
        let pane = makeGesturePane()
        pane.loadView()
        pane.viewModel.setGestureAction(.quitApp, for: .pinchIn, isCmd: false)
        pane.viewModel.setGestureAction(.newTab, for: .swipeRight, isCmd: true)

        pane.refresh()

        let rows = gestureRows(of: pane)
        let pinchIn = try XCTUnwrap(rows.first { $0.kind == .pinchIn })
        XCTAssertEqual(pinchIn.actionPopup.selectedItem?.representedObject as? String,
                       GestureAction.quitApp.rawValue)
        let swipeRight = try XCTUnwrap(rows.first { $0.kind == .swipeRight })
        XCTAssertEqual(swipeRight.cmdActionPopup.selectedItem?.representedObject as? String,
                       GestureAction.newTab.rawValue)
    }

    func testRefreshResetsStaleBindingToFactoryDefault() {
        let pane = makeGesturePane()
        pane.loadView()

        // .closeWindow is not a natural action for .pinchOut — a stale
        // persisted binding that refresh() must reset to the default.
        pane.viewModel.setGestureAction(.closeWindow, for: .pinchOut, isCmd: false)
        pane.refresh()

        XCTAssertEqual(pane.viewModel.gestureAction(for: .pinchOut, isCmd: false),
                       GestureDefaults.action(for: .pinchOut, isCmd: false),
                       "Stale bindings must be reset to the factory default on refresh")
    }

    func testMasterToggleGatesRowControls() {
        let pane = makeGesturePane()
        pane.loadView()

        pane.viewModel.isGesturesEnabled = false
        pane.refresh()
        for row in gestureRows(of: pane) {
            XCTAssertFalse(row.actionPopup.isEnabled,
                           "\(row.kind.rawValue) popup must be disabled when gestures are off")
            XCTAssertFalse(row.enableSwitch.isEnabled,
                           "\(row.kind.rawValue) switch must be disabled when gestures are off")
        }

        pane.viewModel.isGesturesEnabled = true
        pane.refresh()
        for row in gestureRows(of: pane) {
            XCTAssertTrue(row.actionPopup.isEnabled,
                          "\(row.kind.rawValue) popup must be enabled when gestures are on")
            XCTAssertTrue(row.enableSwitch.isEnabled,
                          "\(row.kind.rawValue) switch must be enabled when gestures are on")
        }
    }

    // MARK: Target/action wiring end-to-end

    func testMasterCheckboxActionTogglesViewModelAndSyncsRows() {
        let pane = makeGesturePane()
        pane.loadView()

        guard let master = Mirror(reflecting: pane).descendant("gesturesToggleCheckbox") as? NSButton else {
            return XCTFail("Master checkbox outlet missing")
        }
        XCTAssertTrue(pane.viewModel.isGesturesEnabled, "Gestures default to enabled")

        sendAction(of: master)
        XCTAssertFalse(pane.viewModel.isGesturesEnabled, "Master checkbox must toggle the view model")
        XCTAssertEqual(master.state, .off, "Checkbox state must track the view model")
        XCTAssertTrue(gestureRows(of: pane).allSatisfy { !$0.actionPopup.isEnabled },
                      "Rows must disable immediately after toggling the master off")

        sendAction(of: master)
        XCTAssertTrue(pane.viewModel.isGesturesEnabled)
        XCTAssertEqual(master.state, .on)
    }

    func testGestureSwitchActionUpdatesViewModel() {
        let pane = makeGesturePane()
        pane.loadView()

        let switchControl = gestureRows(of: pane).first { $0.kind == .pinchIn }?.enableSwitch
        guard let switchControl else { return XCTFail("Pinch-in row not built") }

        XCTAssertTrue(pane.viewModel.isPinchInEnabled)
        switchControl.state = .off
        sendAction(of: switchControl)
        XCTAssertFalse(pane.viewModel.isPinchInEnabled,
                       "Row switch must update the per-gesture enablement via its tag")
    }

    func testGesturePopupActionUpdatesViewModel() {
        let pane = makeGesturePane()
        pane.loadView()

        let popup = gestureRows(of: pane).first { $0.kind == .pinchIn }?.actionPopup
        guard let popup else { return XCTFail("Pinch-in row not built") }

        let target = GestureAction.quitApp
        if let idx = popup.itemArray.firstIndex(where: { ($0.representedObject as? String) == target.rawValue }) {
            popup.selectItem(at: idx)
        }
        sendAction(of: popup)

        XCTAssertEqual(pane.viewModel.gestureAction(for: .pinchIn, isCmd: false), target,
                       "Popup selection must persist through actionChanged(_:)")
    }

    func testRestoreDefaultsResetsTogglesAndMappings() {
        let pane = makeGesturePane()
        pane.loadView()
        pane.viewModel.isGesturesEnabled = false
        pane.viewModel.isPinchInEnabled = false
        pane.viewModel.setGestureAction(.quitApp, for: .pinchIn, isCmd: false)

        guard let restoreButton = allDescendants(of: pane.view).compactMap({ $0 as? NSButton })
            .first(where: { $0.title == "Restore Defaults" }) else {
            return XCTFail("Restore Defaults button not built")
        }
        sendAction(of: restoreButton)

        XCTAssertTrue(pane.viewModel.isGesturesEnabled)
        XCTAssertTrue(pane.viewModel.isPinchInEnabled)
        XCTAssertEqual(pane.viewModel.gestureAction(for: .pinchIn, isCmd: false),
                       GestureDefaults.action(for: .pinchIn, isCmd: false))
        XCTAssertEqual(gestureRows(of: pane).first { $0.kind == .pinchIn }?.enableSwitch.state, .on,
                       "Rows must re-sync after Restore Defaults")
    }

    // MARK: Same-class-of-bug smoke tests for the sibling panes

    func testGeneralPaneBuildsARealControlHierarchy() {
        let pane = GeneralSettingsPane(viewModel: makeViewModel(),
                                       tabName: "General",
                                       tabImage: nil,
                                       tabIdentifier: "general")
        pane.loadView()

        let controls = allDescendants(of: pane.view)
            .filter { $0 is NSButton || $0 is NSPopUpButton || $0 is NSSwitch }
        XCTAssertGreaterThanOrEqual(controls.count, 8,
                                    "General pane lost its toggles — a section builder was likely gutted")
    }

    func testShortcutPaneBuildsARealControlHierarchy() {
        let pane = ShortcutSettingsPane(viewModel: makeViewModel(),
                                        tabName: "Shortcuts",
                                        tabImage: nil,
                                        tabIdentifier: "shortcuts")
        pane.loadView()

        let descendants = allDescendants(of: pane.view)
        let controls = descendants
            .filter { $0 is NSButton || $0 is NSPopUpButton || $0 is NSSwitch }
        XCTAssertGreaterThanOrEqual(controls.count, 10,
                                    "Shortcuts pane lost its toggles — a section builder was likely gutted")
        XCTAssertTrue(descendants.compactMap { $0 as? NSButton }.contains { $0.title == "Restore Defaults" })
    }

    func testShortcutPaneMasterGatesCloseTabWithCascadeOff() throws {
        let pane = ShortcutSettingsPane(viewModel: makeViewModel(),
                                        tabName: "Shortcuts",
                                        tabImage: nil,
                                        tabIdentifier: "shortcuts")
        pane.loadView()

        let mirror = Mirror(reflecting: pane)
        let master = try XCTUnwrap(mirror.descendant("closingMasterCheckbox") as? NSButton,
                                   "⌘+W master checkbox outlet missing")
        let closeTab = try XCTUnwrap(mirror.descendant("cmdWCheckbox") as? NSButton,
                                     "Close Tab checkbox outlet missing")

        // Defaults: master on, Close Tab available.
        XCTAssertTrue(pane.viewModel.isClosingEnabled)
        XCTAssertTrue(pane.viewModel.isCmdWEnabled)
        XCTAssertEqual(master.state, .on)
        XCTAssertEqual(closeTab.state, .on)
        XCTAssertTrue(closeTab.isEnabled)

        // Master off cascades: Close Tab can't stay on without it.
        sendAction(of: master)

        XCTAssertFalse(pane.viewModel.isClosingEnabled)
        XCTAssertFalse(pane.viewModel.isCmdWEnabled)
        XCTAssertEqual(master.state, .off)
        XCTAssertEqual(closeTab.state, .off)
        XCTAssertFalse(closeTab.isEnabled)
    }
}
