/*
 * Database.vala — SQLite persistence (ported from Database.qml).
 *
 * Uses the sqlite3 C library directly (synchronous, ACID). The DB file lives
 * at $XDG_DATA_HOME/categorized-todo/todo.sqlite. Schema is versioned in the
 * schema_version table and migrated in _migrate(); bump the version and add a
 * new block when the schema changes.
 *
 * Tables: tasks, subtasks, settings, jira_cache, gh_cache, schema_version.
 */

namespace Ct {

    public class Database : Object {
        private Sqlite.Database db;
        public bool ready { get; private set; default = false; }
        public string path { get; private set; }

        public Database () {
            var dir = Path.build_filename (Environment.get_user_data_dir (), "categorized-todo");
            try {
                File.new_for_path (dir).make_directory_with_parents ();
            } catch (Error e) {
                if (!(e is IOError.EXISTS))
                    warning ("Could not create data dir: %s", e.message);
            }
            path = Path.build_filename (dir, "todo.sqlite");

            int rc = Sqlite.Database.open_v2 (
                path, out db,
                Sqlite.OPEN_READWRITE | Sqlite.OPEN_CREATE);
            if (rc != Sqlite.OK) {
                warning ("Cannot open database %s: %s", path, db.errmsg ());
                return;
            }
            db.exec ("PRAGMA journal_mode=WAL;");
            db.exec ("PRAGMA foreign_keys=ON;");
            _migrate ();
            ready = true;
        }

        private void _exec (string sql) {
            string errmsg;
            int rc = db.exec (sql, null, out errmsg);
            if (rc != Sqlite.OK)
                warning ("SQL error: %s (%s)", errmsg, sql);
        }

        private void _migrate () {
            _exec ("CREATE TABLE IF NOT EXISTS schema_version (v INTEGER NOT NULL)");
            int v = 0;
            Sqlite.Statement st;
            if (db.prepare_v2 ("SELECT v FROM schema_version", -1, out st) == Sqlite.OK) {
                if (st.step () == Sqlite.ROW) v = st.column_int (0);
                else v = -1; // empty table
            }
            bool had_row = (v >= 0);
            if (v < 1) {
                _exec ("""CREATE TABLE IF NOT EXISTS tasks (
                    id INTEGER PRIMARY KEY,
                    title TEXT NOT NULL,
                    description TEXT NOT NULL DEFAULT '',
                    category INTEGER NOT NULL DEFAULT 0,
                    priority TEXT NOT NULL DEFAULT 'M',
                    done INTEGER NOT NULL DEFAULT 0,
                    archived INTEGER NOT NULL DEFAULT 0,
                    created_at INTEGER NOT NULL DEFAULT 0,
                    archived_at INTEGER NOT NULL DEFAULT 0,
                    notion_page_id TEXT NOT NULL DEFAULT '',
                    updated_at INTEGER NOT NULL DEFAULT 0,
                    notion_last_edited TEXT NOT NULL DEFAULT '',
                    notion_synced_at INTEGER NOT NULL DEFAULT 0,
                    jira_key TEXT NOT NULL DEFAULT ''
                )""");
                _exec ("""CREATE TABLE IF NOT EXISTS subtasks (
                    id INTEGER PRIMARY KEY,
                    task_id INTEGER NOT NULL,
                    title TEXT NOT NULL,
                    priority TEXT NOT NULL DEFAULT 'M',
                    done INTEGER NOT NULL DEFAULT 0,
                    position INTEGER NOT NULL DEFAULT 0
                )""");
                _exec ("CREATE INDEX IF NOT EXISTS idx_subtasks_task ON subtasks(task_id)");
                _exec ("CREATE INDEX IF NOT EXISTS idx_tasks_archived ON tasks(archived)");
                _exec ("CREATE INDEX IF NOT EXISTS idx_tasks_category ON tasks(category)");
                _exec ("CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)");
                _exec ("CREATE TABLE IF NOT EXISTS jira_cache (issue_key TEXT PRIMARY KEY, data TEXT NOT NULL, fetched_at INTEGER NOT NULL)");
                _exec ("CREATE TABLE IF NOT EXISTS gh_cache (item_id TEXT PRIMARY KEY, data TEXT NOT NULL, fetched_at INTEGER NOT NULL)");
                if (had_row) _exec ("UPDATE schema_version SET v=1");
                else _exec ("INSERT INTO schema_version (v) VALUES (1)");
            }
            // Idempotent column upgrades for DBs created by an earlier build.
            // (tasks already carries the Notion columns in the v1 CREATE.)
            _ensure_column ("tasks", "jira_key", "TEXT NOT NULL DEFAULT ''");
        }

        // Add `col` to `table` only if it's missing (safe to call every start).
        private void _ensure_column (string table, string col, string def_sql) {
            Sqlite.Statement st;
            if (db.prepare_v2 ("PRAGMA table_info(" + table + ")", -1, out st) != Sqlite.OK) return;
            bool found = false;
            while (st.step () == Sqlite.ROW) {
                if (st.column_text (1) == col) { found = true; break; }
            }
            if (!found)
                _exec ("ALTER TABLE %s ADD COLUMN %s %s".printf (table, col, def_sql));
        }

        // ---- helpers ----------------------------------------------------
        private static string s (Sqlite.Statement st, int col) {
            string? t = st.column_text (col);
            return t ?? "";
        }

        // ---- Settings k/v ----------------------------------------------
        public string get_setting (string key, string fallback) {
            if (!ready) return fallback;
            Sqlite.Statement st;
            if (db.prepare_v2 ("SELECT value FROM settings WHERE key=?", -1, out st) != Sqlite.OK)
                return fallback;
            st.bind_text (1, key);
            if (st.step () == Sqlite.ROW) return s (st, 0);
            return fallback;
        }

        public void set_setting (string key, string value) {
            if (!ready) return;
            Sqlite.Statement st;
            db.prepare_v2 ("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)", -1, out st);
            st.bind_text (1, key);
            st.bind_text (2, value);
            st.step ();
        }

        // ---- Tasks ------------------------------------------------------
        public class LoadResult {
            public Gee.ArrayList<Task> active = new Gee.ArrayList<Task> ();
            public Gee.ArrayList<Task> archived = new Gee.ArrayList<Task> ();
            public int64 max_id = 0;
        }

        public LoadResult load_all_tasks () {
            var res = new LoadResult ();
            if (!ready) return res;

            Sqlite.Statement st;
            db.prepare_v2 ("SELECT * FROM tasks ORDER BY id", -1, out st);
            // Column order is stable per the CREATE above. Key by string
            // because Gee's HashMap<int64?,…> compares boxed pointers, not
            // values, which silently breaks lookups.
            var by_id = new Gee.HashMap<string, Task> ();
            var order = new Gee.ArrayList<Task> ();
            while (st.step () == Sqlite.ROW) {
                var t = new Task ();
                int ncol = st.column_count ();
                for (int c = 0; c < ncol; c++) {
                    string name = st.column_name (c);
                    switch (name) {
                        case "id": t.id = st.column_int64 (c); break;
                        case "title": t.title = s (st, c); break;
                        case "description": t.description = s (st, c); break;
                        case "category": t.category = st.column_int (c); break;
                        case "priority": t.priority = s (st, c); break;
                        case "done": t.done = st.column_int (c) != 0; break;
                        case "created_at": t.created_at = st.column_int64 (c); break;
                        case "archived_at": t.archived_at = st.column_int64 (c); break;
                        case "notion_page_id": t.notion_page_id = s (st, c); break;
                        case "updated_at": t.updated_at = st.column_int64 (c); break;
                        case "notion_last_edited": t.notion_last_edited = s (st, c); break;
                        case "notion_synced_at": t.notion_synced_at = st.column_int64 (c); break;
                        case "jira_key": t.jira_key = s (st, c); break;
                    }
                }
                bool arch = false;
                // Re-read archived flag (not a Task property).
                for (int c = 0; c < ncol; c++)
                    if (st.column_name (c) == "archived") arch = st.column_int (c) != 0;
                if (t.id > res.max_id) res.max_id = t.id;
                by_id.set (t.id.to_string (), t);
                order.add (t);
                if (arch) res.archived.add (t);
                else res.active.add (t);
            }

            Sqlite.Statement ss;
            db.prepare_v2 ("SELECT id, task_id, title, priority, done FROM subtasks ORDER BY task_id, position, id", -1, out ss);
            while (ss.step () == Sqlite.ROW) {
                int64 sid = ss.column_int64 (0);
                int64 tid = ss.column_int64 (1);
                var owner = by_id.get (tid.to_string ());
                if (owner == null) continue;
                owner.subtasks.add (new Subtask.with (sid, s (ss, 2), s (ss, 3), ss.column_int (4) != 0));
                if (sid > res.max_id) res.max_id = sid;
            }

            // archived: UI prefers newest-first.
            res.archived.sort ((a, b) => (int) (b.id - a.id));
            return res;
        }

        public void save_task (Task t, bool is_archived) {
            if (!ready) return;
            Sqlite.Statement st;
            db.prepare_v2 (
                "INSERT OR REPLACE INTO tasks " +
                "(id, title, description, category, priority, done, archived, created_at, archived_at, notion_page_id, updated_at, notion_last_edited, notion_synced_at, jira_key) " +
                "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)", -1, out st);
            st.bind_int64 (1, t.id);
            st.bind_text (2, t.title);
            st.bind_text (3, t.description);
            st.bind_int (4, t.category);
            st.bind_text (5, t.priority);
            st.bind_int (6, t.done ? 1 : 0);
            st.bind_int (7, is_archived ? 1 : 0);
            st.bind_int64 (8, t.created_at);
            st.bind_int64 (9, t.archived_at);
            st.bind_text (10, t.notion_page_id);
            st.bind_int64 (11, t.updated_at);
            st.bind_text (12, t.notion_last_edited);
            st.bind_int64 (13, t.notion_synced_at);
            st.bind_text (14, t.jira_key);
            st.step ();

            Sqlite.Statement del;
            db.prepare_v2 ("DELETE FROM subtasks WHERE task_id=?", -1, out del);
            del.bind_int64 (1, t.id);
            del.step ();

            int pos = 0;
            foreach (var sub in t.subtasks) {
                Sqlite.Statement ins;
                db.prepare_v2 ("INSERT INTO subtasks (id, task_id, title, priority, done, position) VALUES (?,?,?,?,?,?)", -1, out ins);
                ins.bind_int64 (1, sub.id);
                ins.bind_int64 (2, t.id);
                ins.bind_text (3, sub.title);
                ins.bind_text (4, sub.priority);
                ins.bind_int (5, sub.done ? 1 : 0);
                ins.bind_int (6, pos++);
                ins.step ();
            }
        }

        public void delete_task (int64 id) {
            if (!ready) return;
            Sqlite.Statement st;
            db.prepare_v2 ("DELETE FROM subtasks WHERE task_id=?", -1, out st);
            st.bind_int64 (1, id);
            st.step ();
            Sqlite.Statement st2;
            db.prepare_v2 ("DELETE FROM tasks WHERE id=?", -1, out st2);
            st2.bind_int64 (1, id);
            st2.step ();
        }

        public void clear_archive () {
            if (!ready) return;
            _exec ("DELETE FROM subtasks WHERE task_id IN (SELECT id FROM tasks WHERE archived=1)");
            _exec ("DELETE FROM tasks WHERE archived=1");
        }

        // ---- Jira cache -------------------------------------------------
        public void save_jira_json (string[] json_rows, string[] keys, int64 fetched_at) {
            if (!ready) return;
            _exec ("DELETE FROM jira_cache");
            for (int i = 0; i < json_rows.length; i++) {
                Sqlite.Statement st;
                db.prepare_v2 ("INSERT OR REPLACE INTO jira_cache (issue_key, data, fetched_at) VALUES (?,?,?)", -1, out st);
                st.bind_text (1, keys[i]);
                st.bind_text (2, json_rows[i]);
                st.bind_int64 (3, fetched_at);
                st.step ();
            }
        }

        public Gee.ArrayList<string> load_jira_json (out int64 fetched_at) {
            fetched_at = 0;
            var rows = new Gee.ArrayList<string> ();
            if (!ready) return rows;
            Sqlite.Statement st;
            db.prepare_v2 ("SELECT data, fetched_at FROM jira_cache", -1, out st);
            while (st.step () == Sqlite.ROW) {
                rows.add (s (st, 0));
                int64 f = st.column_int64 (1);
                if (f > fetched_at) fetched_at = f;
            }
            return rows;
        }

        // ---- GitHub cache ----------------------------------------------
        public void save_gh_json (string[] json_rows, string[] ids, int64 fetched_at) {
            if (!ready) return;
            _exec ("DELETE FROM gh_cache");
            for (int i = 0; i < json_rows.length; i++) {
                Sqlite.Statement st;
                db.prepare_v2 ("INSERT OR REPLACE INTO gh_cache (item_id, data, fetched_at) VALUES (?,?,?)", -1, out st);
                st.bind_text (1, ids[i]);
                st.bind_text (2, json_rows[i]);
                st.bind_int64 (3, fetched_at);
                st.step ();
            }
        }

        public Gee.ArrayList<string> load_gh_json (out int64 fetched_at) {
            fetched_at = 0;
            var rows = new Gee.ArrayList<string> ();
            if (!ready) return rows;
            Sqlite.Statement st;
            db.prepare_v2 ("SELECT data, fetched_at FROM gh_cache", -1, out st);
            while (st.step () == Sqlite.ROW) {
                rows.add (s (st, 0));
                int64 f = st.column_int64 (1);
                if (f > fetched_at) fetched_at = f;
            }
            return rows;
        }
    }
}
