# Production Cleanup Plan — Dock Latch Investigation Aftermath

- Date: 2026-11-15
- Status: **Executed** — branch `fix/dock-autohide-latch-cleanup`, PR to `main`
- Scope: everything the 2026-11-12 → 11-15 latch investigation added to the tree
- Decisions: ADR 0002 (no monitor, no auto-heal, prevention stays), ADR 0003 (fill bounds)
- Related: `docs/DOCK_AUTOHIDE.md`, `CHANGELOG.md` (Unreleased), AGENTS.md memory mandate

## What stays (the solution, pinpointed)

| # | Change | Where | Why it stays |
|---|--------|-------|--------------|
| 1 | `axFillBounds(for:dockAutoHides:)` + 11 call sites | `ScreenGeometry.swift`, `SizeActions.swift`, `AppActions.swift` | User-facing fix: fill/snap no longer inherits the stale 113 pt strip (ADR 0003) |
| 2 | Dynamic input-tap lifecycle | `MissionControlHoverService.swift`, `+InputTap.swift` | Zero HID interception outside Mission Control; root-cause *prevention* (ADR 0002 §Decision 3) |
| 3 | 500 ms exit-scan backoff | `MissionControlService.markActive` + `checkMissionControlActive` | Gives WindowManager an uncontended runloop turn for `ExitMissionControl-Discrete` |
| 4 | `clampAwayFromDockHotEdge` on synthetic warps | `WindowActivationAction`, `DesktopNavigationActions` | Synthetic pointer can't trip the Dock hot-edge reveal |
| 5 | `_prepareScreensIfNeeded` refresh after MC exit | `MissionControlHoverService+Observers.swift` (keep), `DockLatchMonitor.swift` (dies with file) | Best-effort staleness mitigation for the geometry path (ADR 0003) |

## What goes (investigation baggage)

### Phase 1 — delete dead code

| Item | Touchpoints |
|------|-------------|
| `MCSC/Services/Dock/DockLatchMonitor.swift` | delete file (untracked) |
| `MCSC/Models/SyntheticPointerAudit.swift` | delete file (untracked) |
| `dockLatchMonitor` wiring | `ShortcutViewModel.swift` — lazy var (~line 81), `.start()` (line 368), `.stop()` (line 390) and their doc comments |
| `SyntheticPointerAudit.note` calls (6) | `WindowActivationAction.swift` lines 18, 49, 60; `DesktopNavigationActions.swift` lines 49, 145, 155 — **keep the `clampAwayFromDockHotEdge` lines around them** |
| Scan plumbing for the monitor | `MissionControlService.swift` — `onWindowListScanned` (protocol + property + publish at line ~363), `isMissionControlActiveCached`, `isDockBarOnScreen` accumulation and the `layer >= dockBarLayerThreshold` branch that feeds it. Keep `emptyNamedDockLayers` and the WindowManager-overlay heuristic untouched. |
| Probe scripts | `scripts/latch_sampler.swift` (untracked, delete); kill the running sampler (`pgrep -f latch_sampler`, pid 10675) and the scratch copy in the session tmp dir |

Net effect: −2 files, −1 protocol member, −6 audit calls; no behavior change outside logging.

### Phase 2 — log hygiene (AGENTS.md: unified logging, background only)

- With the monitor gone, its `.notice` latch lines and the synthetic-pointer audit lines
  disappear automatically.
- `MissionControlService.markActive`: collapse the two `info` lines
  ("backoff WindowServer scans…", "Mission Control active state changed…") into one
  line that carries `active` + `backoffUntil`. No per-scan logging anywhere.
- Audit remaining `AppLogger.dock` call sites: keep Dock lifecycle notices
  (observer reconnect), drop `debug`-level chatter added during the hunt
  (e.g. `AccessibilityService` hit-test misses) unless a category rule already requires it.

### Phase 3 — make the claims match the evidence

1. **`CHANGELOG.md` Unreleased rewrite:**
   - Keep: fill-bounds entry (ADR 0003), dynamic-tap lifecycle entry, exit-backoff entry.
   - Drop: "Resolved the root-cause IPC contention" framing → strongest supported claim is
     "avoids WindowServer IPC contention during Mission Control exit" (root cause is a
     hypothesis, consistent with logs, not proven — ADR 0002).
   - Drop: auto-heal entry, `DockLatchMonitor` entry, `SyntheticPointerAudit` entry,
     "Dock Window Matching by Owner and Layer" entry (that scan branch only fed the
     removed monitor).
2. **`docs/DOCK_AUTOHIDE.md`:**
   - Mark §14 root cause as hypothesis-grade (consistent, not proven) and point to ADR 0002.
   - Replace §14.3 / §15.3 auto-heal sections with "removed, see ADR 0002".
   - Add §16: the 60 h instrumented A/B (0 real latches both states; 23 reports, all
     decomposed; `NSScreen.visibleFrame`/`CFPreferences` staleness measured in background
     processes; heal self-echo). Keep §12.6 as the off-side instrument record.
   - Fix any remaining "never writes Dock preferences" statements to past tense.

### Phase 4 — new documentation

- ADR 0002 and ADR 0003 (written alongside this plan).
- `docs/adr/0001` heading convention matched (`# ADR NNNN — Title`, Status/Date/Supersedes).

### Phase 5 — verification (PR checklist from AGENTS.md)

1. `xcodebuild` build clean, no new warnings from the removal.
2. Memory gate: cold RSS ≤ 13 MB; re-check after 1 h and after an MC churn session.
   Current 36 h-uptime reading is **54 MB** — before shipping, explain the delta
   (suspects: window-list scan allocations, overlay panels, gesture services) and
   fix or file. The removals here also reduce surface; measure, don't assume.
3. Functional:
   - Fill Screen reaches the bottom edge with autohide on — immediately after MC exit
     (staleness window) and in steady state.
   - With the Dock pinned, fill still excludes the strip.
   - Mission Control detection survives the 500 ms backoff: open → close → reopen
     within 1 s detects the second open once the backoff lapses; no stuck overlay state.
   - Input tap exists only while MC is open (verify via `log stream` or Instruments
     around `handleActivated` / `handleDeactivated`).
   - Gestures, shortcuts, desktop-move unaffected (the audit `.note` removal must not
     touch the `CGWarpMouseCursorPosition`/`postMouse` behavior — clamps stay).
4. Zero retain cycles: monitor removal takes its `[weak self]` closure with it;
   confirm `onWindowListScanned` had no other subscribers.

### Phase 6 — commit order (each commit builds)

1. `fix(geometry): fill/snap bounds ignore auto-hiding Dock strip` — ScreenGeometry +
   11 call sites + screen-cache refresh.
2. `fix(mission-control): create input tap only while Mission Control is open; back off
   window-list scans for 500 ms after exit` — HoverService + MissionControlService
   (prevention bits only).
3. `refactor(dock): remove latch monitor, pointer audit and auto-heal (ADR 0002)` — the
   Phase 1 deletions + log hygiene.
4. `docs: ADR 0002/0003, DOCK_AUTOHIDE §16 findings, CHANGELOG rewrite`.

Version bump + release notes only after the memory gate passes.
