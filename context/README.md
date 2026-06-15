# Context for Claude Code

Entry point for any Claude Code instance picking up this repo cold. The
files in this folder are intentionally **dense** — they describe what
the project is, how it's structured, which APIs it touches, how to run
it locally, and where to look first.

## What this repo contains

Two **KDE Plasma 5.27 / Qt 5.15** plasmoids (desktop / panel widgets),
both pure QML, written for Kubuntu 24.04.

| Package directory   | Plugin id                            | One-line description |
| ------------------- | ------------------------------------ | -------------------- |
| `package/`          | `org.kde.plasma.categorizedtodo`     | Multi-mode "Categorized ToDo": local task list, Jira issues, GitHub Projects items, Notion pages. Switchable between modes. |
| `worklog-plasmoid/` | `org.kde.plasma.jiraworklog`         | Weekly calendar of worklogs from Jira and/or Clockify. Drag-to-create, drag-to-move (cross-day), edge-resize, sprint gauges. |

Both share Jira credentials by writing to the same KConfig file
(`~/.config/categorizedtodorc`). The worklog plasmoid also reads them
from there.

## Reading order if you're new here

1. **`CLAUDE.md`** — the canonical, comprehensive context dump. Read
   this first; everything else is supplementary.
2. **`APIS.md`** — every REST endpoint hit and how the responses are
   parsed.
3. **`CONFIGURATION.md`** — all KCfg entries listed with their
   defaults and what they affect.
4. **`DEVELOPMENT.md`** — install/upgrade/uninstall flow, dev-mode
   symlink, debug logs, common gotchas.

## House rules

- Don't migrate to KF6 / Qt 6 / Plasma 6 unless explicitly asked.
- Don't add native code (C++ / Python plugins) — pure QML.
- The deliverables are the `package/` folders inside each plasmoid
  directory. The `*.plasmoid` zips in the repo root, if any, are stale.
- `metadata.desktop`'s `X-KDE-PluginInfo-Version` must be bumped on
  every user-visible release so `kpackagetool5 --upgrade` reinstalls.
- The worklog plasmoid keeps a `CHANGELOG.md` next to its package;
  please keep it up to date.
