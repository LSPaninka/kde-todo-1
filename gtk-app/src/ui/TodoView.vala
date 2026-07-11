/*
 * TodoView.vala — the "todo" mode: a category switcher (Global + N categories
 * + Archive) over a rebuilt task list. Tasks render as Adw rows with a done
 * checkbox, priority badge and expandable subtasks. All mutations go through
 * TaskStore; the whole visible list is rebuilt on `store.changed`.
 */

namespace Ct {

    public class TodoView : Gtk.Box {
        private Application app;
        private TaskStore store;
        private Config config;
        private NotionSyncStore notion_sync;
        private JiraStore jira;

        private Adw.ViewStack stack;
        private Adw.ViewSwitcher switcher;
        private Gtk.Label notion_status;
        private Gtk.Button notion_btn;
        private TaskEditDialog? dialog = null;
        private Gee.ArrayList<Adw.ExpanderRow> _expanders = new Gee.ArrayList<Adw.ExpanderRow> ();

        public TodoView (Application app) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.app = app;
            this.store = app.store;
            this.config = app.config;
            this.notion_sync = app.notion_sync;
            this.jira = app.jira;
            build ();
            store.changed.connect (rebuild);
            jira.changed.connect (() => { if (config.get_bool ("todo-jira-link")) rebuild (); });
            config.changed.connect ((key) => {
                if (key == "category-count" || key == "category-names" ||
                    key == "category-colors" || key == "show-priority-icons" ||
                    key == "todo-jira-link")
                    rebuild ();
            });
            notion_sync.changed.connect (update_notion_footer);
            notion_sync.sync_finished.connect ((ok, pulled, pushed) => {
                if (ok) {
                    notion_status.label = "Notion: %d ↓ / %d ↑".printf (pulled, pushed);
                } else {
                    notion_status.label = notion_sync.last_error;
                }
            });
            rebuild ();
            update_notion_footer ();
        }

        private void build () {
            stack = new Adw.ViewStack () { vexpand = true };
            switcher = new Adw.ViewSwitcher () {
                stack = stack,
                policy = Adw.ViewSwitcherPolicy.WIDE,
                halign = Gtk.Align.CENTER
            };
            var switch_scroll = new Gtk.ScrolledWindow () {
                vscrollbar_policy = Gtk.PolicyType.NEVER,
                hscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                child = switcher,
                margin_top = 6, margin_bottom = 6, margin_start = 6, margin_end = 6
            };
            append (switch_scroll);
            append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            append (stack);

            // Footer
            var footer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
                margin_top = 6, margin_bottom = 6, margin_start = 10, margin_end = 10
            };
            var pending = new Gtk.Label ("");
            pending.add_css_class ("dim");
            pending.halign = Gtk.Align.START;
            _pending_label = pending;
            footer.append (pending);

            notion_status = new Gtk.Label ("") { hexpand = true, halign = Gtk.Align.END, ellipsize = Pango.EllipsizeMode.END };
            notion_status.add_css_class ("dim");
            footer.append (notion_status);

            notion_btn = new Gtk.Button.from_icon_name ("view-refresh-symbolic");
            notion_btn.tooltip_text = "Sincronizar la lista con Notion";
            notion_btn.add_css_class ("flat");
            notion_btn.clicked.connect (() => {
                notion_status.label = "Sincronizando con Notion…";
                notion_sync.sync.begin ();
            });
            footer.append (notion_btn);

            append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            append (footer);
        }

        private Gtk.Label _pending_label;

        private void update_notion_footer () {
            notion_btn.visible = notion_sync.is_configured ();
            notion_btn.sensitive = !notion_sync.loading;
            if (notion_sync.loading) notion_status.label = "Sincronizando con Notion…";
        }

        private void rebuild () {
            string? current = stack.visible_child_name;
            _expanders.clear ();
            // Clear existing pages.
            var child = stack.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                stack.remove (child);
                child = next;
            }

            // Global
            var gp = stack.add_titled (build_global (), "global", "Global");
            gp.icon_name = "view-list-symbolic";
            int total = store.total_pending ();
            if (total > 0) gp.badge_number = total;

            // Categories
            int n = config.category_count;
            for (int i = 0; i < n; i++) {
                var page = stack.add_titled (build_category (i), "cat%d".printf (i), config.category_name (i));
                int pc = store.pending_count_for_category (i);
                if (pc > 0) page.badge_number = pc;
            }

            // Archive
            var ap = stack.add_titled (build_archive (), "archive", "Archivo");
            ap.icon_name = "user-trash-symbolic";
            if (store.archived.size > 0) ap.badge_number = store.archived.size;

            if (current != null && stack.get_child_by_name (current) != null)
                stack.visible_child_name = current;

            _pending_label.label = "%d tarea(s) pendiente(s) en total".printf (total);
        }

        // ---- pages ------------------------------------------------------
        private Gtk.Widget build_category (int cat) {
            var group = new Adw.PreferencesGroup ();
            group.title = config.category_name (cat);

            var hdr = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2);
            var collapse = new Gtk.Button.from_icon_name ("view-restore-symbolic");
            collapse.add_css_class ("flat");
            collapse.tooltip_text = "Contraer todas las descripciones/subtareas";
            collapse.clicked.connect (() => set_all_expanded (false));
            var expand = new Gtk.Button.from_icon_name ("view-fullscreen-symbolic");
            expand.add_css_class ("flat");
            expand.tooltip_text = "Expandir todas las subtareas";
            expand.clicked.connect (() => set_all_expanded (true));
            var add = new Gtk.Button.from_icon_name ("list-add-symbolic");
            add.add_css_class ("flat");
            add.tooltip_text = "Nueva tarea";
            add.clicked.connect (() => open_new (cat));
            hdr.append (collapse);
            hdr.append (expand);
            hdr.append (add);
            group.header_suffix = hdr;

            var tasks = store.tasks_for_category (cat);
            _sort_tasks (tasks);
            if (tasks.size == 0) {
                group.add (_empty_row ("Sin tareas en esta categoría."));
            } else {
                foreach (var t in tasks)
                    group.add (build_task_row (t, false));
            }
            return _scroller (group);
        }

        private Gtk.Widget build_global () {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            int n = config.category_count;
            bool any = false;
            for (int i = 0; i < n; i++) {
                var tasks = store.tasks_for_category (i);
                if (tasks.size == 0) continue;
                any = true;
                _sort_tasks (tasks);
                var group = new Adw.PreferencesGroup ();
                var htitle = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
                htitle.append (Widgets.color_dot (config.category_color (i), 12));
                htitle.append (new Gtk.Label (config.category_name (i)));
                group.header_suffix = null;
                group.title = config.category_name (i);
                foreach (var t in tasks)
                    group.add (build_task_row (t, true));
                box.append (group);
            }
            if (!any) {
                var g = new Adw.PreferencesGroup ();
                g.add (_empty_row ("No hay tareas todavía. Añadí una desde cualquier categoría."));
                box.append (g);
            }
            return _scroller (box);
        }

        private Gtk.Widget build_archive () {
            var group = new Adw.PreferencesGroup ();
            group.title = "Archivo";
            if (store.archived.size > 0) {
                var empty = new Gtk.Button.with_label ("Vaciar archivo");
                empty.add_css_class ("flat");
                empty.add_css_class ("destructive-action");
                empty.clicked.connect (confirm_empty);
                group.header_suffix = empty;
            }
            if (store.archived.size == 0) {
                group.add (_empty_row ("El archivo está vacío."));
            } else {
                foreach (var t in store.archived) {
                    var row = new Adw.ActionRow () { title = _escape (t.title) };
                    row.add_css_class ("task-done");
                    if (t.description.length > 0) row.subtitle = _escape (_first_line (t.description));
                    var restore = new Gtk.Button.from_icon_name ("edit-undo-symbolic") { valign = Gtk.Align.CENTER };
                    restore.tooltip_text = "Restaurar";
                    restore.add_css_class ("flat");
                    int64 id = t.id;
                    restore.clicked.connect (() => store.restore_task (id));
                    var del = new Gtk.Button.from_icon_name ("user-trash-symbolic") { valign = Gtk.Align.CENTER };
                    del.tooltip_text = "Eliminar definitivamente";
                    del.add_css_class ("flat");
                    del.clicked.connect (() => confirm_delete (id));
                    row.add_suffix (restore);
                    row.add_suffix (del);
                    group.add (row);
                }
            }
            return _scroller (group);
        }

        // ---- task row ---------------------------------------------------
        private Gtk.Widget build_task_row (Task t, bool show_cat_dot) {
            int64 id = t.id;
            Adw.PreferencesRow prow;
            Adw.ActionRow? action = null;
            Adw.ExpanderRow? exp = null;

            if (t.subtasks.size > 0) {
                exp = new Adw.ExpanderRow ();
                _expanders.add (exp);
                prow = exp;
            } else {
                action = new Adw.ActionRow ();
                prow = action;
            }
            prow.title = _escape (t.title);
            if (t.done) prow.add_css_class ("task-done");
            if (t.description.length > 0) {
                if (exp != null) exp.subtitle = _escape (_first_line (t.description));
                else action.subtitle = _escape (_first_line (t.description));
            }

            var check = new Gtk.CheckButton () { active = t.done, valign = Gtk.Align.CENTER };
            check.toggled.connect (() => store.toggle_task_done (id));
            if (exp != null) exp.add_prefix (_prefix_box (t, show_cat_dot, check));
            else action.add_prefix (_prefix_box (t, show_cat_dot, check));

            var suffix = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) { valign = Gtk.Align.CENTER };
            if (config.get_bool ("todo-jira-link")) {
                var jk = t.jira_key;
                var linkb = new Gtk.Button.with_label (jk.length > 0 ? jk : "–") { valign = Gtk.Align.CENTER };
                if (jk.length > 0) linkb.add_css_class ("accent");
                linkb.tooltip_text = jk.length > 0
                    ? "Jira: %s (clic para ver / cambiar)".printf (jk)
                    : "Anexar subtarea de Jira";
                linkb.clicked.connect (() => open_jira_link (t));
                suffix.append (linkb);
            }
            if (config.get_bool ("show-priority-icons"))
                suffix.append (Widgets.priority_badge (t.priority));
            int pend = t.pending_subtasks ();
            if (t.subtasks.size > 0)
                suffix.append (new Gtk.Label ("%d/%d".printf (t.subtasks.size - pend, t.subtasks.size)) { css_classes = { "dim" } });

            var edit = new Gtk.Button.from_icon_name ("document-edit-symbolic") { valign = Gtk.Align.CENTER };
            edit.add_css_class ("flat");
            edit.tooltip_text = "Editar";
            edit.clicked.connect (() => open_edit (t));
            suffix.append (edit);

            var archive = new Gtk.Button.from_icon_name ("check-round-outline-symbolic") { valign = Gtk.Align.CENTER };
            archive.add_css_class ("flat");
            archive.tooltip_text = "Completar y archivar";
            archive.clicked.connect (() => store.archive_task (id));
            suffix.append (archive);

            if (exp != null) exp.add_suffix (suffix);
            else action.add_suffix (suffix);

            // Subtasks
            if (exp != null) {
                foreach (var s in t.subtasks) {
                    int64 sid = s.id;
                    var srow = new Adw.ActionRow () { title = _escape (s.title) };
                    if (s.done) srow.add_css_class ("task-done");
                    var sc = new Gtk.CheckButton () { active = s.done, valign = Gtk.Align.CENTER };
                    sc.toggled.connect (() => store.toggle_subtask_done (id, sid));
                    srow.add_prefix (sc);
                    if (config.get_bool ("show-priority-icons"))
                        srow.add_suffix (Widgets.priority_badge (s.priority));
                    exp.add_row (srow);
                }
            }
            return prow;
        }

        private Gtk.Widget _prefix_box (Task t, bool show_cat_dot, Gtk.CheckButton check) {
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) { valign = Gtk.Align.CENTER };
            if (show_cat_dot) box.append (Widgets.color_dot (config.category_color (t.category), 10));
            box.append (check);
            return box;
        }

        // ---- helpers ----------------------------------------------------
        private void _sort_tasks (Gee.ArrayList<Task> tasks) {
            tasks.sort ((a, b) => {
                if (a.done != b.done) return a.done ? 1 : -1;
                return _prio_rank (b.priority) - _prio_rank (a.priority);
            });
        }
        private int _prio_rank (string p) {
            switch (p) { case "XS": return 0; case "S": return 1; case "M": return 2; case "L": return 3; case "XL": return 4; }
            return 2;
        }

        private Gtk.Widget _scroller (Gtk.Widget content) {
            var clamp = new Adw.Clamp () { maximum_size = 920, child = content,
                margin_top = 10, margin_bottom = 10, margin_start = 10, margin_end = 10 };
            var scroll = new Gtk.ScrolledWindow () { hscrollbar_policy = Gtk.PolicyType.NEVER, vexpand = true, child = clamp };
            return scroll;
        }

        private Adw.ActionRow _empty_row (string text) {
            var row = new Adw.ActionRow () { title = text };
            row.add_css_class ("dim");
            return row;
        }

        private static string _first_line (string s) {
            int nl = s.index_of_char ('\n');
            return nl >= 0 ? s.substring (0, nl) : s;
        }
        private static string _escape (string s) { return Markup.escape_text (s); }

        private void set_all_expanded (bool expanded) {
            foreach (var e in _expanders) e.expanded = expanded;
        }

        private void open_jira_link (Task t) {
            if (t.jira_key.length == 0) {
                var picker = new JiraSubtaskPicker (jira, t.id, "");
                picker.picked.connect ((tid, key) => store.set_jira_key (tid, key));
                picker.present (this);
                return;
            }
            JiraIssue? found = null;
            foreach (var it in jira.issues)
                if (it.key == t.jira_key) { found = it; break; }
            if (found == null) {
                found = new JiraIssue ();
                found.key = t.jira_key;
                string site = config.get_string ("jira-site").strip ();
                while (site.has_suffix ("/")) site = site.substring (0, site.length - 1);
                if (site.length > 0) found.url = site + "/browse/" + t.jira_key;
            }
            var dlg = new JiraDetailDialog (jira, found, t.id, store);
            dlg.present (this);
        }

        // ---- dialogs / actions ------------------------------------------
        private void open_new (int cat) {
            if (dialog == null) dialog = new TaskEditDialog (store, config);
            dialog.load_new (cat);
            dialog.present (this);
        }
        private void open_edit (Task t) {
            if (dialog == null) dialog = new TaskEditDialog (store, config);
            dialog.load_edit (t);
            dialog.present (this);
        }

        private void confirm_delete (int64 id) {
            if (!config.get_bool ("confirm-delete")) { store.delete_archived (id); return; }
            var d = new Adw.AlertDialog ("¿Eliminar tarea?",
                "Esto quitará la tarea del archivo de forma permanente.");
            d.add_response ("cancel", "Cancelar");
            d.add_response ("delete", "Eliminar");
            d.set_response_appearance ("delete", Adw.ResponseAppearance.DESTRUCTIVE);
            d.response.connect ((r) => { if (r == "delete") store.delete_archived (id); });
            d.present (this);
        }
        private void confirm_empty () {
            var d = new Adw.AlertDialog ("¿Vaciar archivo?",
                "Esto eliminará todas las tareas archivadas de forma permanente.");
            d.add_response ("cancel", "Cancelar");
            d.add_response ("empty", "Vaciar");
            d.set_response_appearance ("empty", Adw.ResponseAppearance.DESTRUCTIVE);
            d.response.connect ((r) => { if (r == "empty") store.clear_archive (); });
            d.present (this);
        }
    }
}
