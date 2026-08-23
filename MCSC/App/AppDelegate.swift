import ApplicationServices
import Cocoa
import os

/// The application delegate for the MCSC menu bar utility.
///
/// Responsibilities:
/// - Configures the app as an accessory (menu bar only, no Dock icon).
/// - Builds the menu bar status item and its toggle menu exactly once.
/// - Assembles the `ShortcutViewModel` with its service dependencies.
/// - Requests Accessibility permission (with a polling fallback) and boots
///   the ViewModel once trust is granted.
/// - Observes system sleep/wake so the event tap can be stopped and
///   restarted cleanly around sleep cycles.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var viewModel: ShortcutViewModel?
    private var statusItem: NSStatusItem?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var settingsController: SettingsWindowController?

    /// Repeating poll used while Accessibility permission has not yet been
    /// granted. Invalidated the moment trust is detected or the app quits.
    private var accessibilityPollTimer: Timer?

    func applicationDidFinishLaunching(_: Notification) {
        // Hide dock icon (menu bar utility, no Dock presence).
        NSApp.setActivationPolicy(.accessory)

        let eventTap = EventTapService()
        let accessibility = AccessibilityService()
        let missionControl = MissionControlService()
        let launchAtLogin = LaunchAtLoginService()

        viewModel = ShortcutViewModel(eventTapService: eventTap,
                                      accessibilityService: accessibility,
                                      missionControlService: missionControl,
                                      launchAtLoginService: launchAtLogin)

        // Build the status bar menu after the ViewModel exists so every toggle
        // reflects real configuration. This runs exactly once — calling
        // `statusItem(withLength:)` again would leak a second menu bar icon.
        setupStatusBar()

        // Request Accessibility permission (prompts via System Settings when
        // needed). The ViewModel only starts listening once trusted.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)

        if isTrusted {
            viewModel?.start()
        } else {
            AppLogger.app.info("Waiting for accessibility permissions...")
            // Poll for trust so the app boots the moment the user grants
            // permission in System Settings, without requiring a relaunch.
            accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                if AXIsProcessTrusted() {
                    self?.viewModel?.start()
                    self?.accessibilityPollTimer = nil
                    timer.invalidate()
                }
            }
        }

        // Observe sleep/wake to recreate event tap
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            AppLogger.app.info("System sleeping - stopping event tap")
            self?.viewModel?.stop()
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            AppLogger.app.info("System woke up - restarting event tap")
            self?.viewModel?.start()
        }
    }

    /// Creates the minimal menu bar status item.
    /// All feature toggles now live in Settings (General/Shortcuts/Gestures);
    /// the menu only exposes Settings and Quit to stay minimal (AGENTS.md: lightweight).
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "command.circle", accessibilityDescription: "MCSC")
        }

        let menu = NSMenu()

        let aboutItem = NSMenuItem(
            title: "About MCSC",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        menu.addItem(aboutItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit MCSC", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc private func showSettings() {
        guard let viewModel else { return }
        if settingsController == nil {
            let controller = SettingsWindowController(viewModel: viewModel)
            controller.onWindowWillClose = { [weak self] in
                self?.settingsController = nil
            }
            settingsController = controller
        }
        settingsController?.show()
    }

    func applicationWillTerminate(_: Notification) {
        viewModel?.stop()
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = nil

        if let observer = sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
