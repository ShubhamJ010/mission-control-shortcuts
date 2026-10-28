# Quitting apps that stay running in background

macOS 27 keeps an app in the Dock after the last window closes. The Dock labels it "Running in Background". Closing it in MCSC now clears that state on the first attempt or the second.

## Behaviour

The quit action has two strikes.

1. First quit on an app that still has windows. MCSC records the attempt against the bundle identifier, then calls `forceTerminate()`.
2. Second quit within 8 seconds, or any quit on an app that already has no windows. MCSC stops the Dock entry and kills the leftover processes instead of calling `forceTerminate()` again.

An app with no windows takes strike two on the first quit. It is already lingering.

## Entry points

| Where you quit | Path |
| --- | --- |
| Dock icon, process alive | `TargetResolution.dock(app)` → `ForceQuitAppAction.perform(app:dockItem:service:)` |
| Dock icon, no process left | `TargetResolution.lingeringDockItem(element)` → `ForceQuitAppAction.perform(dockItem:)` |
| Pointer over a window | `TargetResolution.window(...)` → `ForceQuitAppAction.perform(app:service:)` |
| Keyboard shortcut, pointer on Dock | same as the Dock rows above |
| Keyboard shortcut, pointer on window | `TargetResolution.window(...)` → `ForceQuitAppAction.perform(app:service:)` |
| Mission Control preview | unchanged, `MissionControlWindowActions.performForceQuit(on:)` |

Every quit path except the Mission Control preview now reaches `ForceQuitAppAction`. A path that skips it loses the two strikes, because that is where the decision lives.

## Flow

```
gesture or shortcut
  → resolveTarget(at:)
       process found        → .dock(app)
       icon only, no proc   → .lingeringDockItem(icon)     [macOS 27 case]
       pointer on window    → .window(element)
  → ForceQuitAppAction.perform
       recent quit or no windows → BackgroundAppService.terminateBackgroundServices
                                    1. snapshot descendant pids and bundle pids
                                    2. press Dock "Stop Running in Background"
                                    3. forceTerminate()
                                    4. SIGKILL the remaining pids
       otherwise (first strike)   → recordQuitAttempt + forceTerminate()
```

Step 1 runs before step 3 on purpose. The main process reparents its children to launchd when it exits, and a pid snapshot taken afterwards reaches nobody.

Step 2 runs before step 3 for the same reason. The Dock icon disappears with the process, so the menu item has to be clicked while the icon exists.

`BackgroundAppService.terminateLingeringDockItem(_:)` covers the case where no `NSRunningApplication` exists. It reads the bundle URL from the Dock icon's `AXURL`, presses the Dock menu item, then kills every process whose executable path starts with that bundle path.

## When the Dock menu item exists

The Dock offers "Stop Running in Background" only once the app has no live main process. While the process is alive the menu reads `Options | Show All Windows | Hide | Hide Others | Quit | Force Quit`. MCSC logs the exact list it saw, so a missing item shows up as one line rather than a silent failure. Strike two falls back to the bundle-wide process kill in that situation.

## Reading the logs

```bash
log show --predicate 'subsystem == "sj010.MCSC"' --info --debug --last 10m
```

Lines that carry the decision:

```
Quit 'T3 Code (Beta)' pid=60317
Quit decision: recent=false noWindows=true dock=true
Stopping background services for 'com.t3tools.t3code'
Application Dock item did not resolve to a running app — keeping bare Dock icon as target
Triggered 'Stop Running in Background' on Dock item
Terminating 9 processes for 'com.t3tools.t3code'
Gesture ignored (no routed action)
```

`Gesture ignored (no routed action)` means the gesture reached the router and found nothing to do. It is the signal for a broken target resolution.

## Known gotchas

Release builds drop `Logger.debug` lines. A probe that wrote one `.debug` and one `.info` line to this subsystem on 29 Oct 2026 stored only the `.info` line. Every diagnostic on the quit path therefore logs at `.info`. Do not move them back to `.debug`, and do not conclude from an empty log that the code did not run.

Quitting a lingering app from the keyboard needs the pointer on its Dock icon. Targeting is pointer based, and with no window there is no other element to resolve.

`make install` re-runs `tccutil reset Accessibility sj010.MCSC` because ad-hoc signing changes the cdhash on every build. macOS prompts for Accessibility again after each install, and MCSC logs `Waiting for accessibility permissions...` until the grant lands.

Mission Control previews still call `performForceQuit(on:)` directly, so a quit from a preview tile records no first strike. See `docs/decisions/ADR-001-quit-lingering-background-apps.md`.

## Constraints

The kill sweep allocates one pid buffer per call through `proc_listpids`, and MCSC calls it at most once per quit. Footprint measured 7.39 MB after these changes, under the 13 MB ceiling in `AGENTS.md`.
