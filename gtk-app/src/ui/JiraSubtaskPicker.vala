/*
 * JiraSubtaskPicker.vala — modal to pick a Jira issue/subtask to link to a
 * local ToDo task (the "todo-jira-link" feature). Searches the issues already
 * loaded by JiraStore (the configured JQL) client-side by key + summary.
 * Emits picked(task_id, key); an empty key unlinks.
 */

namespace Ct {

    public class JiraSubtaskPicker : Adw.Dialog {
        private JiraStore jira;
        private int64 task_id;
        private string current_key;

        private Gtk.SearchEntry search;
        private Gtk.ListBox list;

        public signal void picked (int64 task_id, string key);

        public JiraSubtaskPicker (JiraStore jira, int64 task_id, string current_key) {
            this.jira = jira;
            this.task_id = task_id;
            this.current_key = current_key;
            title = "Anexar subtarea de Jira";
            content_width = 540;
            content_height = 560;
            build ();
            rebuild ();
            jira.changed.connect (rebuild);
            if (jira.issues.size == 0 && !jira.loading) jira.fetch.begin ();
        }

        private void build () {
            var tv = new Adw.ToolbarView ();
            var header = new Adw.HeaderBar ();
            var refresh = new Gtk.Button.from_icon_name ("view-refresh-symbolic");
            refresh.tooltip_text = "Refrescar issues de Jira";
            refresh.clicked.connect (() => jira.fetch.begin ());
            header.pack_end (refresh);
            tv.add_top_bar (header);

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) {
                margin_top = 10, margin_bottom = 10, margin_start = 10, margin_end = 10
            };
            search = new Gtk.SearchEntry () { placeholder_text = "Buscar por código o título (ej: CP-123)…", hexpand = true };
            search.search_changed.connect (rebuild);
            box.append (search);

            if (current_key.length > 0) {
                var unlink = new Gtk.Button.with_label ("Quitar anexión (%s)".printf (current_key));
                unlink.add_css_class ("destructive-action");
                unlink.clicked.connect (() => { picked (task_id, ""); close (); });
                box.append (unlink);
            }

            list = new Gtk.ListBox () { selection_mode = Gtk.SelectionMode.NONE };
            list.add_css_class ("boxed-list");
            var ph = new Gtk.Label ("Sin resultados") { margin_top = 12, margin_bottom = 12 };
            ph.add_css_class ("dim");
            list.set_placeholder (ph);
            list.row_activated.connect ((row) => {
                var key = row.get_data<string> ("key");
                if (key != null) { picked (task_id, key); close (); }
            });
            var scroll = new Gtk.ScrolledWindow () { hscrollbar_policy = Gtk.PolicyType.NEVER, vexpand = true, child = list };
            box.append (scroll);

            tv.content = box;
            set_child (tv);
        }

        private void rebuild () {
            Gtk.Widget? c = list.get_first_child ();
            while (c != null) { var n = c.get_next_sibling (); list.remove (c); c = n; }

            string q = search.text.strip ().down ();
            foreach (var iss in jira.issues) {
                string hay = (iss.key + " " + iss.summary).down ();
                if (q.length > 0 && !hay.contains (q)) continue;
                var row = new Adw.ActionRow ();
                row.title = "<span font_family='monospace'>%s</span> — %s".printf (
                    Markup.escape_text (iss.key), Markup.escape_text (iss.summary));
                row.use_markup = true;
                if (iss.status_name.length > 0) row.subtitle = iss.status_name;
                row.activatable = true;
                row.set_data<string> ("key", iss.key);
                if (iss.key == current_key) {
                    var chk = new Gtk.Image.from_icon_name ("object-select-symbolic") { valign = Gtk.Align.CENTER };
                    row.add_suffix (chk);
                }
                list.append (row);
            }
        }
    }
}
