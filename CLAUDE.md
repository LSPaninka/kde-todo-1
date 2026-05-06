# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A KDE Plasma 5 plasmoid (`org.kde.plasma.categorizedtodo`) targeted at **Kubuntu 24.04 / Plasma 5.27 / Qt 5.15**. Pure QML — no native code, no external libraries beyond what ships with Plasma 5 + Qt 5.15 (`org.kde.plasma.*`, `org.kde.kirigami`, `QtQuick`, `QtQuick.Controls 2`, `QtQuick.Dialogs`, `QtQuick.LocalStorage`, `Qt.labs.platform`). README is authored in Spanish; UI strings are bilingual via `i18n`.

## Common commands

Install / develop / uninstall (all wrap `kpackagetool5` / `plasmapkg2`):

```bash
./install.sh              # install or upgrade for current user; checks QML deps
./install.sh --dev        # symlink package/ into ~/.local/share/plasma/plasmoids/ — recommended for iteration
./install.sh --no-deps    # skip the apt-based QML dependency check
./install.sh --uninstall
```

Reload Plasma after installing or after editing QML in dev mode:

```bash
kquitapp5 plasmashell && kstart5 plasmashell
```

Tail QML errors / Jira debug logs:

```bash
journalctl --user -f _COMM=plasmashell
journalctl --user -f _COMM=plasmashell | grep -i jirastore   # Jira fetch/parse traces (jiraDebug=true by default)
```

There is **no test suite, no linter, no build step** — `package/` is the deliverable. The `todo.plasmoid` file at the repo root is a stale prebuilt zip; the source of truth is `package/`.

## Architecture

### Two operating modes, one widget

`main.qml` is a thin dispatcher. `plasmoid.configuration.mode` selects between:

- **`todo`** — local list (`TodoView.qml`) backed by `TaskStore` + SQLite.
- **`jira`** — read-only (`JiraView.qml`) of issues from Jira Cloud REST v3, backed by `JiraStore` + SQLite cache.

Both `FullRepresentation.qml` (popup) and `CompactRepresentation.qml` (panel) branch on `mode`. The compact view shows per-category swatches with pending counts in both modes; clicking opens the popup.

### Stores own the state, views are dumb

`main.qml` instantiates one `Database`, one `TaskStore`, and one `JiraStore`, and injects them down through `store:` / `jira:` properties. Every QML view receives them as properties — they never reach for `plasmoid` or the DB themselves. Mutations go through store methods (`addTask`, `archiveTask`, `toggleSubtaskDone`, `fetch`, …); each store bumps a `version` int and emits `changed()` so QML bindings refresh. Plain JS arrays of plain objects are the in-memory model — there is no `ListModel`.

### Persistence: SQLite via QtQuick.LocalStorage

`Database.qml` wraps `QtQuick.LocalStorage 2.0` (synchronous, ACID, ships with Qt 5). The DB file lives at `~/.local/share/KDE/plasmashell/QML/OfflineStorage/Databases/<md5>.sqlite` (logical name `CategorizedToDo`). Tables: `tasks`, `subtasks`, `settings` (k/v fallback for credentials), `jira_cache`, `schema_version`. Schema migrations are gated on `schema_version.v` inside `_migrate()` — bump `v` and add a new `if (v < N)` block when changing schema.

Every store mutation commits inside `Database.transaction(...)` immediately — there is no debounce, no `flushNow()` queue (the function exists only as an API-compat no-op). `TaskStore.load()` is called once from `Component.onCompleted` and rebuilds the in-memory arrays from SQLite. Do **not** add a separate JSON-file path: previous JSON-file and `Plasmoid.configuration.tasksJson` backends were removed because `KConfigPropertyMap` debouncing and the `executable` data engine proved unreliable on the target setup (see `docs/PERSISTENCE.md`).

### Plasmoid.configuration vs SQLite

Schema is in `package/contents/config/main.xml` (KConfig XML). Use it for **widget configuration** (mode, category names/colors, popup size, panel layout, Jira JQL/refresh interval). Tasks and the Jira issue cache live in SQLite, **not** in `Plasmoid.configuration`.

**Jira credentials are mirrored to both layers.** `main.qml` wires `Connections { target: plasmoid.configuration }` so any change to `jiraSite/Email/Token/Jql` calls `_jira.persistCredentials()` to write through to SQLite. On startup `JiraStore.restoreCredentialsFromCache()` re-populates `Plasmoid.configuration` if Plasma has lost it. Keep this two-way mirror intact when touching credential fields.

### Configurable Jira categories

The Jira mode does not hardcode "To Do / In Progress / Done". Instead, parallel `StringList` entries in `main.xml` (`jiraCategoryNames`, `jiraCategoryColors`, `jiraCategoryTextColors`, `jiraCategoryFilterFields`, `jiraCategoryFilterValues`) drive up to 4 user-defined tabs/swatches. `jiraCategoryFilterFields[i]` is one of `statusCategory`, `issuetype`, `status`, `priority`, or empty (matches all). `jiraCategoryFilterValues[i]` uses `;` as the OR separator within an entry (because the outer list itself is comma-separated).

The matching `categoryNames`/`categoryColors`/`categoryCount` entries drive the ToDo mode tabs (1–4). When `categoryCount` shrinks, `TaskStore.reassignOutOfRangeCategories()` clamps existing tasks into the last surviving category — handle the same way for any new "shrink" path.

### QML module dependencies

`QtQuick.LocalStorage`, `QtQuick.Controls 2`, and `Qt.labs.platform` are imported but on Debian/Ubuntu often not installed by default. `install.sh` probes Qt's QML import paths for the `qmldir` files and offers `apt install qml-module-qtquick-localstorage qml-module-qtquick-controls2 qml-module-qt-labs-platform`. If you add a new QML import that isn't part of base Plasma 5, add it to `REQUIRED_QML_MODULES` in `install.sh`.

## Conventions worth knowing

- The repo is targeted at Plasma 5 (`X-Plasma-API=declarativeappletscript`, `kpackagetool5`). Don't migrate APIs to Plasma 6 / KF6 / Qt 6 unless explicitly asked.
- After every store mutation, call `_bump()` so QML bindings re-evaluate — the arrays are reassigned by reference, but `version` is the binding trigger.
- IDs are monotonically increasing integers issued from `TaskStore._nextId`, seeded from `MAX(id)` across both tasks and subtasks at load time.
- `metadata.desktop` carries the version (`X-KDE-PluginInfo-Version`) — bump it when releasing user-visible changes.
- Documentation source-of-truth: `README.md`, `docs/PERSISTENCE.md`, `docs/JIRA.md`. README is in Spanish.
