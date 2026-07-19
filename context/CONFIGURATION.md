# Configuration reference

Every KCfg entry across both plasmoids, in load order. The files are:

- `package/contents/config/main.xml` — Categorized ToDo
- `worklog-plasmoid/package/contents/config/main.xml` — Worklog Calendar

Both use the **same KCfg file on disk** (`~/.config/categorizedtodorc`)
so the shared Jira credentials are read by both. The `<kcfgfile
name="categorizedtodorc"/>` declaration in each plasmoid's `main.xml`
controls that.

## Shared (Jira credentials)

Edit them in either plasmoid's config dialog; both will see the new
value after a Plasma reload.

| Entry         | Type   | Default | Notes |
| ------------- | ------ | ------- | ----- |
| `jiraSite`    | String | `""`    | e.g. `https://your-company.atlassian.net` (no trailing slash) |
| `jiraEmail`   | String | `""`    | The email associated with your Atlassian account |
| `jiraToken`   | String | `""`    | API token from id.atlassian.com — NOT your password. Stored in plain text |

## Categorized ToDo (`package/`)

### General

| Entry                | Type   | Default       | Notes |
| -------------------- | ------ | ------------- | ----- |
| `mode`               | String | `"todo"`      | `todo` \| `jira` \| `gh` \| `notion` |
| `categoryCount`      | Int    | `4`           | 1–7, number of active categories |
| `categoryNames`      | List   | 7 defaults    | `Personal,Trabajo,Estudio,Otros,Salud,Hogar,Hobbies` |
| `categoryColors`     | List   | 7 hex colors  | Parallel to names |
| `showPriorityIcons`  | Bool   | `true`        | Render priority chips |
| `confirmDelete`      | Bool   | `true`        | Confirm before deleting archived tasks |
| `panelShowLabels`    | Bool   | `false`       | Compact view shows category name next to swatch |
| `panelShowZero`      | Bool   | `true`        | Show swatches for categories with 0 pending tasks |
| `panelCounterStyle`  | String | `"right"`     | `right` \| `inside` |
| `panelCounterColors` | List   | 7 black/white | Per-category number color |
| `popupWidth`         | Int    | `700`         | px |
| `popupHeight`        | Int    | `650`         | px |

### Jira mode (in ToDo plasmoid only)

| Entry                  | Type   | Default     | Notes |
| ---------------------- | ------ | ----------- | ----- |
| `jiraJql`              | String | "(default JQL)" | JQL for the issue list |
| `jiraRefreshMinutes`   | Int    | `5`         | 0 disables auto-refresh |
| `jiraMaxResults`       | Int    | `50`        | 10–200 |
| `jiraCategoryCount`    | Int    | `3`         | 1–4 tabs |
| `jiraCategoryNames`    | List   | 4           | One per tab |
| `jiraCategoryColors`   | List   | 4 hex       | Per tab |
| `jiraCategoryTextColors`   | List | 4           | `white` or `black` |
| `jiraCategoryFilterFields` | List | 4           | `statusCategory` \| `issuetype` \| `status` \| `priority` \| `""` |
| `jiraCategoryFilterValues` | List | 4           | Filter value(s); `;` separates ORs |
| `jiraDebug`            | Bool   | `true`      | Log fetches in `console.log` |

### GitHub Projects mode

| Entry                 | Type   | Default | Notes |
| --------------------- | ------ | ------- | ----- |
| `ghToken`             | String | `""`    | Personal Access Token |
| `ghOwner`             | String | `""`    | User or org login |
| `ghOwnerType`         | String | `user`  | `user` \| `organization` |
| `ghProjectNumber`     | Int    | `1`     | Number from the project URL |
| `ghStatusField`       | String | `Status`| Custom single-select field used as Status |
| `ghIncludeClosed`     | Bool   | `true`  | Include closed issues / merged PRs |
| `ghRefreshMinutes`    | Int    | `5`     | 0 = manual |
| `ghMaxResults`        | Int    | `100`   | 10–300 |
| `ghDebug`             | Bool   | `true`  | |
| `ghCategoryCount`     | Int    | `3`     | 1–4 tabs |
| `ghCategoryNames`     | List   | 4       | |
| `ghCategoryColors`    | List   | 4 hex   | |
| `ghCategoryTextColors`    | List | 4     | `white` \| `black` |
| `ghCategoryFilterFields`  | List | 4     | `status` \| `type` \| `state` \| `repo` \| `""` |
| `ghCategoryFilterValues`  | List | 4     | `;` for OR |

### Notion mode

| Entry                    | Type   | Default | Notes |
| ------------------------ | ------ | ------- | ----- |
| `notionQuery`            | String | `""`    | Free-text search for `/v1/search` |
| `notionFilter`           | String | `page`  | `page` \| `database` |
| `notionMaxResults`       | Int    | `50`    | |
| `notionRefreshMinutes`   | Int    | `10`    | 0 = manual |
| `notionCliPath`          | String | `""`    | Absolute path; empty → use $PATH |
| `notionDebug`            | Bool   | `true`  | |

## Worklog Calendar (`worklog-plasmoid/`)

### General

| Entry                  | Type   | Default          | Notes |
| ---------------------- | ------ | ---------------- | ----- |
| `worklogSource`        | String | `jira`           | `jira` \| `jira-clockify` \| `clockify` |
| `jira2Enabled`         | Bool   | `false`          | Enable a second Jira instance |
| `jira2Site` / `jira2Email` / `jira2Token` | String | `""` | Second Jira credentials (worklog plasmoid only) |
| `jira1BlockColor`      | String | `#9b91e6`        | Jira 1 block color (drawn translucent) |
| `jira2BlockColor`      | String | `#26a69a`        | Jira 2 block color (drawn translucent) |
| `jira1ClockifyProjectId` | String | `""`           | Clockify project Jira 1's worklogs sync into |
| `jira2ClockifyProjectId` | String | `""`           | Clockify project Jira 2's worklogs sync into |
| `worklogViewMode`      | String | `9h`             | `9h` (09:00–18:00) \| `24h` |
| `worklogPopupWidth`    | Int    | `1100`           | px |
| `worklogPopupHeight`   | Int    | `750`            | px |
| `worklogDailyTargetHours` | Double | `8`           | Used for the totals diff |
| `worklogIssueJql`      | String | "(default JQL)"  | JQL for the new-worklog issue picker |
| `worklogIssueMax`      | Int    | `50`             | Max picker rows |
| `worklogShowIssueSummary` | Bool | `false`          | Append issue title after the key on each block |
| `worklogShowSprintGauges` | Bool | `true`           | Master toggle for the bottom panel (rings / subtasks / heatmap), all modes |
| `worklogBottomView`    | String | `rings`          | Bottom-panel view: `rings` \| `subtasks` \| `heatmap` (vertical switch / wheel) |
| `worklogShowSubtaskTable` | Bool | `true`           | Enable the third bottom-panel view (subtask table) |
| `worklogSubtaskJql`    | String | "(my open subtasks)" | JQL that populates the subtask table |
| `worklogSubtaskShowParent` | Bool | `true`         | Show the parent-issue column (with tooltip) in the subtask table |
| `worklogModalWidth`    | Int    | `720`            | New/edit worklog modal width (px) |
| `worklogModalHeight`   | Int    | `520`            | New/edit worklog modal height (px) |
| `worklogPinned`        | Bool   | `false`          | Pin button state |
| `worklogDebug`         | Bool   | `true`           | |

### Sprint (experimental)

| Entry                  | Type   | Default                | Notes |
| ---------------------- | ------ | ---------------------- | ----- |
| `worklogSprintStrategy` | String | `subtask-customfield` | `subtask-customfield` \| `agile-board` \| `assignee-jql` |
| `worklogSprintField`   | String | `customfield_10020`    | Jira field name carrying the sprint array |
| `worklogSprintBoardId` | Int    | `0`                    | Required by `agile-board` |
| `worklogRemainingMode` | String | `api`                  | `api` (`remainingEstimateSeconds`) \| `calculated` (`max(0, original − spent)`) |

### Clockify

| Entry                  | Type   | Default | Notes |
| ---------------------- | ------ | ------- | ----- |
| `clockifyApiKey`       | String | `""`    | From Clockify profile settings → API |
| `clockifyWorkspaceId`  | String | `""`    | 24-char hex Object ID; empty → use `/user.defaultWorkspace` |
| `clockifyUserId`       | String | `""`    | 24-char hex; resolved from `/user.id` and persisted |
| `clockifyDefaultProjectId` | String | `""` | Used by the new-entry modal and by the Jira → Clockify sync |
| `clockifyBillableDefault` | Bool   | `true`  | |
| `clockifyDebug`        | Bool   | `true`  | |

### Google Calendar (read-only)

OAuth 2.0 via the "TV and Limited Input devices" (device-code) flow — no
redirect URI / local server. The config tab runs the one-time device
authorization and the calendar-list fetch; the runtime
`GoogleCalendarStore` exchanges the refresh token for access tokens. See
`worklog-plasmoid/docs/GOOGLE_CALENDAR.md`.

| Entry                  | Type   | Default   | Notes |
| ---------------------- | ------ | --------- | ----- |
| `googleCalEnabled`     | Bool   | `false`   | Show event blocks; toggled by the top-right check button |
| `googleClientId`       | String | `""`      | OAuth client id (type "TV and Limited Input devices") |
| `googleClientSecret`   | String | `""`      | OAuth client secret |
| `googleRefreshToken`   | String | `""`      | Set by the device-code authorization in the config tab |
| `googleCalendarId`     | String | `primary` | Legacy single id; migrated into `googleCalendarIds` |
| `googleCalendarIds`    | StringList | `[]`  | Up to 3 calendar ids to read (parallel to colors) |
| `googleCalendarColors` | StringList | `[]`  | Base hex color per calendar; always drawn translucent |
| `googleCalDebug`       | Bool   | `true`    | |

## How config dialogs map to KCfg

Each `configXxx.qml` file declares `property alias cfg_someEntry:
fieldId.someProperty` or `property string cfg_someEntry: "default"`.
The Plasma configuration system auto-binds these to the matching
KCfg entry (same name minus the `cfg_` prefix) when the dialog opens
and writes them back when the user clicks OK / Apply.

`property alias` is read/write through the form field; `property
string` (or any explicit type) is a writable, defaultable backing
store — used for RadioButton groups where there's no single field to
alias.

## Live reaction to config changes

Most settings affect bindings directly (read fresh on every access),
so changes take effect immediately. A few require side-effects and
have explicit `Connections { target: plasmoid.configuration }` blocks
in `main.qml` or `FullRepresentation.qml`:

- `jiraSite / jiraEmail / jiraToken / jiraJql` → mirror to SQLite via
  `_jira.persistCredentials()`.
- `ghToken / ghOwner` → same for GitHub.
- `jiraRefreshMinutes / ghRefreshMinutes` → restart the refresh timer.
- `mode` (ToDo) and `worklogSource` (Worklog) → trigger first fetch
  in the new mode if `lastFetchedAt === 0`.
- `worklogSprintStrategy / worklogSprintField / worklogSprintBoardId
  / worklogRemainingMode` → re-fetch sprint info so the gauge
  refreshes without a manual ↻.
- `worklogPinned` → mirror to `plasmoid.hideOnWindowDeactivate`.

If you add a setting that requires a re-fetch or other side-effect,
wire it up explicitly — bindings alone aren't enough for actions that
involve network calls.
