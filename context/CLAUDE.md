# CLAUDE.md — comprehensive context

Read this first. It mirrors `/CLAUDE.md` at the repo root but expands
to cover **both** plasmoids and the patterns shared between them.

## What this is

Two KDE Plasma 5.27 plasmoids in one repository:

- **Categorized ToDo** (`package/`, plugin id
  `org.kde.plasma.categorizedtodo`) — a multi-source list widget with
  four operating modes selected from a hamburger in the popup footer:
  - `todo` — local task list backed by SQLite. Up to **7** categories
    plus an always-on **Global** tab.
  - `jira` — read-only view of Jira Cloud issues.
  - `gh` — read-only view of a GitHub Projects (V2) project.
  - `notion` — list + inline-edit of Notion pages via the `ntn` CLI.

- **Jira / Clockify Worklog Calendar** (`worklog-plasmoid/`, plugin id
  `org.kde.plasma.jiraworklog`) — weekly calendar of worklogs with
  three "sources" toggled from a hamburger:
  - `jira` — worklogs from Jira Cloud's REST v3.
  - `clockify` — time entries from Clockify's v1 API.
  - `jira-clockify` — split day columns: Jira on the left half (purple),
    Clockify on the right half (light green or per-project color).
    Includes a *"Jira → Clockify"* button that mirrors Jira worklogs to
    Clockify time entries with the description
    `<issueKey>: <issueSummary>`.
  - Bottom of the popup in 9h mode shows two ring gauges: **Sprint**
    (percentage of time elapsed) and **Horas** (`consumed /
    (remaining + consumed)` in the active sprint).

Both plasmoids are **pure QML**: no native code, no external runtime
libraries beyond what ships with Plasma 5.27 + Qt 5.15
(`org.kde.plasma.*`, `org.kde.kirigami`, `QtQuick.*`, `QtQuick.Controls
2`, `QtQuick.Dialogs`, `QtQuick.LocalStorage`, `Qt.labs.platform`,
`QtQuick.Shapes`).

## Target platform

- Kubuntu 24.04 (or any distro with KDE Plasma 5.27 + Qt 5.15).
- Single-user install under `~/.local/share/plasma/plasmoids/`. No
  system-wide install. No CI / no test suite / no build step beyond
  `kpackagetool5 --install`.

## Architecture: stores own state, views are dumb

`main.qml` of each plasmoid instantiates a small set of singletons
("stores") and injects them into both representations (compact and
full) via properties. Stores own all data and all I/O; views only
read from them and emit signals back.

| Plasmoid                | Stores instantiated in main.qml                                                  |
| ----------------------- | -------------------------------------------------------------------------------- |
| Categorized ToDo        | `Database`, `TaskStore`, `JiraStore`, `GhStore`, `NotionStore`                   |
| Worklog Calendar        | `JiraWorklogStore`, `ClockifyStore`                                              |

Patterns shared by **every** store:

- Plain JS arrays of plain objects as the in-memory model. No
  `ListModel`. Reassigning the array (`store.things = newArray`) is
  what triggers QML's `*Changed` signal.
- A `version: int` property that mutations bump via `_bump()`. Every
  view that displays something derived from the store reads
  `(store.version, store.someComputation())` so QML notices the
  invalidation even when the function returns the same shape of object.
- `loading`, `lastError`, `lastFetchedAt` for status feedback.
- `lastDebugLog` + `hasDebugLog` accumulating a plain-text log of
  every operation, surfaced through an ⓘ dialog in the popup. The
  log is independent of the per-store `*Debug` kcfg toggle (which
  only controls `console.log` / `console.warn` mirroring).
- For credentials, two-way mirror to SQLite (see *Persistence*
  below) so a Plasma config loss doesn't wipe them.

Mutations from views are signals that bubble up to FullRepresentation
which calls the relevant store method. Stores expose
`createX/updateX/deleteX` methods that hit the API and emit
`*Finished(ok, err)` signals; a `Connections` block in
FullRepresentation drives a single re-fetch on every successful
mutation, no matter the origin (modal save, drag-move, edge resize,
duplicate button).

## Persistence layers

Two layers, used for different things:

### `Plasmoid.configuration` (KConfig)

The schema is `package/contents/config/main.xml` in each plasmoid.
KConfig stores user-tweakable settings: mode/source, popup size,
category names + colors, JQL queries, credentials, etc. Setting a
property auto-saves; reading is instantaneous (KConfigPropertyMap).

Credentials live here too because the config dialog binds form fields
to `cfg_*` aliases.

**Important**: KConfigPropertyMap **debounces** writes (typically 5–10
seconds). For values that must survive a Plasma crash within that
window (e.g. credentials), the Categorized ToDo plasmoid **also**
mirrors them to SQLite via `JiraStore.persistCredentials()` and
restores from there on startup if the KConfig value is empty.

### SQLite via `QtQuick.LocalStorage`

`package/contents/ui/Database.qml` wraps `QtQuick.LocalStorage 2.0`,
synchronous and ACID. The DB file lives at
`~/.local/share/KDE/plasmashell/QML/OfflineStorage/Databases/<md5>.sqlite`
(logical name `CategorizedToDo`). Tables:

- `tasks`, `subtasks` — the local Categorized ToDo data
- `settings` — k/v store, used as the credential mirror
  (`jira.site`, `jira.email`, `jira.token`, `jira.jql`, `gh.token`,
  `gh.owner`)
- `jira_cache` — last successful Jira issue fetch
- `gh_cache` — last successful GitHub Projects fetch
- `schema_version` — bumped inside `Database._migrate()` for every
  schema change

The Worklog Calendar plasmoid does **not** use SQLite — it relies
entirely on the shared `categorizedtodorc` file for Jira creds and
its own kcfg entries for everything else.

Do NOT add a separate JSON-file backend. Previous attempts using
`PlasmaCore.DataSource { engine: "executable" }` to write JSON files
proved unreliable on Kubuntu 24.04. The Notion mode is the one
exception that uses the executable engine — but only to invoke `ntn`,
never to read/write its own files.

## Mode-and-source dispatching

Both plasmoids host their full-representation as a `StackLayout`
inside `FullRepresentation.qml`. The current index is driven by a
single string kcfg:

- ToDo: `plasmoid.configuration.mode` ∈ `{todo, jira, gh, notion}`.
- Worklog: `plasmoid.configuration.worklogSource` ∈
  `{jira, jira-clockify, clockify}`.

The hamburger menu writes that string; the StackLayout reacts via a
binding. Every other widget (status text, footer counts, sprint gauges
visibility) keys off the same kcfg.

Hamburger menus use a `QQC2.Popup` containing `QQC2.RadioButton`s
inside a `QQC2.ButtonGroup` (NOT `QQC2.MenuItem { checkable: true }`,
which gives a checkbox visual and lets the user "uncheck" the active
option — neither of which is wanted).

## Worklog calendar in detail (the more complex plasmoid)

### Layout

```
┌──────────────────────────────────────────────────────────────────┐
│ Title  ◀ Today ▶   "10 May — 16 May 2026"   Modo9h ↻ ⓘ 📌       │  ← header
├──────────────────────────────────────────────────────────────────┤
│ Status line (NBSP placeholder so the grid never moves)           │  ← status
├──┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐
│  │ Sun │ Mon │ Tue │ Wed │ Thu │ Fri │ Sat │   ← day headers
│tt│Logd │Logd │Logd │Logd │Logd │Logd │Logd │   ← per-day totals row
├──┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
│09│     │     │     │     │     │     │     │
│30│     │     │     │     │     │     │     │
│..│     │     │     │     │     │     │     │
│18│     │     │     │     │     │     │     │   ← 18×30min rows (9h)
├──┴─────┴─────┴─────┴─────┴─────┴─────┴─────┤
│ ═══ Sprint ═════════════ Horas ═══════════ │   ← ring gauges
│      (●●)                  (●●)              │
│   Inicio / Fin           Disponible / Quemd  │
├──────────────────────────────────────────────────────────────────┤
│ Jira: 7h · Clockify: 5h    [proj v] [Jira → Clockify] [≡] [⚙]   │  ← footer
└──────────────────────────────────────────────────────────────────┘
```

### Grid geometry

- `rowHeight = 22 px` (a single 30-min slot)
- Hour column on the left: 56 px
- 7 day columns, equal width via `Layout.fillWidth: true`
- View mode `9h` = 18 slots = 396 px tall; `24h` = 48 slots = 1056 px
  tall (the grid is wrapped in a `QQC2.ScrollView` so it scrolls
  vertically in 24h mode)
- Worklog blocks are absolutely positioned inside their day column at
  `y = slotsFromViewStart * rowHeight`, `height = durationSlots *
  rowHeight`. In the combined view their width is `(dayCol.width / 2)
  - 3` and Clockify blocks sit at `x = (dayCol.width / 2) + 1`.

### Interactions on a worklog block (`WorklogEntry.qml`)

A single `MouseArea` dispatches three gestures based on the press Y
inside the block:

| Press zone       | Gesture            | What it changes                             |
| ---------------- | ------------------ | ------------------------------------------- |
| Top 5 px         | Resize from top    | New `started`, new `durationSec`            |
| Bottom 5 px      | Resize from bottom | New `durationSec` only                      |
| Middle           | Click or drag      | Click → modal; drag → new day + new start   |

The MouseArea is **manual** (no `drag.target`): on every
`positionChanged` while `pressed`, the new x/y/height are computed
from the cursor delta in **parent coordinates** (via `mapToItem`,
which is stable while the moving MouseArea itself shifts), then
**snapped to the grid** (`rowHeight` for Y, `columnWidth` for X) and
applied directly. The block hops between cells instead of smoothly
following the cursor.

`positionChanged` is guarded by `if (!pressed) return;` at the top —
**critical** because `hoverEnabled: true` would otherwise fire it on
plain hover, the resize logic would run with `_mode === 0` (idle),
break `block.height` binding, and the block would visually freeze at
the wrong size. Always keep this guard.

A duplicate button (top-right corner, hover-only visibility via a
sibling `HoverHandler`) is declared **after** the main MouseArea so
its own MouseArea wins hit-tests in its 16×16 square. It emits
`duplicateRequested` which the parent maps to a `createWorklog` /
`createEntry` call cloning the entry verbatim.

### Sprint gauges (`SprintGauges.qml` + `RingGauge.qml`)

Only visible when `worklogSource ∈ {jira, jira-clockify}` AND
`worklogViewMode === "9h"` AND `worklogShowSprintGauges` is true.

- **Sprint ring**: `(now - sprintStart) / (sprintEnd - sprintStart) *
  100`. Color threshold ladder (`#29B6F6 → #FBC02D → #FB8C00 → #E53935
  → #B71C1C` at 0/75/85/90/100).
- **Horas ring**: `consumed / (remaining + consumed) * 100`. Color
  `#81C784` (or `#4CAF50` at 100%). A `SequentialAnimation` fades
  between baseColor and a pale tint (`#C8E6C9`); cycle is 3 s + 1.5 s
  + 1.5 s by default, compressed to 1 s + 1 s when the sprint is
  ≥85 % and you're <99 % consumed.
- Both rings animate fill from 0 % to current on
  `plasmoid.expanded → true` (each popup open) via a `NumberAnimation`
  on `displayValue`.

**Sprint discovery** is configurable via `worklogSprintStrategy`:

- `subtask-customfield` (default) — JQL `issuetype in
  subTaskIssueTypes() AND assignee = currentUser()`, then scan
  `customfield_10020` (or `worklogSprintField`) on each result for an
  entry with `state="active"`. **Required** when only subtasks are
  assigned to the user (parents unassigned).
- `agile-board` — `GET /rest/agile/1.0/board/{worklogSprintBoardId}/
  sprint?state=active`, then JQL `sprint = N AND assignee =
  currentUser()` for the issues.
- `assignee-jql` — legacy `sprint in openSprints() AND assignee =
  currentUser()`. Only works if you're directly assigned to issues
  with a top-level `sprint` field.

**Remaining hours calculation** (used by the Horas ring's "Disponible"
and by the right column of the issue picker) is configurable via
`worklogRemainingMode`:

- `api` (default) — Jira's `timetracking.remainingEstimateSeconds`.
- `calculated` — `max(0, originalEstimate − timeSpent)`. Useful when
  remainingEstimate isn't kept in sync as users log time.

Any change to the experimental Sprint settings triggers an automatic
re-fetch through a `Connections { target: plasmoid.configuration }`
block in `FullRepresentation`.

## Categorized ToDo in detail

Less to say — most of the architecture is the same. Specifics:

- Up to **7** categories. `categoryCount` (1–7), `categoryNames`,
  `categoryColors`, `panelCounterColors` are parallel `StringList`
  entries (commas escape via Qt's default).
- TaskItem (the delegate for a task) shows a color strip on the left
  for its category — used both inside per-category tabs and inside
  the Global tab.
- Quick-add inputs (used to live next to "New…") were replaced by a
  **search field** that filters tasks within the active tab as you
  type. Pressing Esc clears the search.
- Tasks have `priority ∈ {XS, S, M, L, XL}` rendered as colored chips
  (`PriorityBadge.qml`).
- The compact view shows one swatch per category with the pending
  count. Hovering a swatch updates the **native** `Plasmoid
  .toolTipMainText` / `toolTipSubText` (NOT a QQC2.ToolTip — those
  rendered below the panel and overlapped the widget). A `HoverHandler`
  inside `SwatchBadge.qml` emits a signal that
  `CompactRepresentation` re-emits to `main.qml`, which writes two
  `compactHoverMain` / `compactHoverSub` properties; the tooltip
  bindings read those when non-empty and fall back to the widget-wide
  summary otherwise.

## Key files (for grep / search)

### Categorized ToDo (`package/contents/ui/`)

| File                          | Purpose |
| ----------------------------- | ------- |
| `main.qml`                    | Root; instantiates stores; mode dispatch |
| `CompactRepresentation.qml`   | Panel swatches; wheel cycles mode; hover → tooltip |
| `FullRepresentation.qml`      | Popup; `StackLayout` over the four mode views |
| `TodoView.qml`                | ToDo popup: tab bar + Global + per-category + Archive |
| `GlobalView.qml`              | Global tab listing every task with category-color strip |
| `CategoryView.qml`            | Per-category task list with quick search |
| `TaskItem.qml`                | Single task row; checkbox + title + priority + actions |
| `TaskEditDialog.qml`          | Modal for creating / editing a task |
| `JiraView.qml` / `JiraStore.qml` | Jira mode UI + REST client |
| `GhView.qml` / `GhStore.qml`     | GitHub Projects mode UI + GraphQL client |
| `NotionView.qml` / `NotionStore.qml` | Notion mode UI + `ntn` CLI invoker (executable engine) |
| `ModeMenuButton.qml`          | Hamburger menu used in every view's footer |
| `Database.qml`                | SQLite wrapper |
| `CategoryHelper.qml`          | Tiny helper for category-name/color lookup |
| `SwatchBadge.qml`             | One swatch+count in the compact view, with hover signal |

### Worklog Calendar (`worklog-plasmoid/package/contents/ui/`)

| File                          | Purpose |
| ----------------------------- | ------- |
| `main.qml`                    | Root; instantiates JiraWorklogStore + ClockifyStore |
| `CompactRepresentation.qml`   | Just an icon; click expands popup |
| `FullRepresentation.qml`      | Header + status + calendar + gauges + footer; all top-level state lives here |
| `WorklogCalendar.qml`         | The grid; manual drag-to-create; entry positioning math |
| `WorklogEntry.qml`            | Single block; click + cross-day drag + edge resize + duplicate button |
| `WorklogEditDialog.qml`       | Jira modal: time + issue picker + comment |
| `ClockifyEditDialog.qml`      | Clockify modal: time + project + tags + billable + description |
| `JiraWorklogStore.qml`        | Jira REST client: week fetch, sprint discovery (3 strategies), create/update/delete |
| `ClockifyStore.qml`           | Clockify REST client: workspace + projects + tags + entries + Jira sync |
| `RingGauge.qml`               | Canvas-based donut with fill animation + optional color-fade loop |
| `SprintGauges.qml`            | The two-ring section |
| `configGeneral.qml` etc.      | KCM-style config tabs |

## Conventions

- **No emojis in source code** unless the user explicitly asks. Same
  for `console.log` strings.
- KCfg `defaults` are the source of truth: don't hardcode values in QML
  — read `plasmoid.configuration.foo` so the user can override.
- Imperative writes to QML properties (`block.height = X`) **break
  bindings**. After such a write, the property won't follow its
  binding until the Item is destroyed and recreated (Repeater
  delegates are recreated on model assignment, which is how
  `fetchWeek` "fixes" a corrupted block). If you find yourself
  imperatively setting a property that has a binding, ask: should I
  be using a `Binding {}` element with a `when:` condition instead?
- Cross-store side-effects: when one store would naturally trigger
  another's refresh (e.g. after a Jira→Clockify sync, refetch
  Clockify), do so explicitly in the FullRepresentation handler. Don't
  add cross-store dependencies inside stores.
- Status messages in the worklog plasmoid: never assign
  `statusLabel.text = "..."` directly (that breaks the binding). Use
  `full._setStatus(text, isError)` which updates the
  `_statusOverride` property and restarts the 6-second clear timer;
  the label's text is a pure binding on that.

## Tooling

- Install: `./install.sh` (root for ToDo, `worklog-plasmoid/` for the
  other one). Both wrap `kpackagetool5 --install/--upgrade/--remove`.
- Dev mode: `./install.sh --dev` symlinks the `package/` folder into
  `~/.local/share/plasma/plasmoids/<id>/`. Edits become live after
  `kquitapp5 plasmashell && kstart5 plasmashell`.
- Logs:
  - `journalctl --user -f _COMM=plasmashell | grep -i jirastore`
  - `journalctl --user -f _COMM=plasmashell | grep -i jiraworklog`
  - `journalctl --user -f _COMM=plasmashell | grep -i clockify`
  - or just `journalctl --user -f -u plasma-plasmashell.service`
  - The popup also has an ⓘ diagnostic dialog that shows the same
    log even when console mirroring is off.
- Versioning: bump
  `package/metadata.desktop`'s `X-KDE-PluginInfo-Version` on every
  release. `kpackagetool5 --upgrade` uses it to decide whether to
  reinstall.
- Changelog: the worklog plasmoid maintains
  `worklog-plasmoid/CHANGELOG.md` — keep it in sync with version
  bumps.

## Common pitfalls (the ones I've actually hit)

1. **Property-name shadowing in QtObject subclasses**. A store's
   `property var plasmoid: null` shadowed the global `plasmoid`
   context property, producing self-binding nulls. Stores use
   `plasmoidApi` now (`plasmoidApi: plasmoid` in main.qml). Don't
   rename it back.

2. **Atlassian deprecating endpoints silently**. `/rest/api/3/search`
   was removed in 2025 → replaced by `/rest/api/3/search/jql`. The
   diagnostic overlay surfaces HTTP 410 with the migration message.
   If a new endpoint disappears, check
   <https://developer.atlassian.com/changelog/>.

3. **Clockify Object IDs vs names**. Workspace IDs are 24-char hex
   strings (`60661036c145ea559a4e8be6`); the workspace **name** is
   different. Pasting the name into `clockifyWorkspaceId` returns
   HTTP 403 on `/projects`. `ClockifyStore._isValidObjectId()` filters
   this and auto-resolves the real id from `/user`.

4. **Time precision**: Jira accepts ISO 8601 timestamps with timezone
   suffix `+0000`. Clockify requires the `.000` milliseconds segment
   (e.g. `2026-05-12T15:00:00.000Z`) — both `createEntry` and
   `updateEntry` send the full form via `_toUtcIso`. Don't strip the
   milliseconds.

5. **`positionChanged` fires on hover** when `hoverEnabled: true`.
   The first line of every `onPositionChanged` that mutates state must
   be `if (!pressed) return;`. See `WorklogEntry.qml`.

6. **QML signal handler arity**: in Qt 5.15 with the `function on…`
   syntax inside `Connections`, the signature must match the signal
   exactly or the handler silently fails. Mismatches were the cause
   of "status label stuck" — the binding was being clobbered by an
   imperative assignment in a buggy handler.
