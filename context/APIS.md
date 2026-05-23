# APIs

Every external endpoint the plasmoids talk to, and how their responses
are consumed. All requests are made from QML via `XMLHttpRequest`
except the Notion mode, which shells out to the `ntn` CLI.

## Jira Cloud REST API v3

Base: `<plasmoid.configuration.jiraSite>/rest/api/3` (no trailing slash).
Auth: `Authorization: Basic <base64(email:apiToken)>`.

Token is generated at <https://id.atlassian.com/manage-profile/security/api-tokens>.

| Operation                       | Endpoint                                                            |
| ------------------------------- | ------------------------------------------------------------------- |
| Current user info               | `GET /rest/api/3/myself`                                            |
| Issue search (paginated)        | `GET /rest/api/3/search/jql?jql=…&fields=…&maxResults=…`            |
| Worklogs on issue (list)        | `GET /rest/api/3/issue/{key}/worklog`                               |
| Add worklog                     | `POST /rest/api/3/issue/{key}/worklog`                              |
| Update worklog                  | `PUT /rest/api/3/issue/{key}/worklog/{id}`                          |
| Delete worklog                  | `DELETE /rest/api/3/issue/{key}/worklog/{id}`                       |

**Important migration note**: Atlassian removed `/rest/api/3/search`
sometime in 2025. The plasmoid uses the replacement
`/rest/api/3/search/jql` exclusively. If a 410 with the body containing
`https://developer.atlassian.com/changelog/#CHANGE-2046` appears, that
endpoint went away — check the latest changelog and migrate the URL.

### Worklog body shape (POST / PUT)

```json
{
  "started":          "2026-05-12T15:00:00.000+0000",
  "timeSpentSeconds": 1800,
  "comment": {
    "type": "doc",
    "version": 1,
    "content": [
      { "type": "paragraph",
        "content": [{ "type": "text", "text": "(no comment provided)" }] }
    ]
  }
}
```

- `started` must include the milliseconds and a numeric timezone offset
  (`+0000`). Format produced by `_formatJiraStarted()` in
  `JiraWorklogStore.qml`.
- `comment` is the Atlassian Document Format (ADF) tree. The plasmoid
  always sends a single paragraph with plain text. Reading it back uses
  `_extractAdfText()` which walks the tree concatenating text nodes
  with `\n` between paragraphs.
- Omit `comment` from a PUT to leave it untouched (Jira's PUT is a
  partial update for worklog).

### Sprint discovery (worklog plasmoid)

Three strategies, behind `worklogSprintStrategy`:

| Strategy              | Endpoints used                                                                                                                                       |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `subtask-customfield` (default) | `GET /rest/api/3/search/jql?jql=issuetype in subTaskIssueTypes() AND assignee = currentUser()&fields=…,customfield_10020` — scan results for an entry with `state="active"`. |
| `agile-board`         | `GET /rest/agile/1.0/board/{worklogSprintBoardId}/sprint?state=active`, then `GET /rest/api/3/search/jql?jql=sprint = N AND assignee = currentUser()` for issues. |
| `assignee-jql`        | `GET /rest/api/3/search/jql?jql=sprint in openSprints() AND assignee = currentUser()` — only works if the user is assignee at the issue (not subtask) level. |

The agile endpoint family (`/rest/agile/1.0/…`) needs the
same Basic auth. Sprint object shape used by the gauges:

```json
{
  "id":        1978,
  "name":      "Portal Sprint 57",
  "state":     "active",
  "startDate": "2026-05-18T18:00:59.063Z",
  "endDate":   "2026-05-29T21:00:00.000Z"
}
```

### Issue fields read by the plasmoids

- `summary` (string)
- `status` → `{ name, statusCategory: { key } }`
- `priority` → `{ name }`
- `issuetype` → `{ name, subtask }`
- `parent` → `{ key, fields: { summary } }`
- `updated` (ISO 8601)
- `worklog` → `{ worklogs: [ { id, author: { accountId }, started, timeSpentSeconds, comment (ADF) } ] }`
  (the search response truncates to ~20 worklogs per issue; for more,
  hit `/rest/api/3/issue/{key}/worklog` directly)
- `timeoriginalestimate` / `timeestimate` (seconds, top-level)
- `timetracking` → `{ originalEstimateSeconds, remainingEstimateSeconds, timeSpentSeconds }`
- `customfield_10020` (or whatever `worklogSprintField` points to) →
  array of sprint objects

### Error handling

The plasmoids surface HTTP status codes in the diagnostic overlay with
specific guidance:

- 401 → "Credenciales rechazadas — token vencido o revocado".
- 403 → "El token no tiene permisos sobre este recurso. El usuario
  debe tener 'Browse Projects' en al menos un proyecto."
- 404 → "El endpoint no existe en este servidor. La URL del sitio
  puede estar mal, o la instancia es Server/DC sin API v3."
- 400 → "JQL inválido. Mensaje del servidor: …"
- 410 → "Atlassian removió este endpoint. Mirá
  developer.atlassian.com/changelog/."
- 0   → DNS / TLS / network / sockets (4 sub-causes listed).

## Clockify REST API v1

Base: `https://api.clockify.me/api/v1`.
Auth: `X-Api-Key: <plasmoid.configuration.clockifyApiKey>`.

Generated in Clockify → *Profile → Settings → API*.

| Operation                       | Endpoint                                                                  |
| ------------------------------- | ------------------------------------------------------------------------- |
| Current user + default workspace | `GET /user`                                                              |
| Projects (with color)           | `GET /workspaces/{wid}/projects?archived=false&page-size=200`             |
| Tags                            | `GET /workspaces/{wid}/tags?archived=false&page-size=200`                 |
| Time entries (week)             | `GET /workspaces/{wid}/user/{uid}/time-entries?start=ISO&end=ISO&page-size=200` |
| Create time entry               | `POST /workspaces/{wid}/time-entries`                                     |
| Update time entry (full PUT)    | `PUT /workspaces/{wid}/time-entries/{id}`                                 |
| Delete                          | `DELETE /workspaces/{wid}/time-entries/{id}`                              |

`{wid}` and `{uid}` are 24-char lowercase hex **Object IDs**, never
human-readable names. `ClockifyStore._isValidObjectId()` enforces this
(regex `/^[0-9a-fA-F]{24}$/`). The store auto-resolves both from
`/user.defaultWorkspace` and `/user.id` and persists them to
`clockifyWorkspaceId` + `clockifyUserId` so subsequent fetches skip
the lookup.

### Time entry body shape

```json
{
  "start":       "2026-05-12T15:00:00.000Z",
  "end":         "2026-05-12T16:00:00.000Z",
  "description": "CP-1234: …",
  "billable":    true,
  "projectId":   "60b6d80…",
  "tagIds":      ["...", "..."]
}
```

- `start` and `end` are full UTC ISO 8601 **with milliseconds and Z**
  (no offset). Stripping the `.000` returns HTTP 400 on POST/PUT.
- `projectId` is **required** in many workspaces (those with "Project
  required for time entries" enabled). The Jira → Clockify sync
  defaults to `clockifyDefaultProjectId`; a missing project gives 400.

### Jira → Clockify sync

`ClockifyStore.syncFromJira(jiraWorklogs, defaultProjectId,
defaultBillable, cb)`:

1. Build the desired description for each Jira worklog:
   `<issueKey>: <issueSummary>`.
2. Dedupe: skip if there's already a Clockify entry with the same
   description and `start ±1 minute`.
3. POST the rest sequentially (not in parallel — Clockify's rate
   limits aren't documented; sequential is conservative).
4. Report `(created, skipped, failed)` to the callback.

## Notion API (via `ntn` CLI, not REST)

The `ntn` CLI is Notion's official command-line client released as
part of Notion 3.5 (May 2026 — Notion Developer Platform). It handles
auth internally; the plasmoid never sees the token.

Installation:

```bash
curl -fsSL https://ntn.dev | bash
ntn login
```

The plasmoid shells `ntn` through `PlasmaCore.DataSource` with
`engine: "executable"`, wrapping each command in `sh -c '<cmd>'`. All
variable input is wrapped in POSIX single-quote escaping
(`_shellQuote()`) so titles / descriptions can't break out.

Each invocation gets a unique `seq` suffix appended to the source
string. The DataSource caches by source name, so without that suffix a
re-run of the same command would return stale stdout.

| Operation                | Command                                                                                       |
| ------------------------ | --------------------------------------------------------------------------------------------- |
| List/search pages        | `ntn api v1/search -X POST -d '<json>'`                                                       |
| Read page Markdown       | `ntn pages get <id>`                                                                          |
| Update title (raw API)   | `ntn api v1/pages/<id> -X PATCH -d '{"properties":{"title":…}}'`                              |
| Update body              | `ntn pages update <id> --content '<markdown>'`                                                |

The response of `ntn api v1/search` is the raw Notion API JSON:
`{ object: "list", results: [Page], has_more, next_cursor }`. The
plasmoid does **not** paginate; if `has_more` is true a warning is
logged in the diagnostic overlay.

For the title field, the page object stores it in
`properties[<the title property's name>].title` (an array of rich-text
runs). `NotionStore._normalize()` walks the properties dict for the
first property with `type === "title"` and concatenates the
`plain_text` of each run.

## GitHub Projects (V2) — GraphQL v4

Base: `https://api.github.com/graphql`.
Auth: `Authorization: Bearer <plasmoid.configuration.ghToken>`.

PAT scopes required: `project, read:org, repo` (classic), or
fine-grained with "Projects: read" + "Issues: read".

`GhStore.qml` posts a single GraphQL query selecting the project, its
items (paginated up to `ghMaxResults`), and each item's content
(Issue / PullRequest / DraftIssue) plus the value of the `Status`
single-select field (or `ghStatusField` if customised).

The plasmoid is read-only; no mutations.

## ntn auth model — important caveat

`ntn login` writes a session token to `~/.config/notion/`. That file
is what the plasmoid relies on. If you run `ntn login` from a
different `$HOME` (e.g. an SSH session) the plasmoidshell process
might not see the same config. When that happens the diagnostic
overlay shows `Not logged in / 401` and the user has to run
`ntn login` from their actual desktop session.

Alternatively, set `NOTION_API_TOKEN=secret_…` in `~/.profile` —
`ntn` picks it up without `ntn login`.
