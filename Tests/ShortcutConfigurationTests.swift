import Foundation
import XCTest

/// Covers the two "outside Mission Control" toggles (Dock + Title Bar):
/// defaults are off, Restore Defaults keeps them off, and mutations persist.
final class ShortcutConfigurationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        clearStoredToggles()
    }

    override func tearDown() {
        // Other suites construct `ShortcutConfiguration()` expecting defaults;
        // never leak mutated toggle state into or out of these tests.
        clearStoredToggles()
        super.tearDown()
    }

    private func clearStoredToggles() {
        for entry in ShortcutConfiguration.toggleDefaults {
            UserDefaults.standard.removeObject(forKey: entry.key)
        }
        UserDefaults.standard.removeObject(forKey: ShortcutConfiguration.bindingsStorageKey)
    }

    func testOutsideMCTogglesDefaultToOff() {
        let config = ShortcutConfiguration()
        XCTAssertFalse(config.isDockActionsOutsideMCEnabled)
        XCTAssertFalse(config.isTitleBarActionsOutsideMCEnabled)
    }

    func testRestoreDefaultsKeepsOutsideMCTogglesOff() {
        var config = ShortcutConfiguration()
        config.isDockActionsOutsideMCEnabled = true
        config.isTitleBarActionsOutsideMCEnabled = true

        config.restoreDefaults()

        XCTAssertFalse(config.isDockActionsOutsideMCEnabled)
        XCTAssertFalse(config.isTitleBarActionsOutsideMCEnabled)
    }

    func testTitleBarTogglePersistsAndReloadsFromUserDefaults() {
        let titleBarKey = "mcsc.titleBarActionsOutsideMC.enabled"
        var config = ShortcutConfiguration()
        config.isTitleBarActionsOutsideMCEnabled = true

        XCTAssertTrue(UserDefaults.standard.bool(forKey: titleBarKey))
        XCTAssertTrue(ShortcutConfiguration().isTitleBarActionsOutsideMCEnabled)

        config.isTitleBarActionsOutsideMCEnabled = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: titleBarKey))
    }

    func testQuitAppIfNoWindowsTogglePersistsAndReloadsFromUserDefaults() {
        let quitKey = "mcsc.quitAppIfNoWindows.enabled"
        var config = ShortcutConfiguration()
        XCTAssertFalse(config.isQuitAppIfNoWindowsEnabled)

        config.isQuitAppIfNoWindowsEnabled = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: quitKey))
        XCTAssertTrue(ShortcutConfiguration().isQuitAppIfNoWindowsEnabled)

        config.isQuitAppIfNoWindowsEnabled = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: quitKey))
    }

    /// Guards the single-source-of-truth contract: every stored-property
    /// literal must match its `toggleDefaults` entry, so `restoreDefaults()`
    /// can never drift from what a fresh instance reports.
    func testFreshInstanceMatchesToggleDefaultsTable() {
        let config = ShortcutConfiguration()
        for entry in ShortcutConfiguration.toggleDefaults {
            XCTAssertEqual(config[keyPath: entry.keyPath], entry.defaultValue,
                           "Stored-property default drifted from toggleDefaults for key \(entry.key)")
        }
    }

    func testRestoreDefaultsMatchesToggleDefaultsTableForEveryToggle() {
        var config = ShortcutConfiguration()
        for entry in ShortcutConfiguration.toggleDefaults {
            config[keyPath: entry.keyPath] = !entry.defaultValue
        }

        config.restoreDefaults()

        for entry in ShortcutConfiguration.toggleDefaults {
            XCTAssertEqual(config[keyPath: entry.keyPath], entry.defaultValue,
                           "Restore Defaults did not reset key \(entry.key)")
        }
    }

    // MARK: - Rebindable shortcut bindings

    /// Fresh installs pre-assign exactly the actions that shipped enabled;
    /// everything else starts unassigned (disabled).
    func testDefaultBindingsMatchShippedDefaults() {
        let config = ShortcutConfiguration()
        XCTAssertNotNil(config.binding(for: .close))
        XCTAssertNotNil(config.binding(for: .closeTab))
        XCTAssertNotNil(config.binding(for: .quit))
        XCTAssertNotNil(config.binding(for: .minimize))
        XCTAssertNotNil(config.binding(for: .hide))
        XCTAssertNil(config.binding(for: .fullscreen))
        XCTAssertNil(config.binding(for: .newTab))
        XCTAssertNil(config.binding(for: .newWindow))
        XCTAssertNil(config.binding(for: .reopenTab))
        XCTAssertNil(config.binding(for: .fillScreen))
        XCTAssertNil(config.binding(for: .moveNextDesktop))
        XCTAssertNil(config.binding(for: .unminimizeAll))
        XCTAssertEqual(config.binding(for: .close)?.displayString, "⌘ W")
        XCTAssertEqual(ShortcutBinding(keyCode: 2, includesShift: true).displayString,
                       "⇧ ⌘ D", "Shift bindings render ⇧ before ⌘ with per-glyph gaps")
    }

    func testBindingPersistsAndReloadsFromUserDefaults() {
        var writer = ShortcutConfiguration()
        writer.setBinding(ShortcutBinding(keyCode: 7), for: .makeLarger) // ⌘X

        var reloaded = ShortcutConfiguration()
        XCTAssertEqual(reloaded.binding(for: .makeLarger)?.keyCode, 7)

        reloaded.setBinding(nil, for: .makeLarger)
        XCTAssertNil(ShortcutConfiguration().binding(for: .makeLarger),
                     "Clearing a binding must persist as disabled")
    }

    func testMatchedActionsRespectShiftAndPrecedence() {
        var config = ShortcutConfiguration()
        config.setBinding(ShortcutBinding(keyCode: 13, includesShift: true), for: .fillScreen)

        XCTAssertTrue(config.matchedActions(keyCode: 13, includesShift: true).contains(.fillScreen))
        // ⌘W without shift must not match the ⌘⇧W fill-screen binding…
        XCTAssertFalse(config.matchedActions(keyCode: 13, includesShift: false).contains(.fillScreen))
        // …but it still matches both shipped ⌘W actions in precedence order.
        let matchedW = config.matchedActions(keyCode: 13, includesShift: false)
        XCTAssertEqual(matchedW.first, .close)
        XCTAssertTrue(matchedW.contains(.closeTab))

        XCTAssertTrue(config.boundKeyCodes.contains(13))
        XCTAssertFalse(config.boundKeyCodes.contains(2),
                       "The replaced default key must no longer be admitted")
    }

    func testCloseAndCloseTabAreLinked() {
        var config = ShortcutConfiguration()
        XCTAssertEqual(config.binding(for: .close)?.keyCode, 13)
        XCTAssertEqual(config.binding(for: .closeTab)?.keyCode, 13)

        // Changing close updates closeTab
        config.setBinding(ShortcutBinding(keyCode: 7), for: .close)
        XCTAssertEqual(config.binding(for: .close)?.keyCode, 7)
        XCTAssertEqual(config.binding(for: .closeTab)?.keyCode, 7)

        // Changing closeTab updates close
        config.setBinding(ShortcutBinding(keyCode: 6), for: .closeTab)
        XCTAssertEqual(config.binding(for: .close)?.keyCode, 6)
        XCTAssertEqual(config.binding(for: .closeTab)?.keyCode, 6)

        // Clearing one clears both
        config.setBinding(nil, for: .close)
        XCTAssertNil(config.binding(for: .close))
        XCTAssertNil(config.binding(for: .closeTab))
    }

    func testAssigningExistingBindingDisplacesPreviousAction() {
        var config = ShortcutConfiguration()
        // Quit starts at ⌘Q (keyCode 12)
        XCTAssertEqual(config.binding(for: .quit)?.keyCode, 12)
        XCTAssertNil(config.binding(for: .fullscreen))

        // Assigning ⌘Q to Full Screen unassigns Quit
        config.setBinding(ShortcutBinding(keyCode: 12), for: .fullscreen)
        XCTAssertEqual(config.binding(for: .fullscreen)?.keyCode, 12)
        XCTAssertNil(config.binding(for: .quit), "Quit must be displaced when ⌘Q is given to Full Screen")
    }

    func testLegacyToggleKeysMigrateIntoBindingStore() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "mcsc.shortcuts.closing.enabled")
        defaults.set(false, forKey: "mcsc.shortcuts.fillScreen.enabled")

        let migrated = ShortcutConfiguration()

        XCTAssertNotNil(migrated.binding(for: .close), "Legacy enabled flag must become an assigned binding")
        XCTAssertNil(migrated.binding(for: .fillScreen), "Legacy disabled flag must clear the binding")
        XCTAssertNil(defaults.object(forKey: "mcsc.shortcuts.closing.enabled"),
                     "Legacy keys are dropped after migration")
    }
}
