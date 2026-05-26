# Changelog — Jira / Clockify Worklog Calendar

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
