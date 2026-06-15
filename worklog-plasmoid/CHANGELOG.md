# Changelog — Jira / Clockify Worklog Calendar

## 0.8.0 — Subtask table (third bottom-panel section)

- **Subtask table.** New third bottom-panel view — the vertical switch
  now cycles through **Anillos → Tabla → Heatmap** (and the mouse wheel
  walks the same order, clamping at the ends). Columns: code + title,
  status badge (colored by Jira's `statusCategory.colorName`), available
  hours (using the configured `worklogRemainingMode`), and an optional
  parent column with the parent key + tooltip showing its summary.
- **Left-click → detail modal.** Opens a read-only `SubtaskDetailDialog`
  with status, parent, original / spent / available hours, description,
  assignee and create/update stamps. "Abrir en Jira" button drives
  `Qt.openUrlExternally` against `{site}/browse/{key}`.
- **Right-click → context menu.** "Cambiar estado" submenu lists the
  available Jira transitions (fetched lazily via
  `/rest/api/3/issue/{key}/transitions`; rendered through an
  `Instantiator` so the QML Menu picks up the dynamic items). Picking
  one POSTs the transition and refetches the table. "Ver en Jira"
  opens the issue page in the browser.
- **Three new kcfg entries**, all in the General group:
  `worklogShowSubtaskTable` (Bool, default `true`),
  `worklogSubtaskJql` (default `issuetype in subTaskIssueTypes() AND
  assignee = currentUser() AND statusCategory != Done ORDER BY updated
  DESC`) and `worklogSubtaskShowParent` (Bool, default `true`). All
  three are editable from Configurar → General. `worklogBottomView` now
  accepts the value `"subtasks"` and falls back to `"rings"` if the
  saved view is no longer available.
- **Bottom-panel switch is index-driven.** The slide direction is
  computed from the position of source/target inside `_bottomViews`
  (rings=0, subtasks=1, heatmap=2) so animations stay correct whether
  or not the subtask view is enabled.
- **Store additions** on `JiraWorklogStore`: `subtasks` array,
  `fetchSubtasks(cb)`, `fetchTransitions(key, cb)`,
  `transitionIssue(key, transitionId, cb)`,
  `fetchIssueDetail(key, cb)` and `issueWebUrl(key)`.

Bumped metadata 0.7.0 → 0.8.0.

## 0.7.0 — Heatmap nav fix + click-to-jump + wheel switch + Shift 10-min snap

- **Heatmap empty-on-month-change fixed.** `refresh()` now computes the
  target month straight from `monthOffset` instead of reading the
  `year`/`month` bindings, which could still return the OLD month when
  the refresh ran inside `onMonthOffsetChanged` — that stale key made
  the just-changed month render empty until a manual refresh.
- **Click a heatmap cell to jump to that day.** Day cells are now
  clickable; clicking one navigates the calendar to that day's week
  (and re-syncs). New `daySelected(date)` signal on `MonthHeatmap`.
- **Mouse wheel switches the bottom view.** Scrolling down over the
  bottom panel switches to the heatmap, scrolling up to the rings
  (`WheelHandler`, doesn't consume clicks). The switch buttons now just
  set the config; a single `onWorklogBottomViewChanged` handler drives
  the animation and refresh for buttons, wheel and config dialog alike.
- **Shift = 10-minute granularity.** Holding Shift while drag-creating a
  block snaps to 10-minute steps instead of 30 (so 10/20/40-min blocks
  are possible); the same applies to moving and edge-resizing existing
  blocks. Without Shift it stays at 30 min as before. The grid rows are
  unchanged — only the block gets shorter/positioned precisely. Blocks
  now render at minute precision (`_yForEntry` / `_heightForEntry`), the
  duration floor dropped from 30 to 10 min, and the Shift state flows
  through the move/resize signals as a `fine` flag.

Bumped metadata 0.6.1 → 0.7.0.

## 0.6.1 — Heatmap layout, fixed switch, robust month update, switch fade

- **Icon column is now a normal column.** The left row-icon column
  (Clockify / Jira) was wider/odd; it's now an equal-width column like
  the days (`fillWidth` + `preferredWidth: 1`), so the grid spans the
  full width evenly.
- **Bottom panel has a fixed height (200 px).** The heatmap (shorter
  than the rings) sits vertically centered in it, and the vertical
  switch on the right is pinned to the center so it never jumps when
  you toggle views.
- **Month update is now bulletproof.** Per-day totals are tagged with
  the month they belong to (`clockifyKey` / `jiraKey`); a cell only
  reads a value when its tag matches the visible month. Combined with
  clearing on every month change and the stale-response `_reqId` guard,
  navigating current → last → current can no longer leave the previous
  month's numbers on screen.
- **Switch transition.** Flipping rings → heatmap fades the current
  view out downward and the new one in; heatmap → rings fades upward.
  Driven by a SequentialAnimation that swaps the displayed view at
  opacity 0 (down/up direction via a Translate).

Bumped metadata 0.6.0 → 0.6.1.

## 0.6.0 — Bottom panel switch (rings ⟷ heatmap), heatmap polish

- **Heatmap available in every mode.** The bottom panel below the
  calendar is no longer Clockify-only / Jira-only. It now appears in all
  modes and a **vertical switch on its right** flips between the
  Sprint/Horas rings and the monthly heatmap. New `worklogBottomView`
  kcfg (`rings` | `heatmap`, default `rings`) backs the switch;
  `worklogShowSprintGauges` is repurposed as the master "show bottom
  panel" toggle (relabelled "Panel inferior" in config). The old
  `worklogShowMonthHeatmap` / `worklogHeatmapShowJira` toggles were
  removed (superseded by the switch and the always-on Jira row).
- **Month change clears stale data.** Switching months now wipes the
  totals immediately and tags each request so a late response for the
  previous month can't repaint the grid. Fixes the "leftover last-month
  values" glitch.
- **Help labels replaced by a left icon column.** The legend text under
  the heatmap is gone. Instead the table has a leftmost column whose
  rows 3 and 4 carry a Clockify and a Jira icon respectively, each with
  a small tooltip, aligned to the colored rows via fixed row heights.
- **Jira row is always shown** (4th row), no longer optional.
- **Hover fade on cells.** Each hours cell lightens with a short
  ~180 ms fade when hovered and fades back on leave (a white overlay
  with a `Behavior on opacity`).

Bumped metadata 0.5.0 → 0.6.0.

## 0.5.0 — Monthly hours heatmap + Clockify default-project picker

- **Monthly heatmap** (Clockify mode). The previously-empty area below
  the calendar in Clockify mode now shows a horizontal month table, one
  column per day:
  - Row 1: weekday letter (D L M Mi J V S) — gray on weekends.
  - Row 2: day number — gray on weekends.
  - Row 3: Clockify hours that day as a decimal (3h30m → 3.5, 4h → 4).
    The cell background is graded gray (0) → red → yellow → light green
    from 0 to 4 h, staying green above 4.
  - Row 4 (optional): Jira burned hours that day, same format + grading.
  - ◀ / ▶ toggle between the **current month** and the **last month**.
  - New `MonthHeatmap.qml`. Per-day totals come from two new aggregation
    methods, `ClockifyStore.fetchMonthTotals` (paginated) and
    `JiraWorklogStore.fetchMonthTotals`, neither of which touches the
    stores' week-scoped arrays used by the calendar.
  - Config: `worklogShowMonthHeatmap` (Bool, default true) gates the
    whole table; `worklogHeatmapShowJira` (Bool, default true) gates the
    optional 4th Jira row. Both exposed as checkboxes in General.
  - Refreshed on popup open, on ↻ sync, and on month toggle.

- **Clockify default project is now a ComboBox.** The Clockify config
  tab's "Proyecto por defecto" field changed from a raw hex-ID TextField
  to a ComboBox. Clicking **Probar conexión** validates the key and then
  fetches the workspace's projects (`GET /workspaces/{wid}/projects`),
  populating the dropdown so you pick the project by name. A saved id
  that isn't in the fetched list shows as a `[abcd1234] (probá la
  conexión)` placeholder so it isn't silently dropped.

Bumped metadata 0.4.6 → 0.5.0.

## 0.4.6 — Available-hours breakdown tooltip

- **Tooltip on "Disponible".** Hovering the *Disponible: Nh* legend
  under the Horas ring now shows a tooltip listing which issues make
  up those available hours, one per line, e.g. `CP-123: 4h` /
  `CP-124: 2h 30m`. Sorted descending by remaining hours, capped at
  20 rows with a "…y N más" footer.
- `JiraWorklogStore` now exposes `sprintAvailableBreakdown`
  (`[{ key, summary, remainingSec }]`, only issues with remaining > 0),
  populated next to `sprintAvailableSec` in
  `_computeSprintTotalsFromIssues` and cleared in `_clearSprint` and
  the agile-board error path. It honors the same `worklogRemainingMode`
  (api / calculated) as the ring, so the per-issue rows always sum to
  the Disponible value.
- The Horas legend was split into two labels ("Disponible" and
  "Quemadas") so only the available-hours line carries the hover
  target.

## 0.4.5 — Status auto-clear, in-view clamping, modal polish, weekend tint

A bunch of post-drag-refactor cleanups:

- **Status line auto-clears again.** The move / duplicate handlers
  were stopping `_clearStatusTimer` after `_setStatus()` restarted it,
  so the status string ("Actualizando worklog Jira…", etc.) stayed
  visible until the next event. Removed those `stop()` calls — only
  `syncJiraIntoClockify` keeps the manual stop (it's a multi-second
  multi-POST and needs the message to persist throughout). The status
  binding still reserves vertical space via a non-breaking-space
  fallback, so the grid never moves when messages appear/disappear.

- **Drag stays inside the visible hours.** In 9h mode (or any non-
  24h mode), pressing a block and dragging past the bottom would let
  it spill below 18:00. Same with bottom-resize. Both `block.y` and
  `block.height` are now clamped to `[0, columnHeight]` in
  `onPositionChanged` for the move and bottom-resize paths. Top-resize
  was already clamped to 0.

- **Duplicate button visible on hover.** Switched from a
  `HoverHandler` (which silently misbehaved alongside the
  hoverEnabled MouseArea) to binding `dupBtn.visible` directly to
  `ma.containsMouse || dupBtnMA.containsMouse`. Button now appears
  as soon as the cursor enters the block.

- **Modal size is configurable.** New kcfg entries
  `worklogModalWidth` (default 720) and `worklogModalHeight`
  (default 520). Two SpinBoxes in General → Popup expose them. Both
  dialogs (Jira `WorklogEditDialog` and `ClockifyEditDialog`) read
  these values, clamped to the parent popup's available size minus
  a small margin so they never spill out.

- **Escape closes the modal.** `focus: visible` + `Keys.onEscapePressed`
  on the root Item, plus an explicit `dlg.forceActiveFocus()` in both
  `openCreate` and `openEdit` so Plasma actually delivers key events
  to the dialog. Skipped while loading (so you don't bail mid-save).

- **Inicio / Fin times are directly editable.** The `09:30` labels
  next to the +/- buttons in both modals were swapped for
  `QQC2.TextField`s with `inputMask: "99:99;_"`. Typing a valid
  HH:MM and hitting Enter (or losing focus) applies the value via a
  new `_applyTimeText(text, isStart)` helper that preserves the date
  portion of `startMs` / `endMs` and rejects invalid input (bouncing
  the field back to the current formatted value). The +/- buttons
  still work and update the field through a `Connections` block on
  `startMsChanged` / `endMsChanged` — the field is only re-set when
  it isn't actively focused, so external changes don't yank the
  cursor while you're typing.

- **Saturday + Sunday columns slightly darker.** New `_isWeekend(idx)`
  helper in `WorklogCalendar`; weekends get a `Qt.rgba(0,0,0,0.18)`
  overlay both in the day-column body and in the day-header cell.
  Stacks with the today tint (a Saturday-that-is-today still gets
  the highlight color over the weekend darken).

Bumped metadata 0.4.4 → 0.4.5.

## 0.4.4 — Stop the ScrollView from stealing block-drag events

0.4.3 dropped `drag.target: block` to make the move snap-to-cell, but
that change also turned off Qt's drag heuristic — and the
`QQC2.ScrollView` (Flickable) hosting the calendar started
interpreting press-and-move on a block as a scroll gesture, hijacking
the events. Result: dragging a block scrolled the grid up/down while
the block stayed put.

Fix: `preventStealing: true` on `WorklogEntry`'s MouseArea so the
press stays with the block for the entire gesture, regardless of the
Flickable behind it.

Bumped metadata 0.4.3 → 0.4.4.

## 0.4.3 — Hover-resize bug, snap-during-drag, duplicate button

Three blocks of work on the calendar entry interaction:

- **Hover-resize bug fixed.** `onPositionChanged` fires on plain hover
  when `hoverEnabled: true`. The previous code's `_mode === 3`
  fallthrough was implicit (`else { … }`), so hovering on a block
  with `_mode === 0` (idle) ran the bottom-resize logic, imperatively
  set `block.height`, and **broke the height binding** — the block
  stayed at the corrupted size until refetch. Added a hard
  `if (!pressed) return;` guard at the top and made the fallthrough
  branches explicit (`else if (_mode === 2)` / `else if (_mode === 3)`).
- **Snap-to-cell while dragging.** Removed `drag.target: block`
  entirely; moves and resizes now compute their target position from
  the cursor delta in stable parent coordinates (via `mapToItem`) and
  snap to whole rows/columns on every `onPositionChanged`. The block
  hops between cells instead of smoothly following the cursor —
  matches the user's "más estático" request and makes alignment
  obvious during the drag.
- **Duplicate button.** Small 16×16 icon button (top-right corner of
  every worklog block), visible on hover via a `HoverHandler` that
  doesn't compete with the main `MouseArea`. Emits
  `duplicateRequested`; FullRepresentation maps to
  `jiraStore.createWorklog` / `clockifyStore.createEntry` with the
  entry's existing time, duration, comment/description, projectId,
  tags and billable — i.e. an exact clone. The standard `createFinished`
  Connections triggers a refetch so the new block appears alongside
  the original.

Bumped metadata 0.4.2 → 0.4.3.

## 0.4.2 — Disponible = remaining, with API/calculated toggle

`Disponible` on the Horas ring was summing `timeoriginalestimate` for
every subtask in the active sprint, which inflated the number with
hours already consumed in previous sprints (e.g. 159h 30m vs the
~13–32h actually pending). Two changes:

- **`Disponible` now uses *remaining*** (sum of `_remainingSec(f)`)
  instead of original estimate. Issues fully consumed in earlier
  sprints contribute 0, as expected.
- **`Horas` ring percentage** is now `consumed / (avail + consumed)`,
  matching the original spec ("el total de horas seteadas (disponibles
  y consumidas)"). The total is therefore "what's left to do plus
  what I've already logged in this sprint".
- **New experimental config** `worklogRemainingMode`
  (`"api"` default, `"calculated"`):
  - `api`: uses `timetracking.remainingEstimateSeconds` (the value
    Jira shows in the Remaining field).
  - `calculated`: uses
    `max(0, originalEstimateSeconds − timeSpentSeconds)`.
    Useful when Jira's remainingEstimate isn't kept in sync as
    you log time — many users find the calculated value matches
    reality better.
  Affects both the ring (Disponible legend + the percentage) and
  the column on the right of the new-worklog picker.
- The General config tab gained the new "Remaining" radio in the
  experimental section.
- Sprint info auto-refetches when any of the experimental Sprint /
  Remaining settings change, so the gauge reflects the new mode
  without a manual sync click.

Bumped metadata 0.4.1 → 0.4.2.

## 0.4.1 — Sprint discovery: 3 strategies (subtarea-only friendly)

The 0.4.0 sprint lookup (`sprint in openSprints() AND assignee = currentUser()`)
returned nothing for users who only have subtasks assigned (parent
stories unassigned), leaving both gauges stuck at 0%.

`JiraWorklogStore.fetchSprintInfo` now dispatches to one of three
selectable strategies, exposed under General → Sprint (experimental):

- **Subtarea + customfield** (default) — queries
  `issuetype in subTaskIssueTypes() AND assignee = currentUser()` and
  reads the sprint custom field (`customfield_10020` by default) on
  each subtask, picks the entry with `state="active"`, and aggregates
  estimates + worklogs across those subtasks.
- **Board ID (agile)** — calls
  `GET /rest/agile/1.0/board/{id}/sprint?state=active` with the
  board id from the new `worklogSprintBoardId` config field, then
  pulls the issues in that sprint with
  `sprint = N AND assignee = currentUser()`.
- **Assignee JQL (legacy 0.4.0)** — the original 0.4.0 query, kept
  for setups where it worked.

New kcfg entries:
- `worklogSprintStrategy` (String, default `"subtask-customfield"`).
- `worklogSprintBoardId` (Int, default `0`).
- `worklogSprintField` default changed `"sprint"` → `"customfield_10020"`.

Every strategy shares the same totals computation
(`_computeSprintTotalsFromIssues`) so changing strategies doesn't
alter the numbers — only how the active sprint is discovered.

## 0.4.0 — Sprint + Horas gauges, popup default 750px

### New

- **Sprint gauge** (left ring at the bottom of the popup) shows the
  percentage of the active Jira sprint that has elapsed, computed from
  the sprint's `startDate`, `endDate` and the current time. Color
  thresholds:
  - **0–74 %**: celeste (`#29B6F6`)
  - **75–84 %**: amarillo (`#FBC02D`)
  - **85–89 %**: naranja (`#FB8C00`)
  - **90–99 %**: rojo (`#E53935`)
  - **100 %**: rojo oscuro (`#B71C1C`)
  Legend below shows `Inicio: dd/mm` and `Fin: dd/mm`.

- **Horas gauge** (right ring) shows the percentage of the user's
  total estimated hours in the active sprint that have already been
  logged. Sum of `timeoriginalestimate` across the sprint's issues is
  used as the denominator; sum of *your* worklogs within the sprint's
  date range is the numerator. Colors:
  - **0–99 %**: verde claro (`#81C784`)
  - **100 %**: verde claro fuerte (`#4CAF50`)
  Legend below shows `Disponible: …` and `Quemadas: …`.

- **Color fade-loop** on the Horas ring: animates from base green to a
  pale tint (`#C8E6C9`) and back. Default cycle: 3 s base → 1.5 s
  fade-out → 1.5 s fade-in. When the sprint is at ≥85 % progress AND
  hours are below 99 % the cycle compresses to **1 s + 1 s** (faster
  flashing) to flag that you're behind. Returns to normal speed at
  100 %.

- **Fill animation**: both rings animate from 0 % to their target
  value (1.5 s, `Easing.OutQuart`) every time the popup is opened.

- **Decorative dividers**: thin horizontal lines on the left of
  Sprint, between Sprint and Horas, and on the right of Horas.

- New kcfg entries:
  - `worklogShowSprintGauges` (Bool, default `true`) — hides the
    gauges from the popup when off.
  - `worklogSprintField` (String, default `"sprint"`) — name of the
    Jira issue field that exposes the sprint array; can be overridden
    to `customfield_NNNNN` for older Jira instances.

- New `RingGauge.qml` reusable canvas-based donut (anti-aliased,
  rounded line caps) and `SprintGauges.qml` that hosts the two
  rings + legends + decorative lines.

### Changed

- **Popup default height bumped from 650 to 750 px** to leave room
  for the gauges in 9h mode.
- `JiraWorklogStore`:
  - New `currentSprint`, `sprintAvailableSec`, `sprintConsumedSec`
    properties.
  - New `fetchSprintInfo(callback)` method that runs
    `sprint in openSprints() AND assignee = currentUser()` against
    `/rest/api/3/search/jql`, picks the first `state="active"`
    sprint, and aggregates the totals.
  - `myAccountId` is resolved on demand inside `fetchSprintInfo` if
    it isn't already cached, so the gauges work even before the first
    week sync.
- `FullRepresentation`:
  - `syncNow()` now also triggers `fetchSprintInfo()` when the gauges
    are visible.
  - On startup and every `plasmoid.expanded → true` the gauges are
    re-fetched and their fill animations replay.
- `configGeneral`:
  - New "Gauges" checkbox toggling `worklogShowSprintGauges`.

### Visibility rules for the gauges

The gauges are rendered only when **all** of the following hold:

1. `worklogShowSprintGauges` is true (default).
2. `worklogViewMode` is `"9h"` (24h mode fills the popup vertically,
   leaving no empty space for them).
3. `worklogSource` is `"jira"` or `"jira-clockify"` (Clockify has no
   sprint concept).

If there's no active sprint visible to the user, both rings render at
0 % and the legends show `Sin sprint activo` / `Disponible: 0h /
Quemadas: 0h`.
