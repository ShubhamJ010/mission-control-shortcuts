# ADR-001: Stop lingering apps through the Dock menu plus a bundle-wide kill

## Status

Accepted

## Date

2026-10-29

## Context

macOS 27 leaves an app in the Dock after its last window closes and labels it "Running in Background". MCSC's quit gesture and quit shortcut resolve their target through `TargetResolution`, and the Dock branch of that enum required an `NSRunningApplication`.

For a lingering app the main process is often gone, so `getAppFromDockItem(_:)` returned nil and `resolveTarget(at:)` returned `.none`. The gesture router then returned `.none`, and `routeShortcut` returned `.ignore` for any `.none` target inside the Dock region. Both paths are silent. The user reported that no action worked on an Electron app with a background service, and the logs showed nothing, which looked like the feature had never shipped.

Three more problems showed up once the path was reachable.

- The window branch of both routers called the legacy `ForceQuitAction`, which calls `forceTerminate()` directly. No attempt was recorded, so the second strike could never fire.
- `terminateBackgroundServices` called `forceTerminate()` before it opened the Dock menu and before it collected descendant pids. The Dock icon disappears with the process, and children reparent to launchd when the main process exits, so both of the follow-up steps ran too late.
- Every diagnostic on this path logged at `.debug`. A probe on 29 Oct 2026 wrote one `.debug` and one `.info` line to subsystem `sj010.MCSC` from a release-style binary, and only the `.info` line was stored. An empty log proved nothing about the code.

## Decision

Give a Dock icon without a process its own target case, `TargetResolution.lingeringDockItem(AXUIElement)`, and route it to a new `ForceQuitAppAction.perform(dockItem:)` that resolves the bundle from the icon's `AXURL` and stops it.

Make `BackgroundAppService.terminateBackgroundServices` run in this order: snapshot descendant and bundle pids, press the Dock's "Stop Running in Background" item, call `forceTerminate()`, then `SIGKILL` whatever is left.

Log the whole quit path at `.info`.

## Alternatives considered

### Keep returning `.none` when the Dock icon has no process

- Pros. No new enum case, no new routing.
- Cons. The quit action does nothing and says nothing. The icon cannot be dismissed from MCSC at all.
- Rejected. This is the reported bug.

### Require a live `NSRunningApplication` and handle the case in the settings UI

- Pros. One type to route on, no `AXUIElement` crossing the ViewModel layer.
- Cons. Nothing to route on when the process is gone. The Dock icon is the only handle the user still has.
- Rejected. The absence of a process is the state the feature exists for.

### Kill by pid only

- Pros. One syscall, no AX work.
- Cons. Electron and helper apps keep processes outside the main pid, and a snapshot taken after `forceTerminate()` misses the ones that reparented.
- Rejected. PID enumeration has to be tied to the bundle path.

### Press the Dock menu item only

- Pros. Uses the supported system action.
- Cons. The Dock offers the item only after the main process is dead. While the process lives the menu reads `Options | Show All Windows | Hide | Hide Others | Quit | Force Quit`, and the live-process case would then do nothing.
- Rejected on its own. It works as the first step, with the bundle-wide kill as the fallback.

### Log at `.debug` to keep the log quiet

- Pros. No lines in `log show` during normal use.
- Cons. Release builds drop those lines, which is what made this bug undiagnosable.
- Rejected. Quit diagnostics stay at `.info`, matching the existing `.info` calls on the gesture and event tap paths.

## Consequences

- A lingering Dock icon is now a valid routing target, so `TargetResolution` has one more case and every exhaustive switch over it handles it. Switches that mean "there is a live app" return nil for the new case.
- Quit reaches `ForceQuitAppAction` from the Dock, window, and shortcut paths. Mission Control previews still call `performForceQuit(on:)` directly and record no first strike.
- `applicationDockItem(for:)` accepts an icon whose subrole is not `AXApplicationDockItem` when it exposes a bundle URL. Electron and Mac Catalyst icons that report another subrole now resolve instead of falling through to `.none`.
- A quit can press the Dock context menu, so the menu flashes for about 0.12 seconds. That happens off the main thread.
- The kill sweep walks every process of the user session once per quit. It runs at most twice per app per 8 seconds.
- Rebuilds still reset Accessibility through ad-hoc signing, so `make install` re-prompts for the grant each time. A self-signed `MCSC-Dev` identity would fix that and is not part of this decision.
