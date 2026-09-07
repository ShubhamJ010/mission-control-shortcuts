# Move a Window to Another Desktop (Space)

This guide explains how MCSC moves an application window to the next or
previous Desktop (Space), and how you can reuse the same technique to move a
window to any other Space — for example, two Spaces over. It covers the core
sequence, the system constraints that shape it, and the extension points in
`MCSC/Models/Actions/DesktopNavigationActions.swift`.

## How it works

macOS provides no public API for moving a window between Spaces. MCSC works
around this by simulating what a user does manually: grab the window's title
bar, trigger the Space-switch hotkey while holding it, then release on the
new Desktop.

The sequence runs off-main on `DispatchQueue.global(qos: .userInitiated)` and
takes roughly 1.7 seconds:

1. Focus the target window through Accessibility.
2. Move the cursor to a title-bar grab point (`origin.x + 5, origin.y + 12`).
   Near the left end of the window, just left of the red traffic light,
   centered vertically — nudged left to ensure clear miss without hitting
   resizer/yellow.
3. Post a synthetic `.leftMouseDown` and keep it held.
4. Fire `Ctrl+Right` (or `Ctrl+Left`) through **System Events** (`osascript`)
   while the drag context is held.
5. Wait ~0.85s for the Space switch animation.
6. Post `.leftMouseDragged`, then `.leftMouseUp` at the same point (+3px) to
   release the window on its new Desktop.

## Key constraint: why System Events

The single most important detail: raw HID `CGEvent` posts of the arrow keys
are **dropped** while a synthetic drag context is held. Only the System
Events automation path reaches Dock's Space hotkeys during a drag:

```swift
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
process.arguments = [
    "-e",
    "tell application \"System Events\" to key code \(arrowKeyCode) using control down"
]
process.standardOutput = FileHandle.nullDevice
process.standardError = FileHandle.nullDevice
try? process.run()
process.waitUntilExit()
```

Key codes: Right Arrow = `124`, Left Arrow = `123`. These match Dock's
"Move left/right a space" shortcuts (symbolic hot keys 240/241).

<!-- prettier-ignore -->
> [!IMPORTANT]
> This technique requires the app to hold both **Accessibility** permission
> and **Automation → System Events** permission. The Space hotkeys must also
> be enabled in **System Settings → Keyboard → Shortcuts → Mission Control**.

## Mouse event details

Post mouse events with the `.hidSystemState` source at the `.cghidEventTap`,
so WindowServer sees the synthetic cursor movement before Exposé does:

```swift
CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState),
        mouseType: type,
        mouseCursorPosition: point,
        mouseButton: .left)?.post(tap: .cghidEventTap)
```

Pair the event post with `CGWarpMouseCursorPosition(_:)` before pressing:
the dual move lets WindowServer settle the cursor and makes the press land on
the intended title bar reliably.

## Mission Control handling

If Mission Control (or the App Exposé variant) is open when the action fires,
dismiss it first by posting Escape, then wait ~0.45s before starting the
drag. Otherwise the drag lands nowhere useful. In production,
`ShortcutViewModel` supplies an `isMissionControlActiveProvider` closure so
`MoveWindowToDesktopAction` checks this without polling.

## Extending to arbitrary Spaces

The shipped implementation supports only adjacent Spaces (`next` /
`previous`). To move a window to a non-adjacent Space — say, two to the
right — repeat the Space-switch step while keeping the mouse held:

1. Follow steps 1–3 above to grab the title bar.
2. Fire `Ctrl+Right` once per Space you want to traverse, waiting
   ~0.85s after each switch for the animation.
3. Release the mouse only after the last switch completes.

Keep every intermediate switch inside the held-drag window. If you release
between switches, the window stays behind and only the view moves. For large
traversals, consider increasing the per-switch wait slightly, since Dock
queues animations when switches arrive faster than they render.

<!-- prettier-ignore -->
> [!NOTE]
> Each Space switch spawns one `osascript` process. That cost is acceptable
> at MCSC's scale but avoid batching many moves back-to-back; memory and
> process churn are tracked against the project's 13 MB ceiling philosophy.

## Where the code lives

- Production implementation:
  `MCSC/Models/Actions/DesktopNavigationActions.swift`
  (`MoveWindowToDesktopAction`), registered as
  `moveNextDesktop` / `movePreviousDesktop` in `GestureAction`.
- Routing: `MCSC/ViewModels/Routing/GestureActionRouter.swift`.
- Cursor feedback modes: `spaceLeft` / `spaceRight` in
  `MCSC/Views/CursorFeedbackMode.swift`.
- Tests: `DesktopNavigationActionTests` in `Tests/RouterTests.swift`.

The production code injects side-effect closures (`postMouseEvent`,
`sendSpaceSwitchShortcut`, `waitFor`, and others) so tests can record the
event sequence without posting real events or sleeping.

## Next steps

- Read [GESTURES.md](GESTURES.md) to bind the desktop-move actions to a
  gesture.
- See [SHORTCUTS.md](SHORTCUTS.md) for keyboard-triggered actions.
