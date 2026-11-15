# Dock auto-hide latch on macOS 27 (Dock stays visible, windows do not reflow)

**Status:** investigatory / diagnosis — **re-opened 2026-11-13, see §13**
**Reported on:** MCSC 0.8.4 (build 19), macOS 27.2 (build `26B123`)
**Investigated:** 2026-11-12 · re-validated 2026-11-12 (see §10) · **measured live 2026-11-13 (§12)** · **A/B re-investigated with MCSC down 2026-11-13 (§13)**
**Verdict (revised 2026-11-13, §13):** the earlier "this is an OS bug, not MCSC"
verdict **no longer holds**. With the app down for 13 h 22 min — more Dock and
Mission Control activity than the app-up window it is compared against — the
fault did not occur once, and no independent observer ever saw the 113 pt
reservation. The latch is still a Dock/WindowManager race at the OS level, but
the evidence now says MCSC either **triggers or sustains** it: 14 latch reports
in the 2 h 52 min it was running, 0 in the 13 h 22 min it was not (§13.2).
Four app-side mechanisms survive code review (B, C, D, E), one of which
(§13.4 D) also explains the dead band *without* any system-wide desync. §12's mechanism story
is now the **least** supported of the candidates, not the confirmed one.

> **Original verdict (2026-11-13, superseded by §13 — kept for the record).**
> The latch is a Dock / WindowManager bug in macOS 27, not MCSC changing Dock
> state. MCSC has no code path that shows, unhides or reconfigures the Dock.

> **Correction (2026-11-13).** §1–§3 describe the latch as *"the Dock logs the
> hide and the bar stays on screen"*. The live measurement in §12 shows the
> opposite and more consequential form: **the Dock bar is hidden while the
> screen layout still reserves the Dock's 113 pt strip**. The symptom the user
> actually sees is that windows cannot be filled edge to edge. The underlying
> desync — the Dock and `com.apple.WindowManager` disagreeing about whether
> the Dock is shown — is the same one §3.1 hypothesised, and §12 assumed it
> was confirmed by direct measurement.
>
> **Superseded 2026-11-13 (§13).** "Direct measurement" here means a reading
> taken inside MCSC's own process; §13.1 shows an independent process never
> saw the reservation across 1,569 samples in 13 h with the app down, so the
> ownership of the stale reservation is still open. The *symptom* description
> above stands; the *attribution* does not.
> Also note: the 113 pt figure is only "the Dock's strip" if the Dock really
> reserves it — `DockLatchMonitor` derives it from `NSScreen.visibleFrame`, so
> the number is whatever that process believes, not an independent fact.

---

## 1. Symptom, stated precisely

Auto-hide is on (`Dock → autohide = 1`, Dock pinned to the bottom edge). From
time to time the Dock strip slides up and then **never slides back down**, even
though the pointer is nowhere near the bottom edge. App windows keep the layout
they had while the Dock was hidden, so the strip is composited *over* the
window instead of the window shrinking above it (this is the screenshot: the
Freebuff window still runs to the bottom edge, with the Dock drawn on top).

Toggling "Automatically hide and show the Dock" off and on in System Settings
fixes it instantly, and nothing else does. That matches every occurrence in the
system log.

The important detail is that this is **not** "the Dock revealed because the
pointer hit the hot edge". A normal reveal takes ~0.9 s and is followed by a
`Hiding all windows` event in the Dock's log. In the failing case the Dock
**logs the hide and the bar was still on screen** — the user's manual reset
comes 1–4 s later, which is only explicable if the bar never actually left
the screen. The hide half of the transaction never reached the composite.
That is the whole bug in one sentence.

*Caveat, stated because the Dock's log cannot prove it on its own:* the Dock
logs hide **intent**. There is no line in the Dock's log that says "the bar is
on screen". The inference is from the user's reaction — a reset 1–4 s after a
logged hide that had no reason to happen otherwise — and it is the same
inference the user made visually. See §10 for what would make it certain.

---

## 2. Evidence collected on this machine

### 2.1 Environment

| Item | Value |
|---|---|
| OS | macOS 27.2 (`26B123`) |
| Dock | PID 76368, running continuously for 2 d 05 h (never restarted) |
| `com.apple.dock` | `autohide = 1`, `orientation = bottom`, `magnification = 1`, `tilesize = 87` |
| MCSC | `/Applications/MCSC.app` 0.8.4 (19) |
| MCSC state during capture | **not running** (clean termination at 15:29:29, no relaunch) |
| WindowServer uptime | 12 d 19 h (no recent restarts) |

The Dock process **was not killed** during any of the resets, so "reset the
Dock" here means *re-applying the autohide preference*, which the Dock handles
live (`event-handling: Disabling…` → `event-handling: Starting autohide`).

### 2.2 The failure signature

`log show --predicate 'process == "Dock"' --start "2026-11-11 22:36:30" --end "2026-11-11 22:36:45"`:

```
22:36:33.912  event-queue        Adding mouse enter event
22:36:33.912  dock-bar-additions Showing all windows
22:36:37.458  event-queue        Adding mouse leave event        <- pointer left the Dock
22:36:37.766  dock-bar-additions Hiding all windows             <- Dock says it hid
22:36:42.197  event-handling     Disabling; setting autoHideOn=0   <- user's manual reset
22:36:42.198  dock-bar-additions Showing all windows
22:36:42.543  event-handling     Starting autohide
22:36:42.791  dock-bar-additions Hiding all windows             <- only now does the bar go away
```

The pointer left and the Dock logged the hide; the user's manual reset 4.4 s
later is only explicable if the bar was still on screen — and the reset is
exactly what the log shows next.

Same pattern at 16:03 on 2026-11-12 (again with MCSC not running):

```
16:03:46.946  Adding mouse enter event / Showing all windows
16:03:47.919  event-handling Disabling; setting autoHideOn=0     <- manual reset 1 s later
16:03:49.707  event-handling Starting autohide
16:03:49.948  Hiding all windows
```

### 2.3 It reproduces without MCSC

The two clearest latches (2026-11-12 16:03 and 21:25) happened 34 minutes and
~5.5 hours respectively after MCSC exited:

* MCSC unified-log entries stop at `15:29:29` local (`Termination complete`).
  The JSONL writes the same moment as `2026-11-12T09:59:29Z` — this machine
  runs UTC+05:30, so local time and the `Z` suffix differ by 5.5 hours.
* `pgrep MCSC` → nothing, before and during the captures.
* `~/Library/Logs/MCSC/diagnostic_report.jsonl` ends with the clean-termination
  record; there is no `crash.log` and no `.ips` report.

So on this machine the latch occurs with **zero** MCSC processes, event taps, AX
observers and overlay panels alive. That alone rules MCSC out as the cause of
*these* occurrences.

### 2.4 How often it happens

`com.apple.dock:event-handling` records a real preference re-apply only when the
user changes the Dock setting. Between 2026-11-10 and 2026-11-12 the Dock logged
**45** `Disabling` / `Starting autohide` events — exactly 23 `Disabling` and
22 `Starting autohide` — i.e. roughly two dozen autohide re-applies.

Grouped into episodes (an episode = one or more toggle-off/toggle-on cycles
close together), the full population of the 23 `Disabling` events is:

| Time | Episode | MCSC running? |
|---|---|---|
| Nov 11 15:54 | 1 | yes (PID 76246) |
| Nov 11 16:01 | 1 | yes |
| Nov 11 17:22 | 1 | yes |
| Nov 11 17:44 / 17:46 / 17:49 | 3 | yes |
| Nov 11 17:55 | 1 | yes |
| Nov 11 18:47 / 18:50 / 18:54 | 3 | yes |
| Nov 11 19:32 | 2 pairs | yes |
| Nov 11 19:38 | 1 pair | yes |
| Nov 11 20:13 | 1 pair (3 events) | yes |
| Nov 11 22:36 | 1 pair | yes |
| Nov 11 22:44 | 1 pair | yes (MCSC quit 6 s later) |
| Nov 11 22:50 | 1 pair | no (quit 22:44:58) |
| Nov 12 00:20 | 1 pair | no |
| Nov 12 15:29 | 1 pair (10 s after MCSC quit) | no (quit 15:29:29) |
| Nov 12 16:03 | 1 pair | no |
| Nov 12 21:25 | 2 pairs (4 events) | no |

**17 of the 23 events happened while MCSC was running**; 6 happened with MCSC
gone. The claim this doc used to make — "consistent frequency in both states" —
is **not supported**. The honest statement is weaker and more useful:

* MCSC was alive for the entire dense Nov 11 15:54–22:44 cluster (PID 76246
  observed at 15:20, 15:28 and 18:46 in its own unified-log entries;
  `Termination complete` at 22:44:58) and for Nov 12 14:26–15:29 (PID 92531).
* MCSC was *not* alive for the Nov 12 16:03 and 21:25 latches — those are the
  two the diagnosis rests on.
* The per-hour rate cannot be computed honestly: MCSC's exact alive intervals
  on Nov 10–11 are no longer recoverable from the unified log (only the
  Nov 11 22:44 termination onward survives for `process == "MCSC"`), so the
  denominator on the "MCSC running" side is unknown.

What survives is the important asymmetry: **the latch occurs with MCSC absent
(6 events) and with MCSC present (17 events).** Frequency cannot separate the
two populations, but the mechanism can — see §4 and §5.

---

## 3. Why this looks like an OS bug, not an app bug

### 3.1 The Dock's own state machine is the thing that desyncs

The Dock owns reveal/hide (`dock-bar-additions`, `event-handling`). Apps cannot
"unhide" it — there is no public API for that, and the private SPI that used to
exist (`CoreDockSendNotification`) only *wakes* the Dock, it does not pin the
bar on screen.

The log line that dates the split is:

```
[com.apple.windowmanager:xpc] Asynchronously setting dock info
```

which appears immediately after every autohide re-apply. On macOS 27 the desktop
chrome (spaces, Mission Control composition, the Dock's geometry as seen by the
window server) is owned by `com.apple.WindowManager`, not only by `com.apple.dock`
— the same split already documented for Mission Control detection in
[`MISSION_CONTROL.md`](./MISSION_CONTROL.md#multi-space-isolation--macos-27-ghosting).
That introduces a second copy of "is the Dock shown?" and the two copies can
diverge: the Dock bar window is ordered back in by WindowManager's dock info
while `dock-bar-additions` believes the bar is hidden. Re-applying autohide
rewrites the dock info and re-syncs both, which is why the toggle fixes it and
why `killall Dock` also works as a bigger hammer.

### 3.2 Mission Control churn is *a* predecessor, but not a reliable one

Mission Control is often active around a latch — the Dock shows its bar while
Mission Control is up, so MC transitions and Dock-bar transitions share a log
neighbourhood. But this doc previously claimed "almost every latch is preceded
by Mission Control being entered and exited within a second or two". **That
claim does not survive measurement.**

Mission Control is in near-continuous churn on this machine: **2158
`missioncontrol: Changing from mode …` transitions in the 35 hours from
2026-11-11 12:00 to 2026-11-12 23:00 — one every ~58 seconds.** Against that
base rate:

| Window before the reset | Resets with an MC transition in it | Base rate if MC were irrelevant |
|---|---|---|
| 5 s | 5 / 23 (22 %) | 8.6 % |
| 10 s | 8 / 23 (35 %) | 17.1 % |

So MC churn immediately before a reset is roughly 2× the background rate — a
weak correlate, not a mechanism. The decisive counter-example is the doc's own
clearest latch: **the 21:25 occurrence has no Mission Control activity for the
3 minutes before it** (last transition 21:22:11.231, latch onset 21:25:05.868;
the next transition is 21:26:24.366, *after* the reset). Whatever causes the
21:25 latch, it is not Mission Control.

MC does matter for the 16:03 occurrence: MC was entered at 16:03:44.270, the
bar's show/hide control value ramped `0.0 → 1.0 → 0.0` between 16:03:44.300
and 16:03:45.721, and the reset came 2.7 s later.

The one structurally broken sequence found in the log is:

```
21:21:43.786  Adding mouse enter event
21:21:43.786  Showing all windows                  <- bar on screen
21:21:43.962  missioncontrol: .none -> missionControl
21:21:43.962  setting autoHideOn=1
21:21:43.968  Not in windows mode; did NOT hide    <- hide skipped, bar stays
21:21:43.998  Showing all windows
```

The Dock deliberately refuses to hide while it thinks it is hosting Mission
Control's `showAllWindows` bar. If the Mission Control transition and the Dock
bar's own hide race (the two `dock-bar-additions` threads `7c75a4`/`7c75be`
interleave here), the bar can be left ordered in with nothing scheduled to
remove it. That is the same race the OS is having with itself; MCSC is not in
this transaction at all.

There are two `did NOT hide` events in three days, so this specific race is
rare, but it is the only sequence in the log that leaves the bar up with no
pending hide.

### 3.3 It is already a known class of bug on macOS 26/27

Auto-hide desync after Mission Control, after sleep/wake, and after full-screen
transitions is widely reported since Tahoe, and the workaround users converge on
is exactly the one used here (toggle the setting, or ⌥⌘D twice):

* Apple Community — "Dock keeps auto-hiding on macOS Tahoe": toggle the setting
  off/on to recover, recurs over days.
  <https://discussions.apple.com/thread/256140771>
* Apple Community — "Dock keeps disappearing after macOS Tahoe 26.0 update":
  toggle restores it; present in 26.0.1 too.
  <https://discussions.apple.com/thread/256147871>
* Apple Community — "Dock Does Not Auto-Hide for Fullscreen Apps": dock gets
  stuck after a display/full-screen transition; only a Dock restart fixes it.
  <https://discussions.apple.com/thread/252128301>
* r/MacOS — "Dock autohide bug after mission control": dock randomly stays
  shown after Mission Control; the user's fix is to nudge the Dock geometry.
  <https://www.reddit.com/r/MacOS/comments/n8z3cg/dock_autohide_bug_after_mission_control/>

None of these involve a third-party utility; all of them are the same
"Dock thinks it hid, WindowServer kept the bar" failure.

---

## 4. Everything MCSC does that touches the Dock

Checked exhaustively, with the reason each one cannot latch the bar:

| Mechanism | Where | Reads / writes | Can it pin the Dock bar? |
|---|---|---|---|
| `autohide` preference read | `AccessibilityService.swift:162-166` | **read only** (`UserDefaults(suiteName: "com.apple.dock")`) | No — never written anywhere in the repo |
| Cached Dock `AXUIElement` + icon-list frame | `AccessibilityService.swift:135-166`, `refreshDockFrame()` | AX reads | No |
| `isDockRegion(at:)` hit-tests | `AccessibilityService.swift:734-762` | `AXUIElementCopyElementAtPosition` on the Dock | No |
| Dock AXObserver (`AXExposeShowAllWindows`, `AXExposeExit`, …) | `MissionControlHoverService+Observers.swift:4-10` | AX notifications | No |
| Dock relaunch observer → re-attach observer | `MissionControlHoverService+Observers.swift:16-44` | AX | No |
| Keyboard HID tap (always on) | `EventTapService.swift` | swallows bound key events only | No |
| Mouse HID tap (always on while hover tracking) | `MissionControlHoverService+InputTap.swift` | swallows only clicks on MCSC's own overlay button; passes `mouseMoved`/`mouseUp` through | No |
| Dock interaction suppressor (opt-in, default **off**) | `Dock/DockInteractionSuppressor.swift` | swallows synthesized clicks + gesture events over the Dock | No — physical mouse-ups always pass through (§5 A) |
| Synthetic mouse moves / warps | `WindowActivationAction.swift`, `DesktopNavigationActions.swift` | posts `mouseMoved`/clicks, warps the hardware cursor | Only if a warp lands in the Dock's reveal band — see §5 |
| Overlay panels (`.screenSaverWindow`, `.canJoinAllSpaces`) | `Views/OverlayPanelFactory.swift` | own windows only | No — they never order the Dock |
| Mission Control polling (5 Hz, `CGWindowListCopyWindowInfo`) + 350 ms cache | `MissionControlService.swift` | WindowServer reads | No |
| `NSApp.setActivationPolicy(.accessory)` | `App/AppDelegate.swift:29` | own app | No |

Also verified: **no** `presentationOptions`, **no** `NSApplication.hide/unhide`,
**no** `defaults write com.apple.dock`, **no** `killall Dock`, and **no**
`CoreDockSendNotification` call anywhere in `MCSC/`. The Dock/Exposé SPI is
referenced only in the documentation — `docs/SHORTCUTS.md:107`,
`docs/SHORTCUTS.md:127`, `docs/GESTURES.md:232`, `docs/ARCHITECTURE.md:61`,
`docs/MISSION_CONTROL.md:81` and `README.md:224` (plus historical mentions in
`CHANGELOG.md`) — and those references are **stale** (see §7).

---

## 5. The two app-side mechanisms worth keeping on the list

They did not cause the captured occurrences, but they are the only places where
MCSC could plausibly interact with Dock reveal/hide, so they should be
falsifiable rather than dismissed. One of the two has now been falsified by
the code; the other survives and is the highest-value thing to instrument.

**A. Suppressed Dock mouse-up. — Falsified by the code.**
`DockInteractionSuppressor` swallows `leftMouseDown`/`leftMouseUp` over the
Dock while `isSuppressing` is set (the two-finger double-tap window). The
concern was that a swallowed release leaves the Dock holding a "mouse is down
inside me" state.

It cannot. `DockInteractionSuppressor.swift:147-155` handles the mouse-up
path with two explicit escapes:

```swift
if isMouseUp {
    if hasActivePhysicalMouseDown {          // physical press-click release
        hasActivePhysicalMouseDown = false
        return event                         // always passes through
    }
    let pressure = event.getDoubleValueField(.mouseEventPressure)
    if pressure > 0.0 {
        return event                         // any press-click with pressure
    }
    if isSuppressing, isDockHoveredProvider?(location) ?? false {
        return nil                           // only zero-pressure synthesized up
    }
```

Only a **synthesized, zero-pressure** mouse-up is ever swallowed
(`DockInteractionSuppressor.swift:156-158`). Every physical release — the only
kind the Dock's own "mouse is inside me" tracking cares about — passes
through untouched. Hypothesis A is therefore dead on the code, not merely on
the circumstances of the captured occurrences.

Residual worth keeping: the suppressor is opt-in and default **off**
(`DockInteractionSuppressor.swift:110`), so it cannot explain anything on a
default install either.

**B. Cursor warp into the reveal band.** `CGWarpMouseCursorPosition` +
synthetic `mouseMoved` (Mission Control type-to-select, activation click,
"move window to desktop") moves the pointer without the pointer actually
travelling there. If a warp lands inside the Dock's bottom reveal band, the
Dock reveals; the follow-up "leave" depends on the next real HID move, which may
never arrive if the user's hand is nowhere near the bottom edge.
Signature: the Dock log shows `Adding mouse enter event` with **no** matching
`mouse leave`, immediately after a `MCSC` log line of category `missionControl`
(`activateSelectedWindow` / `postSyntheticMouseMoved`) or `gesture`
(`moveToDesktop`).

**B is the only surviving app-side hypothesis.** A is dead (see above). B
survives because MCSC *can* move the pointer without the pointer travelling:
`CGWarpMouseCursorPosition` relocates the cursor outright, and a synthetic
`mouseMoved` lets the Dock believe the pointer is somewhere it never was. If
that lands in the Dock's reveal band, the Dock shows its bar, and the matching
"leave" needs a *real* HID move that may never come.

Both hypotheses require MCSC to be running at the moment of the latch. That is
**not** true of every latch: of the 23 reset events, 17 occurred while MCSC was
running, and at least two of them carry the full latch signature —

* `2026-11-11 18:47:59.767` mouse enter → `Showing all windows` → reset
  `0.2 s` later (MCSC PID 76246 alive);
* `2026-11-11 22:36:33.912` mouse enter → `Showing all windows` →
  `22:36:37.766` `Hiding all windows` → reset at `22:36:42.197`, 4.4 s later
  (MCSC PID 76246 alive).

So B is **not** dismissed. It is the only mechanism by which MCSC could
interact with Dock reveal/hide, and it is now the highest-value thing to
instrument (§7.3).

---

## 6. How to confirm or refute this in 60 seconds next time

Run these **while the Dock is stuck**, before touching anything:

```bash
# NOTE: use /usr/bin/log, not bare `log` — zsh ships a `log()` math builtin
# and `log show ...` fails with "zsh:log:1: too many arguments".

# 1. Did the Dock log a hide that did not visually happen?
/usr/bin/log show --predicate 'process == "Dock"' --last 5m --style compact \
  | grep -E "Showing all windows|Hiding all windows|did NOT hide|event-handling|missioncontrol"

# 1b. What did the Dock's own show/hide control value do? (0 = hidden, 1 = shown)
/usr/bin/log show --predicate 'process == "Dock"' --last 5m --style compact \
  | grep -oE "^[0-9-]+ [0-9:.]+.*newSystemControlValue=[0-9.]+" | tail -40

# 2. Is the Dock bar still in the WindowServer's on-screen window list?
#    (layer ~18-20, owner "Dock", empty name => the bar is ordered in)
/usr/bin/log show --predicate 'process == "WindowServer"' --last 2m --style compact \
  | grep -i dock | tail -20

# 3. Was MCSC even alive, and what was it doing?
pgrep -lf MCSC
/usr/bin/log show --predicate 'subsystem == "sj010.MCSC"' --last 10m --info --debug --style compact

# 4. Is the preference still what the UI claims?
defaults read com.apple.dock autohide      # expect 1
```

Probe 1b is the closest thing to an objective "was the bar really visible"
signal the Dock's own log offers: `newSystemControlValue` is the bar's
show/hide animation parameter. It tracks the Dock's *intent*, so it reaches
`0.0` even when the bar fails to leave the screen — which is exactly why it
must be read together with the WindowServer window list (probe 2), not on its
own.

Interpretation:

| Observation | Conclusion |
|---|---|
| `Hiding all windows` logged, bar still visible, `pgrep MCSC` empty | OS latch — file with Apple, workaround only |
| No `Hiding all windows` at all, `pgrep MCSC` empty | OS latch (hide never scheduled) |
| No hide, MCSC alive, MCSC `missionControl` synthetic-move log just before | app-assisted (hypothesis B) |
| No hide, MCSC alive, `isDockActionsOutsideMCEnabled` on, gesture just before | app-assisted (hypothesis A) |

Recovery, in increasing order of violence:

Toggle "Automatically hide and show the Dock" off and on in System Settings —
this re-applies the preference live and does **not** restart the Dock, which is
why the PID stays the same across every reset in the log above. ⌥⌘D twice
(Toggle Dock hiding) is the keyboard equivalent. As a heavier fallback,
`killall Dock` restarts the Dock process and re-reads `com.apple.dock`.

---

## 7. Recommended follow-ups for MCSC

1. **Fix the stale docs.** `docs/SHORTCUTS.md:107`, `docs/SHORTCUTS.md:127`,
   `docs/GESTURES.md:232`, `docs/ARCHITECTURE.md:61`, `docs/MISSION_CONTROL.md:81`
   and `README.md:224` describe `CoreDockSendNotification` wake calls that
   no longer exist in the codebase. They make the app look like it pokes Dock
   internals, which it does not — this matters when triaging a Dock bug.
2. **Cheap diagnostic, no memory cost.** On every
   `MissionControlService.markActive(_:)` transition, log one line with
   `Dock.autohide`, whether a `Dock` window at layer ≥ 18 is on screen
   (`CGWindowListCopyWindowInfo`, already paid for by the detector) and the
   pointer position. That turns any future "dock went weird" report into a
   one-query answer, and it costs one dictionary of already-collected data —
   within the 13 MB budget in `AGENTS.md`.
3. **Instrument the one live hypothesis (B).** §2.4 shows the latch occurs with
   MCSC running in 17 of 23 recorded events, §5 shows hypothesis A is dead on
   the code and leaves B as the only app-side candidate, and two latch-shaped
   occurrences happened with MCSC alive.
   **→ Shipped in 0.8.5 — see §11.** Status revised in §13.3: B is not
   supported by any recorded episode, and three further app-side mechanisms
   (§13.4 C/D/E) were missing from this list.
4. **Do not add a Dock watchdog.** Actively rewriting `autohide` or restarting
   the Dock from a background utility is exactly the kind of system-wide
   side effect this project avoids, and it would mask an OS bug rather than fix
   it. If a workaround is ever wanted, it belongs behind an explicit,
   default-off setting.
5. **Re-test hypothesis B on the next occurrence**, whatever the report says.
   It is the only surviving app-side candidate, and §2.4 shows the
   app-running population is the larger one. The instrumentation in §11 makes
   this a one-query answer.

---

## 8. Appendix — raw log excerpts

Dock latch and manual reset, 2026-11-12 21:25 (MCSC not running):

```
21:25:05.868  Adding mouse enter event
21:25:05.868  Showing all windows
21:25:06.449  Adding mouse leave event
21:25:06.749  Hiding all windows
21:25:07.900  event-handling  Disabling; setting autoHideOn=0
21:25:07.900  Showing all windows
21:25:07.900  com.apple.chrono  Reloading control for extension: com.apple.dock.controls
              kind: com.apple.dock.autohide reason: Request reload due to autohide pref change
21:25:07.917  com.apple.windowmanager:xpc  Asynchronously setting dock info
21:25:08.836  event-handling  Starting autohide
21:25:09.881  Hiding all windows
21:25:11.021  event-handling  Disabling; setting autoHideOn=0     <- second toggle
21:25:15.267  event-handling  Starting autohide
21:25:15.515  Hiding all windows
```

Mission Control vs. Dock bar race, 2026-11-12 21:21:

```
21:21:43.786  Adding mouse enter event
21:21:43.786  Showing all windows
21:21:43.962  missioncontrol  Changing from mode .none to missionControl
21:21:43.962  setting autoHideOn=1
21:21:43.968  Not in windows mode; did NOT hide
21:21:43.998  Showing all windows
21:21:44.463  setting autoHideOn=0
21:21:45.466  missioncontrol  Changing from mode .showAllWindows to off
21:21:46.068  Hiding all windows
```

MCSC lifecycle around the captures (no process alive). Two different sources —
the unified log and MCSC's own JSONL — are shown together here; the first line
is MCSC's `AppLogger` record, the rest is the unified log:

```
# ~/Library/Logs/MCSC/diagnostic_report.jsonl
{"category":"diagnostics","subsystem":"sj010.MCSC","timestamp":"2026-11-12T09:59:29Z",
 "message":"Application will terminate cleanly.","level":"INFO"}

# /usr/bin/log show --predicate 'process == "MCSC"' --start "2026-11-12 15:29:25"
2026-11-12 15:29:29.709  MCSC[92531:92aca4] [com.apple.AppKit:Application] terminate:
2026-11-12 15:29:35.681  MCSC[92531:92aca4] [com.apple.AppKit:Application] Termination complete. Exiting without sudden termination.

$ pgrep -lf MCSC      # (no output, at 21:2x and 21:3x)
```

Note the two clocks: `15:29:29.709` is local (UTC+05:30), `09:59:29Z` is the
same instant in UTC.

---

## 9. Source references

- Dock read-only preferences and region hit-testing:
  `../MCSC/Services/Accessibility/AccessibilityService.swift` (`isDockAutoHideEnabled`,
  `refreshDockFrame()`, `isDockRegion(at:)`)
- Dock AXObserver and relaunch handling:
  `../MCSC/Services/MissionControl/MissionControlHoverService+Observers.swift`
- Always-on mouse tap: `../MCSC/Services/MissionControl/MissionControlHoverService+InputTap.swift`
- Optional Dock suppressor: `../MCSC/Services/Dock/DockInteractionSuppressor.swift`
- Synthetic pointer movement: `../MCSC/Models/Actions/WindowActivationAction.swift`,
  `../MCSC/Models/Actions/WindowActions/DesktopNavigationActions.swift`
- Overlay window levels: `../MCSC/Views/OverlayPanelFactory.swift`
- Mission Control detection (WindowManager layer 19): `../MCSC/Services/MissionControl/MissionControlService.swift`
- macOS 27 desktop-chrome ownership: [`MISSION_CONTROL.md`](./MISSION_CONTROL.md)
- Diagnostics and log locations: [`DIAGNOSTICS.md`](./DIAGNOSTICS.md)

---

## 10. Validation record (2026-11-12, second pass)

Everything in this doc was re-derived from scratch against the live machine and
the repo. Results:

### Verified — reproduced exactly

| Claim | Result |
|---|---|
| macOS 27.2 (`26B123`), MCSC 0.8.4 (19) | ✅ exact |
| Dock PID 76368, continuous, never restarted | ✅ `2-06:18:22` elapsed |
| `com.apple.dock`: `autohide=1`, `orientation=bottom` | ✅ |
| WindowServer uptime ~12 d 20 h | ✅ |
| No MCSC process during the 16:03 / 21:25 captures | ✅ `pgrep` empty |
| No `crash.log`, no `.ips` for MCSC | ✅ only `diagnostic_report.jsonl` |
| §2.2 excerpt (Nov 11 22:36) | ✅ reproduces line-for-line |
| §2.2 excerpt (Nov 12 16:03) | ✅ reproduces line-for-line |
| §3.2 excerpt (Nov 12 21:21 race) | ✅ reproduces line-for-line |
| §8 excerpt (Nov 12 21:25) | ✅ reproduces line-for-line |
| "45 `Disabling`/`Starting autohide` events" | ✅ exactly 23 + 22 |
| "two `did NOT hide` events in three days" | ✅ exactly 2 |
| §4 code-path table, all 11 rows + file:line refs | ✅ every reference checked |
| No `presentationOptions` / `NSApp.hide` / `defaults write com.apple.dock` / `killall Dock` | ✅ none in `MCSC/` |
| No `CoreDockSendNotification` in `MCSC/` | ✅ none (only in docs — now listed in §4) |
| §6 triage command 3 returns live MCSC logs | ✅ |

### Corrected in this pass

| § | Was | Now |
|---|---|---|
| §1 | "the bar stays on screen" stated as fact | stated as an inference from the user's reaction, with the caveat |
| §2.3 | "hours after MCSC exited" | 34 min and ~5.5 h |
| §2.3 | clean-termination record "at `15:29:29Z`" | `09:59:29Z` UTC = 15:29:29 local (UTC+05:30) |
| §2.4 | "eleven resets … consistent frequency in both states" | full 23-event table; **17 with MCSC running, 6 without**; rate not computable |
| §3.2 | "almost every latch is preceded by Mission Control" | measured: 5/23 within 5 s, 8/23 within 10 s, vs 8.6 %/17.1 % base rate; the 21:25 latch has **no** MC activity for 3 min |
| §4, §7.1 | 3 stale `CoreDockSendNotification` references | 6, incl. `MISSION_CONTROL.md:81` and `README.md:224` |
| §5 A | "falsified for these occurrences" | **falsified by the code** — physical mouse-ups always pass through |
| §6 | bare `log show` | `/usr/bin/log show` (zsh's `log()` math builtin breaks bare `log`), plus a `newSystemControlValue` probe |
| §8 | unified-log and JSONL lines blended | labelled by source |

### Still not proven

* **That the bar was on screen.** The Dock's log records *intent*; it never
  states the bar's on-screen state. The evidence is the user's reaction, which
  is strong but circumstantial. To make it certain, capture the WindowServer
  window list at the moment of the latch (probe 2 in §6) — the Dock bar window
  at layer ~18–20 with an empty name.
  **→ Now measured directly — see §11.1.**
* **The WindowManager dock-info desync (§3.1).** Inferred from the log pattern
  and from matching macOS 26/27 reports. Not proven from Apple source, and not
  provable from the unified log.
* **That MCSC had no part in the 17 app-running events.** §5 B is still open.
  **→ Now instrumented — see §11.2.**

---

## 11. Shipped instrumentation (0.8.5)

Two pieces were added so the next occurrence answers every open question in
one query instead of requiring a post-hoc reconstruction.

### 11.1 `DockLatchMonitor` — the latch, measured instead of inferred

`MCSC/Services/Dock/DockLatchMonitor.swift` is a passive observer. It never
writes Dock preferences, never restarts the Dock and never moves the pointer.

The detection rests on one fact about the compositor, verified on macOS 27.2:

> `CGWindowListCopyWindowInfo([.optionOnScreenOnly, …])` **omits** the Dock's
> bar window while the Dock is hidden, and **includes** it while the bar is
> composited on screen.

The Dock's bar window is owned by `"Dock"` at layer 20. So its presence in the
on-screen window list is a direct read of "is the bar actually on screen" —
the one thing the Dock's own log cannot tell you.

That scan is *already paid for*: `MissionControlService` runs it every ~350 ms
to detect Mission Control. `DockLatchMonitor` subscribes to it via
`MissionControlService.onWindowListScanned`, so the monitor adds **no polling
timer and no extra window-server round trip**.

A latch is reported when all of these hold continuously for
`persistenceThreshold` (2 s — long enough to ignore the Dock's ~0.3 s
show/hide animations):

| Condition | Why |
|---|---|
| the Dock's bar window is in the on-screen window list | the bar is composited |
| `com.apple.dock` `autohide == 1` | the Dock is *meant* to be hidden |
| Mission Control is not active | MC legitimately shows the bar |
| the pointer is more than 160 pt above the bottom edge | the user is not interacting with the Dock |

The 160 pt interaction zone is deliberate: it covers the Dock's hot edge *and*
the whole bar (≈87 pt at the default `tilesize`, taller when magnified), so a
pointer parked over a legitimately revealed Dock never trips the detector.

The report is a single line:

```
Dock auto-hide latch detected — Dock bar composited on screen while the Dock is
set to auto-hide (held 4.2s, pointer 512pt above the bottom edge, last
synthetic pointer action: postSyntheticMouseMoved 0.31s at (735,954))
```

`.notice` level, so it shows up in a plain `log show` without `--info`, and it
lands in `~/Library/Logs/MCSC/diagnostic_report.jsonl` through the existing
`OSLogStore` dump.

### 11.2 `SyntheticPointerAudit` — hypothesis B, on the record

`MCSC/Models/SyntheticPointerAudit.swift` records the most recent synthetic
pointer action MCSC performed (a `CGWarpMouseCursorPosition` or a posted
`mouseMoved`). It is pure Model code — no logging, no service dependencies —
and it is called from the two places that move the pointer:

* `WindowActivationAction.postSyntheticMouseMoved(to:)` (Mission Control
  type-to-select, activation click)
* `MoveWindowToDesktopAction.warpCursor` (move window to desktop)

`DockLatchMonitor` surfaces each new action as its own log line, so the audit
trail exists **whether or not a latch ever happens**:

```
synthetic pointer action: postSyntheticMouseMoved at (735,954)
```

Correlate that timestamp against the Dock's own `event-queue` lines to settle
hypothesis B directly: if a `Adding mouse enter event` with **no** matching
`mouse leave` follows an MCSC synthetic move into the bottom band, MCSC
caused the reveal.

### 11.3 Verification performed

| Check | Result |
|---|---|
| Signal: Dock hidden → bar window absent from the on-screen list | ✅ |
| Signal: Dock revealed → bar window present (layer 20) | ✅ |
| Detector fires when the condition holds | ✅ (verified with a 1 pt interaction zone; report line captured) |
| No false positive while the Dock is hidden and idle (8 s) | ✅ |
| No false positive on a normal reveal → hide cycle | ✅ |
| No false positive with the pointer parked over a revealed bar | ✅ |
| Synthetic-pointer audit reaches the log | ✅ (verified end to end) |
| Mission Control detection unaffected by the scan change | ✅ (the `emptyNamedDockLayers` accumulation is byte-identical; only an independent boolean was added) |
| Memory: `physicalFootprintMB` | **12.61 MB** (original 0.8.4 build: 12.74 MB) — no measurable increase, under the 13 MB ceiling |
| Accessibility grant survives rebuilds | ✅ with the `MCSC-Dev` identity (`scripts/create-signing-identity.sh`) |

One implementation detail worth recording: the bar window must be matched on
**owner + layer, never on `kCGWindowName`**. Window names are redacted to `""`
for processes without Screen Recording permission, which is MCSC's case — a
name-based match silently never fires.

---

## 12. The desync, measured live (2026-11-13)

This section supersedes the inference in §3.1. Everything in it was measured
on the affected machine while the fault was present.

> **Read §13 first.** The A/B in §13.2, run the same day with MCSC stopped,
> could not reproduce a single 113 pt reservation in 13 h 22 min — including
> 1,075 Dock `autoHideOn` writes and 38 `Asynchronously setting dock info`
> pushes. That makes §12.2's "the WindowManager is stale and only a preference
> re-apply re-syncs it" **unproven as an intrinsic macOS behaviour**: every
> observation of the reservation in this doc was made from **inside MCSC's
> process**, and §12.1 does not record which process produced the measurement.
> See §13.3 for the claim-by-claim review.

### 12.1 The symptom is a *layout* fault, not a visible-bar fault

The report was: *"I can't make any app full edge to edge — maximise — because
the Dock area's space is being taken up. If I unhide the Dock and hide it
again, then maximise, it works."*

`NSScreen.visibleFrame` is the rectangle an app is allowed to occupy. It
excludes the menu bar, and — when the Dock is pinned — the Dock's strip.
Measuring it while the fault was present:

```
screen[0] frame        = (0, 0, 1470, 956)
screen[0] visibleFrame = (0, 113, 1470, 809)     <- 113 pt missing from the bottom
```

| State | `com.apple.dock autohide` | Dock bar composited | Bottom reserved |
|---|---|---|---|
| **Faulty (as reported)** | `1` | **NO** | **113 pt** |
| Dock pinned | `0` | YES | 113 pt |
| **After re-applying the pref** | `1` | NO | **0 pt** |

**The Dock bar was hidden and the screen layout still believed it was shown.**
That is the desync, and it is the *inverse* of what §1 assumed: the Dock's own
state (hidden) is correct, the WindowManager's copy (shown) is stale.

### 12.2 The mechanism

The Dock writes `com.apple.dock autohide` on **every** reveal/hide cycle — the
animation writes the pref to match its own state:

```
01:24:07.702  dock-bar-additions  Completed updating system control value; setting autoHideOn=0
01:24:08.568  dock-bar-additions  Completed updating system control value; setting autoHideOn=1
```

But the WindowManager is only told about the Dock's state by a *separate*
push, and that push only happens on a real preference re-apply:

```
01:28:20.892  event-handling              Starting autohide
01:28:20.910  com.apple.windowmanager:xpc  Asynchronously setting dock info   <- the re-sync
01:28:21.140  dock-bar-additions          Hiding all windows
```

Counting the two over the three hours before the fault:

| Event | Count |
|---|---|
| `autoHideOn=0` / `=1` writes (Dock animation cycles) | **30+** |
| `Asynchronously setting dock info` pushes (real pref re-apply) | **4** |

So the Dock rewrites the pref constantly, but the WindowManager is only
re-synced when the pref is re-applied *through the preference path*. Every
other route leaves the WindowManager's copy of "is the Dock shown?" stale —
which is exactly the divergence §3.1 hypothesised, now confirmed.

**The remedy is therefore the one the user already found:** re-apply the
preference, which pushes the dock info and re-syncs both sides. ⌥⌘D twice
(toggle auto-hide off and on) does it, and the reservation drops 113 pt → 0 pt
in about a second.

Note that on macOS 27 the `autohide` key is driven by a *system control*, not
by the preference daemon: `defaults write com.apple.dock autohide` updates the
stored value but the Dock does **not** react (no log line, no visible change).
The pref write only matters when the Dock itself decides to write it.

### 12.3 What this breaks in MCSC — and the fix

Eleven call sites sized windows to `NSScreen.visibleFrame`:

```swift
// MCSC/Models/Actions/WindowActions/SizeActions.swift:16 (and 10 more)
let axScreenBounds = ScreenGeometry.axVisibleBounds(for: screen)
```

With the Dock set to auto-hide the Dock *overlays* the screen and reserves
nothing — so `visibleFrame` is the wrong rectangle. And in the faulty state it
is not merely suboptimal, it is **wrong by exactly the stale reservation**:

```
axVisible     = (0, 34, 1470, 809)   <- 113 pt short of the bottom edge
axFill(auto)  = (0, 34, 1470, 922)   <- full height, Dock ignored
```

**Fix (shipped):** `ScreenGeometry.axFillBounds(for:dockAutoHides:)` — when the
Dock auto-hides, the fill area is the full screen minus the menu bar and the
Dock's strip is ignored; when the Dock is pinned, `visibleFrame` is kept because
the reservation is real. All eleven call sites now pass
`service.isDockAutoHideEnabled`.

The consequence: **"Fill Screen" / maximise now works edge to edge even while
the Dock is in the faulty state**, without touching any system preference.

### 12.4 Detection (shipped)

`DockLatchMonitor` now covers both directions of the desync:

| Mode | Condition | Reported as |
|---|---|---|
| `bar-stuck-visible` | the bar is composited while `autohide == 1`, and the pointer is outside the Dock's interaction zone | `[bar-stuck-visible]` |
| `space-stuck-reserved` | the bar is hidden but the layout still reserves the Dock's strip while `autohide == 1` | `[space-stuck-reserved]` |

Both are reported as a single `.notice` line naming the mode, the size of the
reservation, and the remedy:

```
Dock auto-hide latch detected [space-stuck-reserved] — the Dock is set to
auto-hide but 113pt of the Dock's strip is still reserved (held 2.0s, last
synthetic pointer action: none never at (0,0)). Remedy: toggle the Dock's
auto-hide (⌥⌘D twice) to re-apply the preference.
```

The reservation is measured with `ScreenGeometry.dockReservation(for:)`, which
compares the screen's bounds against its visible frame on the edges the menu
bar does not occupy.

### 12.5 Still not proven

* **What triggers the desync.** The Dock was idle from 01:15 to 01:24:07, and
  the fault was already present. The only activity at 01:24:07 was
  `com.apple.WindowManager` (PID 634) processing **system gesture payloads**
  through `com.apple.SkyLight:SystemGestures`, immediately before the Dock's
  reveal/hide oscillation. That is a strong lead — a system gesture (Mission
  Control / Space) is a WindowManager operation that touches the dock
  composition without going through the preference path — but it is not
  proven, and 10 rapid reveal/hide cycles did **not** reproduce the fault.
* **That MCSC had no part in it.** §5 B is still open, and the monitor now
  records every synthetic pointer action so it can be settled by correlation
  rather than by inference. **→ Overturned the same day: MCSC running is now
  the discriminating variable — see §13.1.**

### 12.6 Off-side instrument (2026-11-13 05:07 IST)

The A/B test ("does the latch occur with MCSC dead?") now has a detector on the
MCSC-off side, so it no longer depends on the user noticing the bar:

* `latch_sampler.swift` (scratch copy in the session tmp dir) runs as a plain
  `swift` interpreter process with **MCSC not running**. Every 3 s it samples
  the main screen's bottom reservation (`visibleFrame.minY − frame.minY`),
  `com.apple.dock autohide`, and the pointer Y.
* Log: `~/Library/Logs/MCSC/latch_sampler_off.log`.
  * `LATCH-CANDIDATE b=<n> ...` — reservation > 0 pt **and** pointer above
    140 pt (excludes a legit pointer-reveal), i.e. the `space-stuck-reserved`
    signature, caught within 3 s.
  * `state b=… ah=… mouse=…` — logged on every state change; `beat` every 5 min
    so gaps are detectable.
* Baseline at launch: `b=0 ah=1` (healthy), MCSC down since 02:52:45.
* Sample so far, all with MCSC dead: 2 h 14 min, **206** Mission Control opens
  (410 mode transitions), 397 Dock autohide writes, **zero** observed latches.
  All `setting dock info` re-syncs in the window (03:48×2, 04:08, 04:12,
  04:40, 04:45, 04:53×2) are manual ⌥⌘D toggles (`Disabling; setting
  autoHideOn=0` → `Starting autohide` pairs), i.e. cures the user applied while
  testing, not spontaneous recoveries.
* Note: 04:54:02–04:54:08 shows `autoHideOn` flapping 0→1 three times in ~6 s
  via `dock-bar-additions` "system control value" writes — unclassified; if a
  latch onset ever lands next to such flapping, that is the writer-fight lead.
* Readout rule: a `LATCH-CANDIDATE` line with `pgrep MCSC` empty proves the
  OS can latch without the app; a full day of `beat`/`state` lines with no
  candidate while usage matches (~90 MC opens/h) makes MCSC the prime suspect
  and hypothesis §5 B the next thing to instrument on the app side.

---

## 13. Re-investigation: the app-down A/B (2026-11-13)

**Why this section exists.** The 0.8.5 build carrying `DockLatchMonitor` and
`SyntheticPointerAudit` was deployed to this machine, then MCSC was stopped at
**02:52:45** and left down. The user reports the Dock fault has **not happened
once since**. That is a direct test of §12's verdict, and it fails: with the app
down the fault produces 0 occurrences under *more* Dock activity than the
app-up window it is compared against. This section records the measurement,
then reviews §1–§12 claim by claim against the deployed code.

### 13.1 The two windows

Same machine, same OS build, same Dock process (**PID 76368 throughout, never
restarted**), same display, same user, same day — the only intended variable is
whether MCSC was running.

| | MCSC **up** | MCSC **down** |
|---|---|---|
| Window | 00:00:00 → 02:52:45 (2 h 53 min) | 02:52:45 → 16:15 (13 h 22 min) |
| MCSC process | PID 55596 → 69962 (several dev rebuilds) | none (`pgrep MCSC` empty) |
| `com.apple.dock autohide` | 1 | 1 |
| Dock `autoHideOn` writes | 502 | **1,075** |
| Mission Control mode transitions | 514 | **1,108** |
| `Asynchronously setting dock info` | *(not counted)* | 38 |
| Dock autohide preference re-applies | *(not counted)* | 12 |
| `Not in windows mode; did NOT hide` | 2 | 2 |
| Latch reports (`DockLatchMonitor`) | **14** | 0 (app not running) |
| Off-side `LATCH-CANDIDATE` lines | n/a | **0** |

Note the direction of the confound: the app-down window is not a quiet window.
It contains **twice** the Mission Control transitions and **twice** the Dock
autohide writes of the app-up window, plus 38 dock-info pushes — the operation
§12.2 says is what re-syncs the WindowManager. None of it produced a single
reservation.

### 13.2 The off-side detector never fired

`~/Library/Logs/MCSC/latch_sampler_off.log` is a plain `swift` interpreter
process (§12.6), independent of MCSC, sampling every 3 s:

```
2026-11-13 05:07:32.192 sampler start pid=7706
2026-11-13 05:07:32.194 state b=0 ah=1 mouse=605
...
2026-11-13 16:15:23.263 state b=0 ah=1 mouse=153
```

* 1,569 samples over 11 h 08 min, **every single one `b=0`** (no bottom
  reservation), `ah=1` throughout.
* 76 `beat` lines, so no silent gaps.
* **0 `LATCH-CANDIDATE`** lines.

A fresh process reading the same geometry at 16:27 returns the healthy
baseline:

```
screen[0] frame        = (0.0, 0.0, 1470.0, 956.0)
screen[0] visibleFrame = (0.0, 0.0, 1470.0, 922.0)   bottomReserved=0  topReserved=34
```

The Dock was also toggled repeatedly *while the app was down* — 16:24:55,
16:25:07 and 16:25:29 all log `event-handling Starting autohide` without a
preceding `Disabling`, and the bar threads double-fire
(`Showing all windows` twice in the same millisecond, `autoHideOn` 0→1→1→0 in
under a second). `b` stayed `0` through all of it. So the Dock's own internal
double-firing (the "writer fight" of §12.6) is **common without MCSC and does
not by itself reserve space**.

### 13.3 Claim-by-claim review of this document

| Claim | Where | Status after re-investigation |
|---|---|---|
| MCSC has no code path that writes Dock state | §4, §7.4 | **Stands.** Re-checked: no `defaults write com.apple.dock`, no `killall Dock`, no `CoreDockSendNotification`, no `presentationOptions`, no `NSApp.hide` in `MCSC/`. |
| Hypothesis A (swallowed Dock mouse-up) is dead | §5 A | **Stands.** `DockInteractionSuppressor.swift:147-158` still passes every physical release through, and the suppressor is off by default (`isEnabledProvider?() ?? false`). |
| Hypothesis B (warp into the reveal band) is the only surviving app-side mechanism | §5 B, §7.3 | **Wrong scope.** B is one of at least four app-side mechanisms (§13.4), and it is **not supported by any recorded episode**: the 02:29:53 bar-stuck report names `postSyntheticMouseMoved` **100.92 s** earlier (far too old to raise the bar), and the 01:34/01:37/01:38 reports say `none never`. B is unproven, not "the" candidate. |
| The `Not in windows mode; did NOT hide` race is "the only sequence in the log that leaves the bar up with no pending hide" | §3.2 | **Refuted as a latch mechanism.** It fired **2× in 11 h with MCSC dead** (13:22:07.688, 13:39:22.823) and 2× in 2 h 53 min with it alive, and produced **0** reservations in the dead window. The race is routine and usually benign; something else turns it into a persistent fault. |
| "Two `did NOT hide` events in three days" | §3.2, §10 | **Correct for the capture window, misleading as a rate.** It is ~2 per 11 h, not 2 per 3 days. |
| The latch occurs with MCSC absent (6 of 23) | §2.4 | **Not re-verifiable.** The 2026-11-11 window has rolled out of the unified log store — `log show` for that day now returns nothing. The 23-event table cannot be re-derived today, so it should not be quoted as if it were. |
| Detector verified with no false positive on a parked pointer | §11.3 | **Contradicted by the log.** An earlier iteration of the same 0.8.5 monitor reported three latches at 22:38:36–22:40:17 with `held 0.4s` and `pointer 2pt above the bottom edge` — the pointer was sitting *on* the hot edge, i.e. exactly the false positive the 160 pt zone was later added to prevent. The shipped zone is sound; the verification claim as written was not. |
| `SyntheticPointerAudit` records "the most recent synthetic pointer action MCSC performed" | §11.2 | **Incomplete.** It wraps two sites (warps + one posted `mouseMoved`). MCSC posts **synthetic left mouse down/up** at two more (`WindowActivationAction.swift:44-62`, `DesktopNavigationActions.swift:162`) and those are not recorded, so `last synthetic pointer action: none` does **not** exclude MCSC having clicked into the Dock's band (§13.4 E). |
| The 113 pt reservation is the WindowManager holding a stale copy | §12.1, §12.2 | **Unproven, and the most consequential gap in the doc.** §12.1 does not record *which process* produced the measurement. Every observation of the reservation in this document was emitted by MCSC itself; no independent process has ever observed it, in 1,569 samples across 11 h. Either the desync is real and MCSC is what brings it about (§13.4 C/E), or the reservation was only ever true *inside MCSC's process* (§13.4 D). The doc as written picks the first reading without evidence that distinguishes them. |
| Re-applying the preference is what re-syncs the WindowManager | §12.2 | **Not demonstrated.** 38 dock-info pushes happened in the dead window with no reservation before or after. The push is real; that it is *the* repair is inference from a correlation observed only while the app was running. |
| MCSC had no part in it | §12.5, header | **Overturned by §13.1.** Same-day, same-Dock comparison: 14 reports while running, 0 while stopped, against a dead window with twice the Dock/MC activity. MCSC is causal or strongly permissive; which of the mechanisms in §13.4 is open. |
| Do not add a Dock watchdog | §7.4 | **Stands.** Nothing here argues for the app writing Dock state. |
| Fill Screen fix (`axFillBounds`) | §12.3 | **Stands as a fix, needs its justification restated.** Ignoring the Dock strip while `autohide == 1` is right regardless of which process's `visibleFrame` is stale. See §13.4 D for the alternative, app-local explanation that the doc currently omits. |

### 13.4 App-side mechanisms that survive code review

Ranked by how much of the evidence each explains. All five require MCSC to be
running, which is now the discriminating condition rather than a coincidence.

**C. The head-insert mouse tap sits in front of the Dock's pointer stream.**
`MissionControlHoverService+InputTap.swift` creates the tap at
`.cghidEventTap`, `.headInsertEventTap`, `.defaultTap`, adds its run-loop
source to **the main run loop**, and for `.leftMouseDown` enters
`DispatchQueue.main.sync` while `mouseMoved` is dispatched `async` to main. The
main thread also runs the 0.2 s Mission Control poll, which performs a
`CGWindowListCopyWindowInfo` IPC and AX queries, plus overlay updates. Every
pointer event the Dock would use to decide "the pointer left me, hide" is
therefore held behind MCSC's main-thread work. If a stall exceeds the tap's
timeout the system disables the tap, and both taps re-enable it **silently** —
`tapDisabledByTimeout` is handled with no `AppLogger` line anywhere — so the
stall window leaves no trace. This is the most plausible way MCSC turns a rare
OS race into a frequent latch (`bar-stuck-visible`) without touching Dock state.
*Falsifiable:* log `tapDisabledByTimeout` with a timestamp; a latch within a few
hundred ms of one confirms C.

**D. `visibleFrame`, as seen by a long-lived accessory process.**
`AccessibilityService.swift:162-166` reads the Dock preference through
`UserDefaults(suiteName: "com.apple.dock")` without `CFPreferencesAppSynchronize`
or a preference observer, and both `ScreenGeometry.axFillBounds`
(`ScreenGeometry.swift:51-72`) and `DockLatchMonitor.detectSpaceStuckReserved`
derive from `NSScreen.visibleFrame`. MCSC runs as `.accessory`
(`AppDelegate.swift:29`), never activates, and its only screen-geometry refresh
hook is `NSApplication.didChangeScreenParametersNotification`
(`AccessibilityService` init), which clears `cachedDockFrame` — nothing forces
`visibleFrame` itself to be re-read from the window server. If a Dock show/hide
does not deliver that notification to a non-activating process, the stale
113 pt reservation persists for the life of the process: Fill Screen keeps a
dead band, `space-stuck-reserved` keeps reporting, toggling the preference
(a real screen-parameter change) clears it, and a fresh process never sees it.
That is *every* observation in this document, including the app-down A/B.
*Falsifiable:* at the next occurrence, read the reservation from a **new**
process while MCSC reports 113 pt. New process 0 / MCSC 113 → D is the answer
and §12's system-wide desync is wrong (though `axFillBounds` is still the right
fix). New process 113 → D is dead and the system really is reserving.

**E. Synthetic clicks posted into the Dock's band (unaudited).**
`WindowActivationAction.swift:44-62` posts a left down/up at the Mission
Control tile point, and `DesktopNavigationActions.swift:162` posts a left mouse
down during the space-switch sequence. A synthetic press delivered into the
Dock's window can put the Dock in its "button held inside me" state, which is
exactly the state that pins the bar; and because `SyntheticPointerAudit` does
not record these, the monitor's report line cannot see them. Note the
suppressor only ever swallows a *synthetic, zero-pressure* up
(`DockInteractionSuppressor.swift:156-158`) — and it is off by default, so a
synthetic down/up pair over the Dock reaches the Dock intact.
*Falsifiable:* wrap both posters with `SyntheticPointerAudit.note(kind:)` and
re-run; then the report line either names a click at a bottom-band point or it
does not.

**B. Synthetic warp + posted `mouseMoved` (§5 B).** Retained, but with no
supporting occurrence: 02:29:53 names a move 100.92 s old, everything else says
`none never`. Note `CGWarpMouseCursorPosition` does not produce a real HID
move, so a warp into the bottom band reveals the Dock with no matching leave —
the mechanism is sound, the evidence for it is absent.

**Mission Control churn (not a separate mechanism).** §3.2's weak MC
correlation is further weakened here: the dead window had 1,108 MC transitions
and no fault, the live window 514 and fourteen. MC churn is not the variable;
MCSC's presence is.

### 13.5 The one measurement that decides it

At the next occurrence, with the bar/reservation present, before touching
anything:

```bash
# A. What MCSC's own process believes
grep "latch detected" ~/Library/Logs/MCSC/diagnostic_report.jsonl | tail -3

# B. What a FRESH process believes (this is the discriminator)
/usr/bin/swift -e 'import Cocoa
for (i,s) in NSScreen.screens.enumerated() { print(i, s.frame, s.visibleFrame) }'

# C. Did MCSC's tap stall?  (requires the §13.4 C instrumentation; absent today)
/usr/bin/log show --predicate 'subsystem == "sj010.MCSC"' --last 2m --info --debug --style compact | grep -i "tap.*disabled"

# D. Is the Dock bar actually composited?
/usr/bin/log show --predicate 'process == "WindowServer"' --last 2m --style compact | grep -i dock | tail -20
```

| A | B | Conclusion |
|---|---|---|
| 113 pt | 0 pt | **D** — process-local stale layout; §12's desync story is wrong |
| 113 pt | 113 pt | system-wide — then C or E decides who caused it |
| 0 pt | 0 pt | the fault is gone; the report was stale, re-check §13.1's numbers |

### 13.6 What this A/B does not prove

* The app-up window was a **development session** (six different MCSC PIDs from
  rebuilds), not normal use, so its 14 reports may overstate the steady-state
  rate.
* Dock/MC activity was **2× denser** in the dead window, which strengthens the
  conclusion, but the *pattern* of that activity was not identical — the live
  window includes MCSC's synthetic activation sequences.
* Between 02:52:45 and the sampler's launch at 05:07:32 there is **no
  measurement**. The reservation could have persisted for part of that gap and
  cleared by a toggle (`Disabling` at 04:53:24) before the first sample.
* The user was actively toggling the Dock during the dead window (12
  preference re-applies). That is an attempt to reproduce that failed, but it
  also means the dead window was not a plain passive observation.
* **Nothing here identifies the trigger.** It establishes correlation with
  MCSC running, and it moves D and C ahead of §12's WindowManager desync
  explanation. Establishing causality still requires the §13.5 measurement at
  the moment of the fault, plus the two instrumentation gaps in §13.3 (tap
  timeout logging, audit coverage of synthetic clicks).

---

## 14. Root Cause — hypothesis-grade evidence; former auto-heal (2026-11-14)

> **Posture update (2026-11-15, ADR 0002).** The monitor and the auto-heal described in
> this section and §15 were **removed** from the app: in a 36 h instrumented run the
> monitor reported 23 latches and **zero were real** (§16). Prevention (§15) stays.
> The mechanism below remains the best-supported explanation of the desync, but the
> "confirmed" framing was too strong: the mechanism is consistent with all logs and
> was never isolated as the sole cause.

### 14.1 The 01:56:08 Incident Capture

On 2026-11-14 at 01:56:10 and 01:57:11, `DockLatchMonitor` reported two `space-stuck-reserved`
episodes while MCSC was running. Correlating `WindowManager`, `Dock`, and `MCSC` logs reveals
the exact sequence:

```
01:56:01.344  Dock            Changing mode: .none -> missionControl
01:56:07.381  WindowManager   Asynchronously setting dock info (113pt reserved for MC)
01:56:08.124  Dock            Changing mode: .showAllWindows to off
01:56:08.562  WindowManager   'ExitMissionControl-Discrete' activity did complete
01:56:08.715  Dock            dock-bar-additions Hiding all windows
--- OS DEFECT: WindowManager never pushed clear dock info after exit ---
01:56:10.986  MCSC            Dock auto-hide latch [space-stuck-reserved]: 113pt strip still reserved (held 2.2s)
01:57:11.267  MCSC            Dock auto-hide latch [space-stuck-reserved]: 113pt strip still reserved (held 9.1s)
01:57:54.728  Dock            Tile insert -> Asynchronously setting dock info (cleared reservation)
```

### 14.2 The Mechanism Identified

1. While Mission Control is active, `WindowManager` pushes `Asynchronously setting dock info`
   to reserve the 113 pt bottom strip.
2. When Mission Control exits, `ExitMissionControl-Discrete` completes and the Dock bar hides,
   but macOS 27 `WindowManager` **omits the matching post-exit dock info push**.
3. The 113 pt reservation remains stuck in the compositor's layout and `NSScreen.visibleFrame`.
4. Previously, the only way to recover was manually toggling auto-hide (⌥⌘D twice) or an app
   launch triggering a Dock tile insert (which happened at 01:57:54).

### 14.3 The Auto-Heal Fallback — REMOVED (ADR 0002)

The osascript double-toggle auto-heal shipped briefly and was removed: it fired only on
false positives (11/11 in the instrumented run), wrote Dock preferences through System
Events despite the monitor's "never writes Dock preferences" contract, and echoed itself
(heal toggle → fresh transaction → a bar-stuck report 3 s later). The cure for a real
latch is manual ⌥⌘D twice. Historical description retained for the record:

Instead of merely logging the latch and asking the user to press ⌥⌘D, MCSC includes an automated cure:

1. **Auto-Heal via System Events (`osascript`):**
   When `DockLatchMonitor` detects `spaceStuckReserved` held for ≥ 2.0s, it executes an asynchronous
   double-toggle via `osascript` (`autohide to false` -> delay 0.1s -> `autohide to true`). The Dock reacts
   by pushing fresh dock info to `WindowManager`. The reservation drops 113 pt → 0 pt in under 0.3 s
   without user intervention.
2. **AppKit Screen Cache Refresh (`_prepareScreensIfNeeded`):**
   Called upon Mission Control deactivation (`handleDeactivated`) and during auto-heal to
   ensure MCSC's in-process `NSScreen` cache never holds a stale `visibleFrame`.
3. **Zero-Footprint:**
   No polling timers, no `killall Dock`, no plist writes, no private CoreDock SPI. Uses native
   AppleScript System Events IPC within the 13 MB memory ceiling.

---

## 15. Root-Cause Prevention: Eliminating IPC Contention at Source (2026-11-14)

### 15.1 Why Double-Toggle Was Not Enough

The auto-heal double-toggle is a reactive cure after WindowManager drops the dock-info clear push.
The app-down A/B test (§13.1) demonstrated that the latch **never occurred in 13+ hours across 1,108
Mission Control transitions** while MCSC was stopped. MCSC's runtime behavior was actively inducing
the WindowManager race.

Two architectural culprits were identified:
1. **Always-On Head-Insert Mouse Tap:**
   `MissionControlHoverService` installed `.headInsertEventTap` on `start()`, intercepting all mouse moves,
   drags, clicks, and flags changes 24/7 on the main runloop, even when Mission Control was completely closed.
   On every mouse move, it evaluated `isMissionControlActiveProvider()` at up to 30 Hz.
2. **WindowServer IPC Contention on Exit:**
   When exiting Mission Control (e.g. clicking a thumbnail), MCSC intercepted the mouse down synchronously
   at the head of the HID queue, delaying event delivery to WindowServer/Dock and firing `CGWindowListCopyWindowInfo`
   on the exact runloop turn where `WindowManager` was executing `ExitMissionControl-Discrete`.
   This IPC collision caused WindowManager to drop the asynchronous 0 pt dock-info push.

### 15.2 Preventive Architecture Implemented

1. **Dynamic Input Tap Lifecycle:**
   - Removed `startInputTap()` from `MissionControlHoverService.start()`.
   - The global mouse input tap is created and attached to the runloop **only** upon entering Mission Control
     (`handleActivated()`).
   - The tap is stopped and invalidated (`stopInputTap()`) immediately upon Mission Control deactivation
     (`handleDeactivated()`).
   - Outside Mission Control, MCSC has **zero mouse event taps, zero HID interception, and zero runloop overhead**.
2. **Exit Scan Backoff Window:**
   - In `MissionControlService.markActive(false)`, an `exitBackoffUntil = now + 0.50` quiet window is set.
   - For 500 ms after Mission Control exits, all WindowServer window list scans (`CGWindowListCopyWindowInfo`)
     are suppressed and return `false` instantly.
   - WindowManager and Dock have an uncontended runloop to complete `ExitMissionControl-Discrete` and cleanly
     push `Asynchronously setting dock info (0pt)`.
3. **Dormant Auto-Heal Safety Net — REMOVED (ADR 0002):**
   - `DockLatchMonitor` and its auto-heal were removed after the instrumented run
     showed 23 reports and zero real latches (§16). The preventive mechanisms in
     items 1–2 remain.



---

## 16. The 60 h instrumented A/B — zero real latches, 23 false reports (2026-11-15)

`DockLatchMonitor`, `SyntheticPointerAudit`, the osascript auto-heal and a standalone
sampler process ran as instrumentation for ~60 h: MCSC off ~23 h (Nov 13 02:52 →
Nov 14 02:31 IST), MCSC on ~36 h (Nov 14 02:31 → Nov 15 14:54 IST). Usage was Mission
Control-heavy throughout (~28–94 opens/hour; 1019 opens in the on-window alone).

| | MCSC off | MCSC on |
|---|---|---|
| Real latches (independent observation + user report) | **0** | **0** |
| Monitor reports | n/a | **23** (11 space-stuck-reserved, 12 bar-stuck-visible) |
| Auto-heal runs (osascript Dock-pref writes) | n/a | **11** |
| User ⌥⌘D toggles | ~1 | ~16 |

All 23 reports were decomposed; none was a real latch:

* **space-stuck-reserved (11/11):** the monitor read `NSScreen.visibleFrame` as
  reserving 113 pt; a sampler process reading the same property read `0` within ±1 s of
  every report. `visibleFrame` in a background app lags the compositor by seconds after
  every Dock show/hide transaction. Every report sat seconds after a legitimate
  reveal/toggle transaction. (The app's own Nov 13 log line had already flagged this:
  "independent sampler confirms b=0: Hypothesis D process-local cache".)
* **bar-stuck-visible (12/12):** the bar genuinely was on screen (CGWindowList is a
  fresh read), but legitimately — 11 fired 2–7 s after an autohide toggle while the
  pref was actually `0` (Dock pinned on purpose) and the monitor's `CFPreferences`
  autohide read was stale (the sampler's identical read was stale too); the twelfth
  fired while Mission Control was open (Dock log `Changing from mode .none to
  missionControl` at 22:15:52, report 22:15:57) and the monitor's cached MC state lagged.
* **The heal fired only on false positives** and echoed itself: each heal's off/on
  toggle created the next transaction, producing a bar-stuck report ~3 s later
  (14:18:41 space-stuck → heal → 14:18:44 bar-stuck, Nov 15).

Instrument caveats, recorded so future readers don't over-trust either side: the
sampler also once read a stale `b=0` while the Dock was genuinely pinned (14:31:12,
Nov 15) and its `CFPreferences` autohide read lagged the same way; App-Nap produced
sampling gaps up to ~17 min during idle periods. **`NSScreen.visibleFrame` and
`CFPreferences` reads in background processes are not ground truth for sub-10 s Dock
transitions on macOS 27; CGWindowList (fresh per scan) and the Dock's own log are.**

Conclusion: the posture in ADR 0002 — no resident monitor, no auto-heal, prevention
only, manual ⌥⌘D cure. The cleanup execution record is `docs/PROD_CLEANUP_PLAN.md`.
