# ADR 0002 — Dock auto-hide desync: prevent, don't detect; cure is manual

- Status: Accepted
- Date: 2026-11-15
- Supersedes: none (retires the in-tree `DockLatchMonitor` + auto-heal approach described in `docs/DOCK_AUTOHIDE.md` §11–§15)

## Context

macOS 27 has a real Dock/WindowManager desync: after Mission Control exits, WindowManager
can skip its post-exit dock-info push and the compositor keeps a ~113 pt Dock strip
reserved (or leaves the bar composited) while `com.apple.dock autohide == 1`.
`docs/DOCK_AUTOHIDE.md` §2–§3 documents latches from Nov 10–12 **with MCSC not running**,
so the defect exists independently of this app.

To chase it, two days of instrumentation were added: `DockLatchMonitor`
(passive observer riding the Mission Control window-list scan), `SyntheticPointerAudit`
(record of MCSC's synthetic pointer actions), an osascript "auto-heal" that re-applies
the autohide preference, and a standalone sampler process. The instrumented 60 h A/B
(MCSC off ~23 h, on ~36 h) produced:

| | MCSC off | MCSC on |
|---|---|---|
| Real latches (independent observation + user) | **0** | **0** |
| Monitor reports | n/a | **23** (11 space-stuck, 12 bar-stuck) |
| Auto-heal runs (osascript Dock-pref writes) | n/a | **11** |

Forensics on all 23 reports found **no real latch**:

- **space-stuck-reserved (11/11):** the monitor read `NSScreen.visibleFrame` as reserving
  113 pt; a sampler reading the same property in a second process read `0` within ±1 s of
  every report. `visibleFrame` in a background app lags the compositor by seconds after
  every Dock show/hide transaction (the app's own Nov 13 log line already named this:
  "independent sampler confirms b=0: Hypothesis D process-local cache"). Every report sat
  seconds after a legitimate reveal/toggle transaction.
- **bar-stuck-visible (12/12):** the bar genuinely was on screen (CGWindowList is a fresh
  read), but legitimately — 11 reports fired 2–7 s after an autohide toggle while the pref
  was actually `0` (Dock pinned on purpose) and the monitor's `CFPreferences` autohide read
  was stale; the twelfth fired while Mission Control was open (Dock log:
  `Changing from mode .none to missionControl`) and the monitor's cached MC state lagged.
- **The auto-heal fired only on false positives** (11/11), wrote Dock preferences through
  System Events despite the monitor's documented "never writes Dock preferences" contract,
  and echoed itself (heal toggle → fresh transaction → a bar-stuck report 3 s later,
  e.g. 14:18:41 → 14:18:44 on Nov 15).

Separately, the root-cause *prevention* work (§15: dynamic input-tap lifecycle, exit-scan
backoff) is consistent with all log evidence but is not proven to be *the* fix — the A/B
showed zero real latches in both states, so nothing was demonstrated to be prevented.

## Decision

1. **No resident latch monitor.** `DockLatchMonitor`, `SyntheticPointerAudit`, and the
   `onWindowListScanned` / `isMissionControlActiveCached` / `isDockBarOnScreen` scan
   plumbing are removed. Their diagnostic job is done; the findings live in
   `docs/DOCK_AUTOHIDE.md`.
2. **No automated cure.** The osascript auto-heal is removed together with the monitor.
   The cure for a real latch (expected to stay rare, OS-side) is the user pressing
   ⌥⌘D twice; that remedy is documented in `docs/DOCK_AUTOHIDE.md` §6.
3. **Prevention stays.** The dynamic `.headInsertEventTap` lifecycle (created only while
   Mission Control is open), the 500 ms exit-scan backoff, and the
   `clampAwayFromDockHotEdge` guard on synthetic pointer warps remain — they reduce the
   app's WindowServer IPC footprint at the exact moment the desync occurs, and each is
   also justified independently (zero-footprint mandate, AGENTS.md).
4. **The stale-reservation consequence is absorbed at the geometry layer** — see
   ADR 0003 (`ScreenGeometry.axFillBounds`), which is what actually fixes the
   user-visible dead band.

## Alternatives Considered

### Keep a corrected monitor (CGWindowList-derived reservation, transaction-quiet gate, no heal)
- Pros: would auto-detect a future real latch with evidence attached.
- Cons: 60 h of instrumentation produced **zero** real events to detect; a resident
  detector conflicts with the 13 MB zero-footprint mandate for machinery whose only
  consumer is a log line; and any future investigation can rerun the documented
  `log show` triage queries from `docs/DOCK_AUTOHIDE.md` §6 without shipping code.
- Rejected.

### Keep the auto-heal without the monitor
- Pros: invisible self-repair if the desync recurs.
- Cons: nothing left to trigger it; blind-firing Dock preference toggles on a timer or
  on Mission Control exit would be indistinguishable from the bug it cures, and it
  writes system preferences from a utility app.
- Rejected.

### Ship the monitor + heal as-is
- Pros: none measured.
- Cons: 23 false reports per 36 h (~1 bogus Dock-pref write every 1.6 h), a documented
  contract violation, self-echoing alerts, and extra code surface.
- Rejected.

## Consequences

- A real latch is cured manually (⌥⌘D twice). MCSC no longer auto-cures it.
- `NSScreen.visibleFrame` staleness is treated as a property of macOS 27 background
  apps, not a bug to work around per-callsite; code that sizes windows must not trust
  it for the Dock strip (ADR 0003).
- If the latch recurs, the triage entry point is `docs/DOCK_AUTOHIDE.md` §6
  (60-second `log show` procedure), not resident instrumentation.
- The CHANGELOG's Unreleased section is rewritten to match this evidence: "prevents
  the app from contending" is the strongest claim supported, not "resolved the
  root cause".
