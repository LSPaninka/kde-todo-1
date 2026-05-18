/*
 * Database.qml
 *
 * SQLite-backed persistence using QtQuick.LocalStorage 2.15. This module
 * ships with Qt 5 and is built on top of SQLite, so all writes are
 * properly synced (full ACID), atomic and durable across reboots.
 *
 * The DB file lives at:
 *   ~/.local/share/KDE/plasmashell/QML/OfflineStorage/Databases/<hash>.sqlite
 * The hash is the MD5 of the database name; an .ini next to the file
 * records the original name. See docs/PERSISTENCE.md for how to find
 * it and how to back it up.
 */

import QtQuick 2.15
// 2.0 is the stable URI; LocalStorage doesn't bump its version with Qt
// releases, so this import is the most portable across distros.
import QtQuick.LocalStorage 2.0 as LS

QtObject {
    id: db

    property var _conn: null
    property bool ready: false

    // ------------------------------------------------------------------
    // Lifecycle
    // ------------------------------------------------------------------

    function init() {
        if (ready) return;
        try {
            // Empty version string opens any existing DB without a strict
            // version check — we manage migrations ourselves via the
            // schema_version table below.
            _conn = LS.LocalStorage.openDatabaseSync(
                "CategorizedToDo",
                "",
                "Categorized ToDo plasmoid data",
                5000000          // estimated max size (5 MB)
            );
            _migrate();
            ready = true;
        } catch (e) {
            console.warn("Database.init failed:", e);
            ready = false;
        }
    }

    function _migrate() {
        _conn.transaction(function(tx) {
            tx.executeSql(
                "CREATE TABLE IF NOT EXISTS schema_version (v INTEGER NOT NULL)");

            var rs = tx.executeSql("SELECT v FROM schema_version");
            var v = rs.rows.length > 0 ? rs.rows.item(0).v : 0;

            if (v < 1) {
                tx.executeSql(
                    "CREATE TABLE IF NOT EXISTS tasks (" +
                    "  id INTEGER PRIMARY KEY," +
                    "  title TEXT NOT NULL," +
                    "  description TEXT NOT NULL DEFAULT ''," +
                    "  category INTEGER NOT NULL DEFAULT 0," +
                    "  priority TEXT NOT NULL DEFAULT 'M'," +
                    "  done INTEGER NOT NULL DEFAULT 0," +
                    "  archived INTEGER NOT NULL DEFAULT 0," +
                    "  created_at INTEGER NOT NULL DEFAULT 0," +
                    "  archived_at INTEGER NOT NULL DEFAULT 0" +
                    ")");
                tx.executeSql(
                    "CREATE TABLE IF NOT EXISTS subtasks (" +
                    "  id INTEGER PRIMARY KEY," +
                    "  task_id INTEGER NOT NULL," +
                    "  title TEXT NOT NULL," +
                    "  priority TEXT NOT NULL DEFAULT 'M'," +
                    "  done INTEGER NOT NULL DEFAULT 0," +
                    "  position INTEGER NOT NULL DEFAULT 0" +
                    ")");
                tx.executeSql(
                    "CREATE INDEX IF NOT EXISTS idx_subtasks_task ON subtasks(task_id)");
                tx.executeSql(
                    "CREATE INDEX IF NOT EXISTS idx_tasks_archived ON tasks(archived)");
                tx.executeSql(
                    "CREATE INDEX IF NOT EXISTS idx_tasks_category ON tasks(category)");
                tx.executeSql(
                    "CREATE TABLE IF NOT EXISTS settings (" +
                    "  key TEXT PRIMARY KEY," +
                    "  value TEXT NOT NULL" +
                    ")");
                tx.executeSql(
                    "CREATE TABLE IF NOT EXISTS jira_cache (" +
                    "  issue_key TEXT PRIMARY KEY," +
                    "  data TEXT NOT NULL," +
                    "  fetched_at INTEGER NOT NULL" +
                    ")");

                if (rs.rows.length > 0) {
                    tx.executeSql("UPDATE schema_version SET v=1");
                } else {
                    tx.executeSql("INSERT INTO schema_version (v) VALUES (1)");
                }
                v = 1;
            }
            if (v < 2) {
                tx.executeSql(
                    "CREATE TABLE IF NOT EXISTS gh_cache (" +
                    "  item_id TEXT PRIMARY KEY," +
                    "  data TEXT NOT NULL," +
                    "  fetched_at INTEGER NOT NULL" +
                    ")");
                tx.executeSql("UPDATE schema_version SET v=2");
                v = 2;
            }
            // Future migrations: bump v and add ALTER TABLE / new tables.
        });
    }

    // ------------------------------------------------------------------
    // Settings (key/value table). Used as a fallback persistence layer
    // for things that should survive a Plasmoid.configuration loss
    // (Jira credentials, etc.).
    // ------------------------------------------------------------------

    function getSetting(key, fallback) {
        if (!ready) return fallback;
        var out = fallback;
        _conn.readTransaction(function(tx) {
            var rs = tx.executeSql("SELECT value FROM settings WHERE key=?", [key]);
            if (rs.rows.length > 0) out = rs.rows.item(0).value;
        });
        return out;
    }

    function setSetting(key, value) {
        if (!ready) return;
        _conn.transaction(function(tx) {
            tx.executeSql(
                "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
                [key, String(value === undefined || value === null ? "" : value)]);
        });
    }

    // ------------------------------------------------------------------
    // Tasks
    // ------------------------------------------------------------------

    function loadAllTasks() {
        var result = { active: [], archived: [], maxId: 0 };
        if (!ready) return result;
        _conn.readTransaction(function(tx) {
            var rs = tx.executeSql("SELECT * FROM tasks ORDER BY id");
            for (var i = 0; i < rs.rows.length; i++) {
                var row = rs.rows.item(i);
                var task = _rowToTask(row);
                if (row.id > result.maxId) result.maxId = row.id;

                var sr = tx.executeSql(
                    "SELECT * FROM subtasks WHERE task_id=? ORDER BY position, id",
                    [task.id]);
                for (var j = 0; j < sr.rows.length; j++) {
                    var srow = sr.rows.item(j);
                    task.subtasks.push({
                        id: srow.id,
                        title: srow.title,
                        priority: srow.priority,
                        done: srow.done !== 0
                    });
                    if (srow.id > result.maxId) result.maxId = srow.id;
                }

                if (row.archived !== 0) result.archived.push(task);
                else result.active.push(task);
            }
        });
        // archived oldest-first by id; the UI prefers newest first.
        result.archived.reverse();
        return result;
    }

    function _rowToTask(row) {
        return {
            id: row.id,
            title: row.title,
            description: row.description || "",
            category: row.category | 0,
            priority: row.priority || "M",
            done: row.done !== 0,
            archivedAt: row.archived_at | 0,
            createdAt: row.created_at | 0,
            subtasks: []
        };
    }

    // Save the whole task atomically (its row + subtasks). isArchived
    // controls the `archived` flag on the tasks row.
    function saveTask(t, isArchived) {
        if (!ready) return;
        _conn.transaction(function(tx) {
            tx.executeSql(
                "INSERT OR REPLACE INTO tasks " +
                "(id, title, description, category, priority, done, archived, created_at, archived_at) " +
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                [
                    t.id,
                    t.title || "",
                    t.description || "",
                    t.category | 0,
                    t.priority || "M",
                    t.done ? 1 : 0,
                    isArchived ? 1 : 0,
                    t.createdAt | 0,
                    t.archivedAt | 0
                ]);
            tx.executeSql("DELETE FROM subtasks WHERE task_id=?", [t.id]);
            var subs = t.subtasks || [];
            for (var i = 0; i < subs.length; i++) {
                var s = subs[i];
                tx.executeSql(
                    "INSERT INTO subtasks (id, task_id, title, priority, done, position) " +
                    "VALUES (?, ?, ?, ?, ?, ?)",
                    [s.id, t.id, s.title || "", s.priority || "M", s.done ? 1 : 0, i]);
            }
        });
    }

    function deleteTask(id) {
        if (!ready) return;
        _conn.transaction(function(tx) {
            tx.executeSql("DELETE FROM subtasks WHERE task_id=?", [id]);
            tx.executeSql("DELETE FROM tasks WHERE id=?", [id]);
        });
    }

    function clearArchive() {
        if (!ready) return;
        _conn.transaction(function(tx) {
            tx.executeSql(
                "DELETE FROM subtasks WHERE task_id IN " +
                "(SELECT id FROM tasks WHERE archived=1)");
            tx.executeSql("DELETE FROM tasks WHERE archived=1");
        });
    }

    // Bulk update categories (used when categoryCount shrinks).
    function reassignCategories(fromIndexInclusive, newIndex) {
        if (!ready) return;
        _conn.transaction(function(tx) {
            tx.executeSql(
                "UPDATE tasks SET category=? WHERE category >= ?",
                [newIndex | 0, fromIndexInclusive | 0]);
        });
    }

    // ------------------------------------------------------------------
    // Jira cache
    // ------------------------------------------------------------------

    function saveJiraIssues(issues, fetchedAt) {
        if (!ready) return;
        _conn.transaction(function(tx) {
            tx.executeSql("DELETE FROM jira_cache");
            for (var i = 0; i < issues.length; i++) {
                var iss = issues[i];
                tx.executeSql(
                    "INSERT INTO jira_cache (issue_key, data, fetched_at) VALUES (?, ?, ?)",
                    [iss.key || ("?" + i), JSON.stringify(iss), fetchedAt | 0]);
            }
        });
    }

    function loadJiraIssues() {
        var out = { issues: [], fetchedAt: 0 };
        if (!ready) return out;
        _conn.readTransaction(function(tx) {
            var rs = tx.executeSql("SELECT data, fetched_at FROM jira_cache");
            for (var i = 0; i < rs.rows.length; i++) {
                var row = rs.rows.item(i);
                try {
                    out.issues.push(JSON.parse(row.data));
                    if (row.fetched_at > out.fetchedAt) out.fetchedAt = row.fetched_at;
                } catch (e) { /* skip malformed entry */ }
            }
        });
        return out;
    }

    // ------------------------------------------------------------------
    // GitHub Projects cache
    // ------------------------------------------------------------------

    function saveGhItems(items, fetchedAt) {
        if (!ready) return;
        _conn.transaction(function(tx) {
            tx.executeSql("DELETE FROM gh_cache");
            for (var i = 0; i < items.length; i++) {
                var it = items[i];
                tx.executeSql(
                    "INSERT INTO gh_cache (item_id, data, fetched_at) VALUES (?, ?, ?)",
                    [it.id || ("?" + i), JSON.stringify(it), fetchedAt | 0]);
            }
        });
    }

    function loadGhItems() {
        var out = { items: [], fetchedAt: 0 };
        if (!ready) return out;
        _conn.readTransaction(function(tx) {
            var rs = tx.executeSql("SELECT data, fetched_at FROM gh_cache");
            for (var i = 0; i < rs.rows.length; i++) {
                var row = rs.rows.item(i);
                try {
                    out.items.push(JSON.parse(row.data));
                    if (row.fetched_at > out.fetchedAt) out.fetchedAt = row.fetched_at;
                } catch (e) { /* skip malformed entry */ }
            }
        });
        return out;
    }
}
