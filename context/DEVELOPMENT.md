# Development guide

Practical info for working on either plasmoid locally.

## Prerequisites

- Kubuntu 24.04 (or any distro with KDE Plasma 5.27 + Qt 5.15).
- `kpackagetool5` (or `plasmapkg2` as fallback). Both ship with the
  `plasma-framework` package on Debian/Ubuntu.
- QML modules — usually already present, but each plasmoid's
  `install.sh` checks and offers `apt install`:
  - `qml-module-qtquick-localstorage` (Categorized ToDo's SQLite)
  - `qml-module-qtquick-controls2` (almost always installed)
  - `qml-module-qt-labs-platform` (for native dialogs)
  - `qml-module-qtquick-shapes` (for `RingGauge` in the worklog
    plasmoid, if the system doesn't ship it with Qt 5.15)

## Install / upgrade / uninstall

Each plasmoid has its own `install.sh` wrapping `kpackagetool5`:

```bash
# Categorized ToDo
./install.sh                # install or upgrade
./install.sh --dev          # symlink package/ → ~/.local/share/plasma/plasmoids/
./install.sh --no-deps      # skip the apt-package dependency probe
./install.sh --uninstall

# Worklog Calendar (no --no-deps flag; same other modes)
cd worklog-plasmoid
./install.sh
```

After install, reload Plasma to pick up the new package:

```bash
kquitapp5 plasmashell && kstart5 plasmashell
```

Find the new widget under *Add Widgets → ToDo / Worklog*.

## Dev mode — live iteration

`./install.sh --dev` symlinks the `package/` folder into
`~/.local/share/plasma/plasmoids/<plugin-id>/`. After that, any edit
to a `.qml` file becomes live after `kquitapp5 plasmashell && kstart5
plasmashell`. You don't need to reinstall on every change.

A faster cycle for very small changes: right-click the plasmoid on
the panel → *Reload* (if exposed by your panel theme), or unpin and
re-pin the widget.

`metadata.desktop`'s `X-KDE-PluginInfo-Version` only matters for
`kpackagetool5 --upgrade`. In `--dev` mode the symlink bypasses
versioning entirely.

## Debug logs

The popular invocation:

```bash
journalctl --user -f -u plasma-plasmashell.service
```

Grep for store-specific tags:

```bash
journalctl --user -f _COMM=plasmashell | grep -iE '\[(JiraStore|GhStore|NotionStore|JiraWorklog|Clockify)\]'
```

Each plasmoid also has an **in-popup diagnostic overlay** (the ⓘ
button in the header). It surfaces every request and response, even
when the per-store `*Debug` config toggle is off (the toggle only
controls `console.log` mirroring; the overlay's log buffer is always
populated).

If `journalctl` returns nothing for `plasmashell`, the service might
be running as a transient session unit. Try the broader form:

```bash
journalctl --user -f _COMM=plasmashell
```

or just watch every QML console output:

```bash
plasmashell --replace 2>&1 | grep -iE 'qml:|error|warn'
```

## Inspecting the SQLite DB (ToDo plasmoid)

```bash
DIR=~/.local/share/KDE/plasmashell/QML/OfflineStorage/Databases
DB=$(grep -l 'CategorizedToDo' "$DIR"/*.ini | sed 's/\.ini$/.sqlite/')
sqlite3 "$DB" '.tables'
sqlite3 "$DB" 'SELECT * FROM tasks LIMIT 5;'
sqlite3 "$DB" 'SELECT k, length(v) FROM settings;'
```

## Inspecting the KConfig file

```bash
cat ~/.config/categorizedtodorc
```

Both plasmoids write here. Be careful — if Plasma is running, edits
might be overwritten on the next debounce write. Stop plasmashell
first if hand-editing:

```bash
kquitapp5 plasmashell
$EDITOR ~/.config/categorizedtodorc
kstart5 plasmashell
```

## Bumping versions and releasing

1. Edit code.
2. Bump `X-KDE-PluginInfo-Version` in the relevant
   `package/metadata.desktop`.
3. Append a section to the worklog plasmoid's `CHANGELOG.md` (the
   ToDo plasmoid has no changelog as of this writing).
4. Commit and push to the user's working branch.
5. Reinstall: `./install.sh && kquitapp5 plasmashell && kstart5
   plasmashell`.

`kpackagetool5 --upgrade` will replace the installed package with
the new version. Settings are preserved (they live in
`~/.config/categorizedtodorc`, not inside the package).

## Branch convention

The user works on a single feature branch (currently `claude/github-
projects-integration-7Nm8D`). Don't push to `main`. Don't open PRs
unless explicitly asked.

## Files NOT to touch

- `*.plasmoid` zips at the repo root — stale, ignore.
- `.git/`, `.gitignore` — standard.
- `~/.config/categorizedtodorc` — only via the configuration dialog
  or hand-edits with plasmashell stopped.

## Common debugging recipes

### "I changed config but the UI didn't update"

KConfig writes are debounced. If the change is in a kcfg the user
just set via the dialog, give it ~10 s or reload plasmashell. For
network-triggered side-effects (refreshing a fetched list), look for
the matching `Connections { target: plasmoid.configuration }` block
that should trigger the re-fetch — it might be missing.

### "Blocks are stuck at the wrong size after dragging"

A previous version of `WorklogEntry.qml` resized on hover (no
`pressed` guard). If you see this regression, check that
`onPositionChanged` starts with `if (!pressed) return;`. The fix
unbreaks future hovers but already-corrupted blocks need a sync (↻)
to recreate their bindings.

### "Sprint gauge says 0%"

Open the diagnostic overlay (ⓘ) in the popup and look for `[JiraWorklog]
Sprint strategy:`. If it says `subtask-customfield` and "0 subtarea(s)
recibidas", the JQL `issuetype in subTaskIssueTypes() AND assignee =
currentUser()` returned empty — try a JQL search in Jira's UI for
sanity. If subtarea returns results but `Ningún sprint activo en el
campo`, the `customfield_NNNNN` id is different on your instance —
edit `worklogSprintField`.

### "Clockify 403 on /workspaces/X/projects"

You typed the workspace **name** instead of the **24-char hex Object
ID**. Hit the *Limpiar* button next to the field, save; the plasmoid
will auto-resolve and write the correct id on the next sync.

### "Notion mode silent / no pages"

Open a terminal and run `ntn pages list` or `ntn api v1/search -X POST
-d '{"page_size":5}'`. If it works there but not in the plasmoid, set
the absolute path to `ntn` in the Notion config tab (Plasma may not
have the same `$PATH` as your shell).
