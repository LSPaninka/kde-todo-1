# Changelog — Jira / Clockify Worklog Calendar

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
