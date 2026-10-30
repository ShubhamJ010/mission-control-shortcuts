# Targeting Scopes & Scope Hierarchy

This document defines the architectural rules governing action targeting across MCSC: whether an operation acts on an entire application (all windows) or a singular window/tab.

---

## The Core Targeting Principle

MCSC maps cursor position and context into two primary scopes:

| Target Context | Scope Level | Target Meaning | Window Operation Semantics |
| :--- | :--- | :--- | :--- |
| **Dock Icon** (inside or outside Mission Control) | **App Level** | Represents the entire application and all of its open windows. | Operations like **Close Window** act on **all windows** of that app (`CloseScope.wholeApp`). Tab operations act on the key window's active tab. |
| **Window Preview** (Mission Control thumbnail) | **Singular Level** | Represents a single specific window instance. | Operations like **Close Window** act strictly on **that one window** (`CloseScope.window`). Tab operations act on its active tab. |
| **Title Bar / Window Body** (Desktop / normal state) | **Singular Level** | Represents a single specific window under the cursor. | Operations act strictly on **that one window** (`CloseScope.window`) or its active tab (`CloseScope.activeTab`). |
| **Floating Component** (PiP video, always-on-top panel) | **None** | Not a target. These windows are borderless, so the title-bar strip is content. | No action. Classified by `WindowComponentClassifier` from `kCGWindowLayer >= 3`; see [ADR 0001](adr/0001-window-components.md). |

---

## Detailed Rules by Action

### 1. Close Actions
- **On Dock Icon**:
  - `Close Window` / `⌘W` -> `.wholeApp`: closes all open windows belonging to the targeted app.
  - `Close Tab` -> `.activeTab`: closes the active tab of the app's frontmost key window.
  - `Quit App` -> terminates the application process.
- **On Window Preview (Mission Control)**:
  - `Close Window` -> `.window`: clicks the red close button (`kAXCloseButtonAttribute`) of that window.
  - `Close Tab` -> `performCloseTab`: sends `⌘W` or clicks the tab close button on that specific window without clicking the window's red close button.
- **On Title Bar / Window Body**:
  - `Close Window` -> `.window`: clicks that window's red close button.
  - `Close Tab` -> `.activeTab`: closes the active tab of that window.
  - `Smart Close` (shared shortcut): closes active tab if tabbed application/tabs present; otherwise closes window.

### 2. Tab & New Window Actions
- **On Dock Icon**:
  - `New Window` / `New Tab` -> `NewWindowAppAction`: activates the application and posts `⌘N` directly to `app.processIdentifier`.
  - `Reopen Tab` -> `ReopenTabAppAction`: activates the application and posts `⌘⇧T` directly to `app.processIdentifier`.
- **On Window Preview / Title Bar**:
  - Targets the window under the cursor, activating it if necessary before posting keystrokes.
