/*
 * TaskStore.vala — central store for the local ToDo list (ported from
 * TaskStore.qml). Owns the in-memory arrays of Task objects and writes every
 * mutation straight to SQLite. Emits `changed` (with a bumped `version`) so
 * the UI can refresh.
 */

namespace Ct {

    public class TaskStore : Object {
        public Config config { get; construct; }
        public Database database { get; construct; }

        public Gee.ArrayList<Task> tasks { get; private set; }
        public Gee.ArrayList<Task> archived { get; private set; }
        public int version { get; private set; default = 0; }

        private int64 _next_id = 1;

        public signal void changed ();

        public TaskStore (Config config, Database database) {
            Object (config: config, database: database);
        }

        construct {
            tasks = new Gee.ArrayList<Task> ();
            archived = new Gee.ArrayList<Task> ();
        }

        private static int64 now_ms () { return GLib.get_real_time () / 1000; }

        private void bump () {
            version++;
            changed ();
        }

        private void touch (Task t) { t.updated_at = now_ms (); }

        public void load () {
            var data = database.load_all_tasks ();
            tasks = data.active;
            archived = data.archived;
            _next_id = int64.max (1, data.max_id + 1);
            bump ();
        }

        // ---- queries ----------------------------------------------------
        public Gee.ArrayList<Task> tasks_for_category (int cat) {
            var outl = new Gee.ArrayList<Task> ();
            foreach (var t in tasks)
                if (t.category == cat) outl.add (t);
            return outl;
        }

        public int pending_count_for_category (int cat) {
            int c = 0;
            foreach (var t in tasks)
                if (t.category == cat && !t.done) c++;
            return c;
        }

        public int total_pending () {
            int c = 0;
            foreach (var t in tasks)
                if (!t.done) c++;
            return c;
        }

        private int index_of (Gee.ArrayList<Task> arr, int64 id) {
            for (int i = 0; i < arr.size; i++)
                if (arr[i].id == id) return i;
            return -1;
        }

        public Task? get_task (int64 id) {
            int i = index_of (tasks, id);
            return i >= 0 ? tasks[i] : null;
        }

        public Task? get_any_task (int64 id) {
            int i = index_of (tasks, id);
            if (i >= 0) return tasks[i];
            int k = index_of (archived, id);
            return k >= 0 ? archived[k] : null;
        }

        public bool is_archived (int64 id) {
            return index_of (archived, id) >= 0;
        }

        // ---- mutations --------------------------------------------------
        public int64 add_task (string title, int category, string priority, string description) {
            var t = new Task ();
            t.id = _next_id++;
            t.title = title;
            t.category = category;
            t.priority = priority.length > 0 ? priority : "M";
            t.description = description;
            t.created_at = now_ms ();
            touch (t);
            tasks.add (t);
            database.save_task (t, false);
            bump ();
            return t.id;
        }

        public void update_task (int64 id, string? title, string? description,
                                 int? category, string? priority) {
            var t = get_task (id);
            if (t == null) return;
            if (title != null) t.title = title;
            if (description != null) t.description = description;
            if (category != null) t.category = category;
            if (priority != null) t.priority = priority;
            touch (t);
            database.save_task (t, false);
            bump ();
        }

        // Replace a task's whole subtask list (used by the edit dialog).
        // Subtasks with id == 0 get a fresh id.
        public void replace_subtasks (int64 id, Gee.List<Subtask> subs) {
            var t = get_task (id);
            if (t == null) t = get_any_task (id);
            if (t == null) return;
            t.subtasks.clear ();
            foreach (var s in subs) {
                if (s.id == 0) s.id = _next_id++;
                t.subtasks.add (s);
            }
            touch (t);
            database.save_task (t, is_archived (t.id));
            bump ();
        }

        // Link (or unlink, with "") a task to a Jira issue/subtask key.
        public void set_jira_key (int64 id, string key) {
            var t = get_any_task (id);
            if (t == null) return;
            t.jira_key = key;
            touch (t);
            database.save_task (t, is_archived (t.id));
            bump ();
        }

        public void toggle_task_done (int64 id) {
            var t = get_task (id);
            if (t == null) return;
            t.done = !t.done;
            touch (t);
            database.save_task (t, false);
            bump ();
        }

        public void add_subtask (int64 task_id, string title, string priority) {
            var t = get_task (task_id);
            if (t == null) return;
            t.subtasks.add (new Subtask.with (_next_id++, title, priority.length > 0 ? priority : "M", false));
            touch (t);
            database.save_task (t, false);
            bump ();
        }

        public void update_subtask (int64 task_id, int64 sub_id, string? title, string? priority) {
            var t = get_task (task_id);
            if (t == null) return;
            foreach (var sub in t.subtasks) {
                if (sub.id == sub_id) {
                    if (title != null) sub.title = title;
                    if (priority != null) sub.priority = priority;
                    touch (t);
                    database.save_task (t, false);
                    bump ();
                    return;
                }
            }
        }

        public void toggle_subtask_done (int64 task_id, int64 sub_id) {
            var t = get_task (task_id);
            if (t == null) return;
            foreach (var sub in t.subtasks) {
                if (sub.id == sub_id) {
                    sub.done = !sub.done;
                    touch (t);
                    database.save_task (t, false);
                    bump ();
                    return;
                }
            }
        }

        public void remove_subtask (int64 task_id, int64 sub_id) {
            var t = get_task (task_id);
            if (t == null) return;
            for (int j = 0; j < t.subtasks.size; j++) {
                if (t.subtasks[j].id == sub_id) {
                    t.subtasks.remove_at (j);
                    touch (t);
                    database.save_task (t, false);
                    bump ();
                    return;
                }
            }
        }

        public void archive_task (int64 id) {
            int i = index_of (tasks, id);
            if (i < 0) return;
            var t = tasks[i];
            t.archived_at = now_ms ();
            t.done = true;
            touch (t);
            archived.insert (0, t);
            tasks.remove_at (i);
            database.save_task (t, true);
            bump ();
        }

        public void restore_task (int64 id) {
            int i = index_of (archived, id);
            if (i < 0) return;
            var t = archived[i];
            t.archived_at = 0;
            t.done = false;
            touch (t);
            tasks.add (t);
            archived.remove_at (i);
            database.save_task (t, false);
            bump ();
        }

        public void delete_archived (int64 id) {
            int i = index_of (archived, id);
            if (i < 0) return;
            archived.remove_at (i);
            database.delete_task (id);
            bump ();
        }

        public void clear_archive () {
            archived.clear ();
            database.clear_archive ();
            bump ();
        }

        public void reassign_out_of_range_categories (int new_count) {
            bool dirty = false;
            foreach (var t in tasks) {
                if (t.category >= new_count) {
                    t.category = new_count - 1;
                    database.save_task (t, false);
                    dirty = true;
                }
            }
            foreach (var t in archived) {
                if (t.category >= new_count) {
                    t.category = new_count - 1;
                    database.save_task (t, true);
                    dirty = true;
                }
            }
            if (dirty) bump ();
        }

        // ---- export / import -------------------------------------------
        public string export_category_json (int cat) {
            var builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("schema"); builder.add_string_value ("categorizedtodo.v1");
            builder.set_member_name ("exportedAt"); builder.add_int_value (now_ms ());
            builder.set_member_name ("category"); builder.add_int_value (cat);
            builder.set_member_name ("categoryName"); builder.add_string_value (config.category_name (cat));
            builder.set_member_name ("tasks");
            builder.begin_array ();
            foreach (var t in tasks) {
                if (t.category != cat) continue;
                _task_to_json (builder, t);
            }
            builder.end_array ();
            builder.end_object ();
            var gen = new Json.Generator ();
            gen.set_root (builder.get_root ());
            gen.pretty = true;
            return gen.to_data (null);
        }

        private void _task_to_json (Json.Builder b, Task t) {
            b.begin_object ();
            b.set_member_name ("title"); b.add_string_value (t.title);
            b.set_member_name ("description"); b.add_string_value (t.description);
            b.set_member_name ("category"); b.add_int_value (t.category);
            b.set_member_name ("priority"); b.add_string_value (t.priority);
            b.set_member_name ("done"); b.add_boolean_value (t.done);
            b.set_member_name ("subtasks");
            b.begin_array ();
            foreach (var sub in t.subtasks) {
                b.begin_object ();
                b.set_member_name ("title"); b.add_string_value (sub.title);
                b.set_member_name ("priority"); b.add_string_value (sub.priority);
                b.set_member_name ("done"); b.add_boolean_value (sub.done);
                b.end_object ();
            }
            b.end_array ();
            b.end_object ();
        }

        public int import_category_json (int cat, string json_text) throws Error {
            var parser = new Json.Parser ();
            parser.load_from_data (json_text);
            var root = parser.get_root ();
            Json.Array? arr = null;
            if (root.get_node_type () == Json.NodeType.ARRAY) {
                arr = root.get_array ();
            } else if (root.get_node_type () == Json.NodeType.OBJECT) {
                var obj = root.get_object ();
                if (obj.has_member ("tasks"))
                    arr = obj.get_array_member ("tasks");
            }
            if (arr == null)
                throw new IOError.INVALID_DATA ("Unrecognized JSON structure");

            int imported = 0;
            for (uint i = 0; i < arr.get_length (); i++) {
                var el = arr.get_element (i);
                if (el.get_node_type () != Json.NodeType.OBJECT) continue;
                var o = el.get_object ();
                var t = new Task ();
                t.id = _next_id++;
                t.title = _member_str (o, "title");
                t.description = _member_str (o, "description");
                t.category = cat;
                t.priority = _member_str_def (o, "priority", "M");
                t.done = o.has_member ("done") && o.get_boolean_member ("done");
                t.created_at = now_ms ();
                touch (t);
                if (o.has_member ("subtasks") && o.get_member ("subtasks").get_node_type () == Json.NodeType.ARRAY) {
                    var subs = o.get_array_member ("subtasks");
                    for (uint j = 0; j < subs.get_length (); j++) {
                        var so = subs.get_object_element (j);
                        t.subtasks.add (new Subtask.with (
                            _next_id++, _member_str (so, "title"),
                            _member_str_def (so, "priority", "M"),
                            so.has_member ("done") && so.get_boolean_member ("done")));
                    }
                }
                tasks.add (t);
                database.save_task (t, false);
                imported++;
            }
            bump ();
            return imported;
        }

        private static string _member_str (Json.Object o, string key) {
            return o.has_member (key) ? (o.get_string_member (key) ?? "") : "";
        }
        private static string _member_str_def (Json.Object o, string key, string def) {
            return o.has_member (key) && o.get_string_member (key) != null ? o.get_string_member (key) : def;
        }

        // ---- Notion sync support ---------------------------------------
        public Gee.ArrayList<Task> all_tasks_for_sync () {
            var outl = new Gee.ArrayList<Task> ();
            outl.add_all (tasks);
            outl.add_all (archived);
            return outl;
        }

        public bool notion_local_changed (Task t) {
            return t.updated_at > t.notion_synced_at;
        }

        private Task? find_by_notion (string page_id, out bool arch) {
            arch = false;
            if (page_id.length == 0) return null;
            foreach (var t in tasks)
                if (t.notion_page_id == page_id) { arch = false; return t; }
            foreach (var t in archived)
                if (t.notion_page_id == page_id) { arch = true; return t; }
            return null;
        }

        public void mark_pushed (int64 task_id, string page_id, string last_edited) {
            var t = get_any_task (task_id);
            if (t == null) return;
            if (page_id.length > 0) t.notion_page_id = page_id;
            if (last_edited.length > 0) t.notion_last_edited = last_edited;
            t.notion_synced_at = now_ms ();
            database.save_task (t, is_archived (t.id));
            bump ();
        }

        // Upsert a task coming from Notion (pull side).
        public int64 apply_remote_upsert (RemoteTask remote) {
            int64 now = now_ms ();
            bool arch;
            var t = find_by_notion (remote.notion_page_id, out arch);
            if (t != null) {
                t.title = remote.title;
                t.description = remote.description;
                t.category = remote.category;
                t.priority = remote.priority;
                t.done = remote.done;
                t.notion_last_edited = remote.notion_last_edited;
                t.notion_synced_at = now;
                t.updated_at = now;
                t.subtasks.clear ();
                foreach (var rs in remote.subtasks) {
                    var sid = rs.id != 0 ? rs.id : _next_id++;
                    t.subtasks.add (new Subtask.with (sid, rs.title, rs.priority, rs.done));
                }
                bool want_arch = remote.archived;
                if (want_arch && !arch) {
                    t.archived_at = now;
                    tasks.remove (t);
                    archived.insert (0, t);
                } else if (!want_arch && arch) {
                    t.archived_at = 0;
                    archived.remove (t);
                    tasks.add (t);
                }
                database.save_task (t, want_arch);
                bump ();
                return t.id;
            }

            // New page → create locally.
            t = new Task ();
            t.id = _next_id++;
            t.title = remote.title;
            t.description = remote.description;
            t.category = remote.category;
            t.priority = remote.priority;
            t.done = remote.done;
            t.notion_page_id = remote.notion_page_id;
            t.notion_last_edited = remote.notion_last_edited;
            t.notion_synced_at = now;
            t.updated_at = now;
            t.created_at = now;
            foreach (var rs in remote.subtasks)
                t.subtasks.add (new Subtask.with (rs.id != 0 ? rs.id : _next_id++, rs.title, rs.priority, rs.done));
            if (remote.archived) {
                t.archived_at = now;
                archived.insert (0, t);
            } else {
                tasks.add (t);
            }
            database.save_task (t, remote.archived);
            bump ();
            return t.id;
        }
    }

    // The "remote" shape used by the Notion sync pull side.
    public class RemoteTask : Object {
        public string notion_page_id = "";
        public string notion_last_edited = "";
        public string title = "";
        public string description = "";
        public int category = 0;
        public string priority = "M";
        public bool done = false;
        public bool archived = false;
        public Gee.ArrayList<Subtask> subtasks = new Gee.ArrayList<Subtask> ();
    }
}
