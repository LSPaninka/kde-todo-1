/*
 * NotionSyncStore.vala — two-way sync between the local ToDo list (TaskStore
 * + SQLite) and a Notion database over the official HTTP API
 * (api.notion.com/v1). Ported from NotionSyncStore.qml.
 *
 * Sync model (newest-wins, no deletions): each task maps to one Notion page.
 * New tasks on either side are created on the other; when a task changed on
 * both sides the most recently edited wins; deletions are never propagated.
 */

namespace Ct {

    private class ApiResult {
        public bool ok;
        public Json.Object? obj;
        public uint status;
        public string raw;
    }

    public class NotionSyncStore : Object {
        public Config config { get; construct; }
        public Database database { get; construct; }
        public TaskStore tasks { get; construct; }

        public bool loading { get; private set; default = false; }
        public string last_error { get; private set; default = ""; }
        public int64 last_synced_at { get; private set; default = 0; }
        public int version { get; private set; default = 0; }

        public string last_debug_log { get; private set; default = ""; }

        public signal void changed ();
        public signal void sync_finished (bool ok, int pulled, int pushed);

        private const string API_BASE = "https://api.notion.com/v1";
        private const string NOTION_VERSION = "2022-06-28";

        private Soup.Session session;
        private uint refresh_source = 0;

        public NotionSyncStore (Config config, Database database, TaskStore tasks) {
            Object (config: config, database: database, tasks: tasks);
        }

        construct {
            session = new Soup.Session ();
            session.timeout = 40;
        }

        public void init () { apply_refresh_schedule (); }

        private void bump () { version++; changed (); }

        public void apply_refresh_schedule () {
            if (refresh_source != 0) { Source.remove (refresh_source); refresh_source = 0; }
            int minutes = config.get_int ("notion-refresh-minutes");
            if (minutes > 0 && is_configured ())
                refresh_source = Timeout.add_seconds (minutes * 60, () => { sync.begin (); return Source.CONTINUE; });
        }

        public bool is_configured () {
            return token ().length > 0 && database_id ().length > 0;
        }
        private string token () { return config.get_string ("notion-api-token").strip (); }
        private string database_id () { return config.get_string ("notion-database-id").strip (); }
        private string parent_page_id () { return config.get_string ("notion-parent-page-id").strip (); }

        // ---- low-level HTTP --------------------------------------------
        private async ApiResult api (string method, string path, string? body) {
            var res = new ApiResult ();
            if (token ().length == 0) { res.ok = false; res.status = 0; res.raw = "no token"; return res; }
            var msg = new Soup.Message (method, API_BASE + path);
            msg.request_headers.append ("Authorization", "Bearer " + token ());
            msg.request_headers.append ("Notion-Version", NOTION_VERSION);
            msg.request_headers.append ("Accept", "application/json");
            if (body != null)
                msg.set_request_body_from_bytes ("application/json", new Bytes (body.data));
            try {
                var bytes = yield session.send_and_read_async (msg, Priority.DEFAULT, null);
                res.status = msg.status_code;
                res.raw = (string) bytes.get_data ();
                res.ok = (res.status >= 200 && res.status < 300);
                if (res.raw.length > 0) {
                    try {
                        var p = new Json.Parser (); p.load_from_data (res.raw);
                        if (p.get_root ().get_node_type () == Json.NodeType.OBJECT)
                            res.obj = p.get_root ().get_object ();
                    } catch (Error e) { }
                }
                if (!res.ok) {
                    string m = (res.obj != null && res.obj.has_member ("message"))
                               ? res.obj.get_string_member ("message") : "HTTP %u".printf (res.status);
                    _warn (method + " " + path + " -> %u: %s".printf (res.status, m));
                }
            } catch (Error e) {
                res.ok = false; res.status = 0; res.raw = "send() threw: " + e.message;
            }
            return res;
        }

        // ---- test connection -------------------------------------------
        public async bool test_connection (string token_in, out string message) {
            string tk = token_in.strip ();
            if (tk.length == 0) { message = "Completá el token antes de probar."; return false; }
            var msg = new Soup.Message ("GET", API_BASE + "/users/me");
            msg.request_headers.append ("Authorization", "Bearer " + tk);
            msg.request_headers.append ("Notion-Version", NOTION_VERSION);
            msg.request_headers.append ("Accept", "application/json");
            try {
                var bytes = yield session.send_and_read_async (msg, Priority.DEFAULT, null);
                if (msg.status_code == 200) {
                    string who = "OK";
                    try {
                        var p = new Json.Parser (); p.load_from_data ((string) bytes.get_data ());
                        var o = p.get_root ().get_object ();
                        if (o.has_member ("name")) who = o.get_string_member ("name");
                    } catch (Error e) { }
                    message = "OK — integración «%s» autenticada.".printf (who);
                    return true;
                } else if (msg.status_code == 401) {
                    message = "Token rechazado (HTTP 401). Revisá el secret de la integración.";
                    return false;
                }
                message = "HTTP %u".printf (msg.status_code);
                return false;
            } catch (Error e) {
                message = "Error de red: " + e.message;
                return false;
            }
        }

        // ---- create database -------------------------------------------
        public async bool create_database (out string result) {
            result = "";
            if (token ().length == 0) { result = "Falta el token de Notion."; return false; }
            string parent = parent_page_id ();
            if (parent.length == 0) { result = "Falta el ID de la página padre."; return false; }

            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("parent");
            b.begin_object ();
            b.set_member_name ("type"); b.add_string_value ("page_id");
            b.set_member_name ("page_id"); b.add_string_value (parent);
            b.end_object ();
            b.set_member_name ("title");
            b.begin_array ();
            b.begin_object ();
            b.set_member_name ("type"); b.add_string_value ("text");
            b.set_member_name ("text");
            b.begin_object (); b.set_member_name ("content"); b.add_string_value ("Categorized ToDo"); b.end_object ();
            b.end_object ();
            b.end_array ();
            b.set_member_name ("properties");
            b.begin_object ();
            _prop_def (b, "Name", "title");
            _prop_def (b, "Description", "rich_text");
            _prop_def (b, "Category", "number");
            b.set_member_name ("Priority");
            b.begin_object (); b.set_member_name ("select");
            b.begin_object (); b.set_member_name ("options");
            b.begin_array ();
            foreach (var p in PRIORITIES) { b.begin_object (); b.set_member_name ("name"); b.add_string_value (p); b.end_object (); }
            b.end_array (); b.end_object (); b.end_object ();
            _prop_def (b, "Done", "checkbox");
            _prop_def (b, "Archived", "checkbox");
            _prop_def (b, "Subtasks", "rich_text");
            _prop_def (b, "LocalId", "number");
            b.end_object ();
            b.end_object ();

            var gen = new Json.Generator (); gen.set_root (b.get_root ());
            var res = yield api ("POST", "/databases", gen.to_data (null));
            if (!res.ok || res.obj == null || !res.obj.has_member ("id")) {
                last_error = "No se pudo crear la base: " + (res.obj != null && res.obj.has_member ("message")
                              ? res.obj.get_string_member ("message") : "HTTP %u".printf (res.status));
                bump ();
                result = last_error;
                return false;
            }
            string id = res.obj.get_string_member ("id");
            config.set_string ("notion-database-id", id);
            apply_refresh_schedule ();
            bump ();
            result = id;
            return true;
        }

        private void _prop_def (Json.Builder b, string name, string kind) {
            b.set_member_name (name);
            b.begin_object ();
            b.set_member_name (kind);
            b.begin_object (); b.end_object ();
            b.end_object ();
        }

        // ---- sync -------------------------------------------------------
        public async bool sync () {
            var ts = new DateTime.now_local ().format ("%Y-%m-%d %H:%M:%S");
            _append_debug ("\n=== Notion sync %s ===\n".printf (ts));
            if (!is_configured ()) {
                last_error = "Notion no está configurado (token + base de datos).";
                _append_debug (last_error + "\n");
                bump (); sync_finished (false, 0, 0); return false;
            }
            if (loading) { _append_debug ("[abort] ya hay un sync en curso.\n"); return false; }

            loading = true; last_error = ""; bump ();

            var pages = new Gee.ArrayList<Json.Object> ();
            string err = "";
            bool ok = yield _query_all_pages (database_id (), pages, null, out err);
            if (!ok) {
                loading = false;
                last_error = "Error al consultar Notion: " + err;
                _append_debug ("[!] " + last_error + "\n");
                bump (); sync_finished (false, 0, 0); return false;
            }
            return yield _reconcile (pages);
        }

        private async bool _query_all_pages (string db_id, Gee.ArrayList<Json.Object> acc,
                                             string? cursor, out string err) {
            err = "";
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("page_size"); b.add_int_value (100);
            if (cursor != null) { b.set_member_name ("start_cursor"); b.add_string_value (cursor); }
            b.end_object ();
            var gen = new Json.Generator (); gen.set_root (b.get_root ());
            var res = yield api ("POST", "/databases/" + db_id + "/query", gen.to_data (null));
            if (!res.ok || res.obj == null) {
                err = (res.obj != null && res.obj.has_member ("message"))
                      ? res.obj.get_string_member ("message") : "HTTP %u".printf (res.status);
                return false;
            }
            if (res.obj.has_member ("results")) {
                var arr = res.obj.get_array_member ("results");
                for (uint i = 0; i < arr.get_length (); i++)
                    if (arr.get_element (i).get_node_type () == Json.NodeType.OBJECT)
                        acc.add (arr.get_object_element (i));
            }
            bool has_more = res.obj.has_member ("has_more") && res.obj.get_boolean_member ("has_more");
            if (has_more && res.obj.has_member ("next_cursor")
                && res.obj.get_member ("next_cursor").get_node_type () == Json.NodeType.VALUE) {
                string nc = res.obj.get_string_member ("next_cursor");
                return yield _query_all_pages (db_id, acc, nc, out err);
            }
            return true;
        }

        private async bool _reconcile (Gee.ArrayList<Json.Object> pages) {
            _append_debug ("reconcile: %d página(s) en Notion.\n".printf (pages.size));

            var snapshot = tasks.all_tasks_for_sync ();
            var local_by_page = new Gee.HashMap<string, Task> ();
            foreach (var lt in snapshot)
                if (lt.notion_page_id.length > 0) local_by_page.set (lt.notion_page_id, lt);

            int pulled = 0;
            var push_updates = new Gee.ArrayList<PushOp> ();

            foreach (var page in pages) {
                if (!page.has_member ("id")) continue;
                string pid = page.get_string_member ("id");
                var remote = _page_to_remote (page);
                string last_edited = page.has_member ("last_edited_time") ? page.get_string_member ("last_edited_time") : "";
                var local = local_by_page.has_key (pid) ? local_by_page.get (pid) : null;

                if (local == null) {
                    tasks.apply_remote_upsert (remote);
                    pulled++;
                    continue;
                }
                bool remote_changed = (last_edited != local.notion_last_edited);
                bool local_changed = tasks.notion_local_changed (local);
                if (remote_changed && local_changed) {
                    int64 remote_ms = _parse_iso_ms (last_edited);
                    if (remote_ms >= local.updated_at) { tasks.apply_remote_upsert (remote); pulled++; }
                    else push_updates.add (new PushOp (local.id, pid));
                } else if (remote_changed) {
                    tasks.apply_remote_upsert (remote); pulled++;
                } else if (local_changed) {
                    push_updates.add (new PushOp (local.id, pid));
                }
            }

            var push_creates = new Gee.ArrayList<int64?> ();
            foreach (var t in snapshot)
                if (t.notion_page_id.length == 0) push_creates.add (t.id);

            int pushed = 0;
            foreach (var op in push_updates)
                if (yield _push_update (op.task_id, op.page_id)) pushed++;
            foreach (var tid in push_creates)
                if (yield _push_create (tid)) pushed++;

            loading = false;
            last_synced_at = GLib.get_real_time () / 1000;
            _append_debug ("sync OK: %d traída(s), %d enviada(s).\n".printf (pulled, pushed));
            bump ();
            sync_finished (true, pulled, pushed);
            return true;
        }

        private async bool _push_update (int64 task_id, string page_id) {
            var t = tasks.get_any_task (task_id);
            if (t == null) return false;
            string body = _task_to_body (t, false);
            var res = yield api ("PATCH", "/pages/" + page_id, body);
            if (res.ok && res.obj != null) {
                string le = res.obj.has_member ("last_edited_time") ? res.obj.get_string_member ("last_edited_time") : "";
                tasks.mark_pushed (task_id, page_id, le);
                return true;
            }
            _warn ("push update falló para task %lld".printf (task_id));
            return false;
        }

        private async bool _push_create (int64 task_id) {
            var t = tasks.get_any_task (task_id);
            if (t == null) return false;
            string body = _task_to_body (t, true);
            var res = yield api ("POST", "/pages", body);
            if (res.ok && res.obj != null && res.obj.has_member ("id")) {
                string le = res.obj.has_member ("last_edited_time") ? res.obj.get_string_member ("last_edited_time") : "";
                tasks.mark_pushed (task_id, res.obj.get_string_member ("id"), le);
                return true;
            }
            _warn ("push create falló para task %lld".printf (task_id));
            return false;
        }

        // ---- mapping ----------------------------------------------------
        private string _task_to_body (Task t, bool with_parent) {
            var b = new Json.Builder ();
            b.begin_object ();
            if (with_parent) {
                b.set_member_name ("parent");
                b.begin_object (); b.set_member_name ("database_id"); b.add_string_value (database_id ()); b.end_object ();
            } else {
                b.set_member_name ("archived"); b.add_boolean_value (false);
            }
            b.set_member_name ("properties");
            b.begin_object ();
            _prop_title (b, "Name", t.title);
            _prop_rich (b, "Description", t.description);
            _prop_number (b, "Category", t.category);
            _prop_select (b, "Priority", t.priority);
            _prop_checkbox (b, "Done", t.done);
            _prop_checkbox (b, "Archived", tasks.is_archived (t.id));
            _prop_rich (b, "Subtasks", _serialize_subtasks (t));
            _prop_number (b, "LocalId", (int) t.id);
            b.end_object ();
            b.end_object ();
            var gen = new Json.Generator (); gen.set_root (b.get_root ());
            return gen.to_data (null);
        }

        private void _prop_title (Json.Builder b, string name, string val) {
            b.set_member_name (name); b.begin_object (); b.set_member_name ("title"); _rich_array (b, val); b.end_object ();
        }
        private void _prop_rich (Json.Builder b, string name, string val) {
            b.set_member_name (name); b.begin_object (); b.set_member_name ("rich_text"); _rich_array (b, val); b.end_object ();
        }
        private void _rich_array (Json.Builder b, string val) {
            b.begin_array ();
            if (val.length > 0) {
                int CHUNK = 1900;
                for (int i = 0; i < val.length; i += CHUNK) {
                    int end = int.min (i + CHUNK, val.length);
                    b.begin_object ();
                    b.set_member_name ("type"); b.add_string_value ("text");
                    b.set_member_name ("text");
                    b.begin_object (); b.set_member_name ("content"); b.add_string_value (val.substring (i, end - i)); b.end_object ();
                    b.end_object ();
                }
            }
            b.end_array ();
        }
        private void _prop_number (Json.Builder b, string name, int val) {
            b.set_member_name (name); b.begin_object (); b.set_member_name ("number"); b.add_int_value (val); b.end_object ();
        }
        private void _prop_select (Json.Builder b, string name, string val) {
            b.set_member_name (name); b.begin_object (); b.set_member_name ("select");
            b.begin_object (); b.set_member_name ("name"); b.add_string_value (val.length > 0 ? val : "M"); b.end_object ();
            b.end_object ();
        }
        private void _prop_checkbox (Json.Builder b, string name, bool val) {
            b.set_member_name (name); b.begin_object (); b.set_member_name ("checkbox"); b.add_boolean_value (val); b.end_object ();
        }

        private string _serialize_subtasks (Task t) {
            if (t.subtasks.size == 0) return "";
            var b = new Json.Builder ();
            b.begin_array ();
            foreach (var s in t.subtasks) {
                b.begin_object ();
                b.set_member_name ("title"); b.add_string_value (s.title);
                b.set_member_name ("priority"); b.add_string_value (s.priority);
                b.set_member_name ("done"); b.add_boolean_value (s.done);
                b.end_object ();
            }
            b.end_array ();
            var gen = new Json.Generator (); gen.set_root (b.get_root ());
            return gen.to_data (null);
        }

        private Gee.ArrayList<Subtask> _parse_subtasks (string s) {
            var outl = new Gee.ArrayList<Subtask> ();
            if (s.length == 0) return outl;
            try {
                var p = new Json.Parser (); p.load_from_data (s);
                if (p.get_root ().get_node_type () != Json.NodeType.ARRAY) return outl;
                var arr = p.get_root ().get_array ();
                for (uint i = 0; i < arr.get_length (); i++) {
                    if (arr.get_element (i).get_node_type () != Json.NodeType.OBJECT) continue;
                    var o = arr.get_object_element (i);
                    outl.add (new Subtask.with (0,
                        JiraStore._str (o, "title"),
                        JiraStore._str_def (o, "priority", "M"),
                        o.has_member ("done") && o.get_boolean_member ("done")));
                }
            } catch (Error e) { }
            return outl;
        }

        private RemoteTask _page_to_remote (Json.Object page) {
            var pr = JiraStore._obj (page, "properties");
            var r = new RemoteTask ();
            r.notion_page_id = page.has_member ("id") ? page.get_string_member ("id") : "";
            r.notion_last_edited = page.has_member ("last_edited_time") ? page.get_string_member ("last_edited_time") : "";
            r.title = _rich_plain (pr, "Name", true);
            if (r.title.length == 0) r.title = "(sin título)";
            r.description = _rich_plain (pr, "Description", false);
            r.category = _num_prop (pr, "Category");
            r.priority = _select_prop (pr, "Priority");
            if (r.priority.length == 0) r.priority = "M";
            r.done = _checkbox_prop (pr, "Done");
            r.archived = _checkbox_prop (pr, "Archived");
            r.subtasks = _parse_subtasks (_rich_plain (pr, "Subtasks", false));
            return r;
        }

        private string _rich_plain (Json.Object pr, string name, bool is_title) {
            if (!pr.has_member (name)) return "";
            var p = JiraStore._obj (pr, name);
            string key = is_title ? "title" : "rich_text";
            if (!p.has_member (key)) return "";
            var arr = p.get_array_member (key);
            var sb = new StringBuilder ();
            for (uint i = 0; i < arr.get_length (); i++) {
                var o = arr.get_object_element (i);
                if (o.has_member ("plain_text")) sb.append (o.get_string_member ("plain_text"));
            }
            return sb.str;
        }
        private int _num_prop (Json.Object pr, string name) {
            if (!pr.has_member (name)) return 0;
            var p = JiraStore._obj (pr, name);
            if (p.has_member ("number") && p.get_member ("number").get_node_type () == Json.NodeType.VALUE)
                return (int) p.get_double_member ("number");
            return 0;
        }
        private string _select_prop (Json.Object pr, string name) {
            if (!pr.has_member (name)) return "";
            var p = JiraStore._obj (pr, name);
            if (p.has_member ("select") && p.get_member ("select").get_node_type () == Json.NodeType.OBJECT)
                return JiraStore._str (p.get_object_member ("select"), "name");
            return "";
        }
        private bool _checkbox_prop (Json.Object pr, string name) {
            if (!pr.has_member (name)) return false;
            var p = JiraStore._obj (pr, name);
            return p.has_member ("checkbox") && p.get_boolean_member ("checkbox");
        }

        private static int64 _parse_iso_ms (string iso) {
            if (iso.length == 0) return 0;
            var dt = new DateTime.from_iso8601 (iso, null);
            if (dt == null) return 0;
            return dt.to_unix () * 1000;
        }

        // ---- debug ------------------------------------------------------
        private void _append_debug (string line) {
            string next = last_debug_log + line;
            if (next.length > 80000)
                next = "[…log truncado…]\n" + next.substring (next.length - 40000);
            last_debug_log = next;
        }
        private void _warn (string msg) { _append_debug ("[!] " + msg + "\n"); warning ("[NotionSync] %s", msg); }
        public void clear_debug_log () { last_debug_log = ""; bump (); }
    }

    private class PushOp {
        public int64 task_id;
        public string page_id;
        public PushOp (int64 task_id, string page_id) { this.task_id = task_id; this.page_id = page_id; }
    }
}
