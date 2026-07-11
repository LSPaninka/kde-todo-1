/*
 * JiraView.vala — read-only Jira mode. Category switcher over the configured
 * Jira categories; each issue row opens a detail dialog (summary, status,
 * description, comments) fetched on demand.
 */

namespace Ct {

    public class JiraView : Gtk.Box {
        private Application app;
        private JiraStore jira;
        private Config config;

        private Adw.ViewStack stack;
        private Adw.ViewSwitcher switcher;
        private Gtk.Label status_label;
        private Gtk.Button refresh_btn;
        private Gtk.Spinner spinner;

        public JiraView (Application app) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.app = app;
            this.jira = app.jira;
            this.config = app.config;
            build ();
            jira.changed.connect (() => { rebuild (); update_status (); });
            jira.category_requested.connect ((i) => {
                var name = "jcat%d".printf (i);
                if (stack.get_child_by_name (name) != null) stack.visible_child_name = name;
            });
            config.changed.connect ((key) => { if (key.has_prefix ("jira-category")) rebuild (); });
            rebuild ();
            update_status ();
            if (jira.last_fetched_at == 0) jira.fetch.begin ();
        }

        private void build () {
            var bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
                margin_top = 6, margin_bottom = 6, margin_start = 8, margin_end = 8
            };
            stack = new Adw.ViewStack () { vexpand = true };
            switcher = new Adw.ViewSwitcher () { stack = stack, policy = Adw.ViewSwitcherPolicy.WIDE, hexpand = true, halign = Gtk.Align.CENTER };
            var sw = new Gtk.ScrolledWindow () { vscrollbar_policy = Gtk.PolicyType.NEVER, child = switcher, hexpand = true };
            bar.append (sw);

            spinner = new Gtk.Spinner () { valign = Gtk.Align.CENTER };
            bar.append (spinner);
            refresh_btn = new Gtk.Button.from_icon_name ("view-refresh-symbolic") { valign = Gtk.Align.CENTER };
            refresh_btn.add_css_class ("flat");
            refresh_btn.tooltip_text = "Actualizar";
            refresh_btn.clicked.connect (() => jira.fetch.begin ());
            bar.append (refresh_btn);

            append (bar);
            append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            append (stack);

            status_label = new Gtk.Label ("") { xalign = 0, ellipsize = Pango.EllipsizeMode.END,
                margin_top = 4, margin_bottom = 4, margin_start = 10, margin_end = 10 };
            status_label.add_css_class ("dim");
            append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            append (status_label);
        }

        private void update_status () {
            spinner.spinning = jira.loading;
            refresh_btn.sensitive = !jira.loading;
            if (jira.loading) { status_label.label = "Cargando incidencias…"; return; }
            if (jira.last_error.length > 0) { status_label.label = jira.last_error; return; }
            string when = jira.last_fetched_at > 0
                ? new DateTime.from_unix_local (jira.last_fetched_at / 1000).format ("%H:%M") : "—";
            status_label.label = "%d incidencia(s) · actualizado %s".printf (jira.total_count (), when);
        }

        private int _jira_count () {
            return int.min (10, int.max (1, config.get_int ("jira-category-count")));
        }

        private void rebuild () {
            string? current = stack.visible_child_name;
            var child = stack.get_first_child ();
            while (child != null) { var next = child.get_next_sibling (); stack.remove (child); child = next; }

            int n = _jira_count ();
            for (int i = 0; i < n; i++) {
                var page = stack.add_titled (build_page (i), "jcat%d".printf (i),
                    config.strv_at ("jira-category-names", i, "Cat %d".printf (i + 1)));
                int c = jira.count_by_category (i);
                if (c > 0) page.badge_number = c;
            }
            if (current != null && stack.get_child_by_name (current) != null)
                stack.visible_child_name = current;
        }

        private Gtk.Widget build_page (int cat) {
            var group = new Adw.PreferencesGroup ();
            var issues = jira.issues_by_category (cat);
            if (issues.size == 0) {
                var e = new Adw.ActionRow () { title = "Sin incidencias en esta categoría." };
                e.add_css_class ("dim");
                group.add (e);
            } else {
                foreach (var iss in issues)
                    group.add (build_issue_row (iss));
            }
            var clamp = new Adw.Clamp () { maximum_size = 920, child = group,
                margin_top = 10, margin_bottom = 10, margin_start = 10, margin_end = 10 };
            return new Gtk.ScrolledWindow () { hscrollbar_policy = Gtk.PolicyType.NEVER, vexpand = true, child = clamp };
        }

        private Gtk.Widget build_issue_row (JiraIssue iss) {
            var row = new Adw.ActionRow ();
            row.title = "<span font_family='monospace'>%s</span> — %s".printf (
                Markup.escape_text (iss.key), Markup.escape_text (iss.summary));
            row.use_markup = true;
            var sub = new StringBuilder ();
            if (iss.issuetype.length > 0) sub.append (iss.issuetype);
            if (iss.priority.length > 0) { if (sub.len > 0) sub.append (" · "); sub.append (iss.priority); }
            if (iss.parent_key.length > 0) { if (sub.len > 0) sub.append (" · "); sub.append ("↳ " + iss.parent_key); }
            if (sub.len > 0) row.subtitle = sub.str;
            row.activatable = true;

            var hb = Widgets.hours_bar (iss.spent_sec, iss.original_sec);
            if (hb != null) row.add_suffix (hb);

            string color = jira.status_override_color (iss.status_name) ?? Widgets.jira_status_color (iss.status_color);
            if (iss.status_name.length > 0)
                row.add_suffix (Widgets.status_chip (iss.status_name, color));
            var open = new Gtk.Image.from_icon_name ("go-next-symbolic") { valign = Gtk.Align.CENTER };
            open.add_css_class ("dim");
            row.add_suffix (open);
            row.activated.connect (() => open_detail (iss));

            // Right-click → context menu (detalle / Jira / cambiar estado).
            var rc = new Gtk.GestureClick () { button = Gdk.BUTTON_SECONDARY };
            rc.pressed.connect ((n, x, y) => show_context_menu (row, iss, x, y));
            row.add_controller (rc);
            return row;
        }

        private void open_detail (JiraIssue iss) {
            var dlg = new JiraDetailDialog (jira, iss);
            dlg.present (this);
        }

        private void show_context_menu (Gtk.Widget row, JiraIssue iss, double x, double y) {
            var pop = new Gtk.Popover () { has_arrow = true, autohide = true };
            pop.set_parent (row);
            pop.set_pointing_to ({ (int) x, (int) y, 1, 1 });
            pop.closed.connect (() => pop.unparent ());

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) {
                margin_top = 6, margin_bottom = 6, margin_start = 6, margin_end = 6, width_request = 210
            };
            var detail = _menu_button ("Ver detalle", "view-reveal-symbolic");
            detail.clicked.connect (() => { pop.popdown (); open_detail (iss); });
            box.append (detail);
            var web = _menu_button ("Ver en Jira", "web-browser-symbolic");
            web.clicked.connect (() => {
                pop.popdown ();
                if (iss.url.length > 0) { try { AppInfo.launch_default_for_uri (iss.url, null); } catch (Error e) { } }
            });
            box.append (web);
            box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL) { margin_top = 4, margin_bottom = 4 });
            var heading = new Gtk.Label ("Cambiar estado") { xalign = 0, margin_start = 6 };
            heading.add_css_class ("caption-heading");
            box.append (heading);
            JiraUi.append_transitions (box, jira, iss.key, pop, () => { });
            pop.set_child (box);
            pop.popup ();
        }

        private Gtk.Button _menu_button (string label, string icon) {
            var b = new Gtk.Button () { has_frame = false };
            var h = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            h.append (new Gtk.Image.from_icon_name (icon));
            h.append (new Gtk.Label (label) { xalign = 0, hexpand = true });
            b.child = h;
            return b;
        }
    }

    // Shared helper: fill a box with the workflow transitions for `key`,
    // applying one on click (then refreshing the list). Used by the card
    // context menu and the detail dialog's "Cambiar estado" button.
    public delegate void AppliedFunc ();

    namespace JiraUi {
        public void append_transitions (Gtk.Box box, JiraStore jira, string key,
                                        Gtk.Popover pop, owned AppliedFunc on_applied) {
            var spinner = new Gtk.Spinner () { spinning = true, margin_top = 4, margin_bottom = 4 };
            box.append (spinner);
            jira.fetch_transitions.begin (key, (o, res) => {
                var list = jira.fetch_transitions.end (res);
                box.remove (spinner);
                if (list.size == 0) {
                    var e = new Gtk.Label ("Sin transiciones disponibles") { xalign = 0, margin_start = 6 };
                    e.add_css_class ("dim");
                    box.append (e);
                    return;
                }
                foreach (var tr in list) {
                    var name = tr.name.length > 0 ? tr.name : tr.to_status;
                    var b = new Gtk.Button () { has_frame = false };
                    var h = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
                    if (tr.to_status_color.length > 0)
                        h.append (Widgets.color_dot (Widgets.jira_status_color (tr.to_status_color), 9));
                    h.append (new Gtk.Label (name) { xalign = 0, hexpand = true });
                    b.child = h;
                    string tid = tr.id;
                    b.clicked.connect (() => {
                        pop.popdown ();
                        jira.transition_issue.begin (key, tid, (o2, res2) => {
                            string err; bool ok = jira.transition_issue.end (res2, out err);
                            if (ok) { jira.fetch.begin (); on_applied (); }
                        });
                    });
                    box.append (b);
                }
            });
        }
    }

    // ---- issue detail dialog -------------------------------------------
    public class JiraDetailDialog : Adw.Dialog {
        private JiraStore jira;
        private JiraIssue issue;
        private Gtk.Box body;
        private int64 link_task_id;
        private TaskStore? task_store;

        public JiraDetailDialog (JiraStore jira, JiraIssue issue,
                                 int64 link_task_id = 0, TaskStore? task_store = null) {
            this.jira = jira;
            this.issue = issue;
            this.link_task_id = link_task_id;
            this.task_store = task_store;
            content_width = 560;
            content_height = 640;
            title = issue.key;
            build ();
            load ();
        }

        private void build () {
            var tv = new Adw.ToolbarView ();
            var header = new Adw.HeaderBar ();

            var status_btn = new Gtk.Button.from_icon_name ("emblem-synchronizing-symbolic");
            status_btn.tooltip_text = "Cambiar estado";
            status_btn.clicked.connect (() => {
                var pop = new Gtk.Popover () { autohide = true };
                pop.set_parent (status_btn);
                pop.closed.connect (() => pop.unparent ());
                var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) {
                    margin_top = 6, margin_bottom = 6, margin_start = 6, margin_end = 6, width_request = 210
                };
                JiraUi.append_transitions (box, jira, issue.key, pop, () => load ());
                pop.set_child (box);
                pop.popup ();
            });
            header.pack_start (status_btn);

            if (link_task_id > 0 && task_store != null) {
                var repick = new Gtk.Button.from_icon_name ("document-edit-symbolic");
                repick.tooltip_text = "Cambiar subtarea";
                repick.clicked.connect (() => {
                    var picker = new JiraSubtaskPicker (jira, link_task_id, issue.key);
                    picker.picked.connect ((tid, key) => { task_store.set_jira_key (tid, key); close (); });
                    picker.present (this);
                });
                header.pack_start (repick);
            }

            var openweb = new Gtk.Button.from_icon_name ("web-browser-symbolic");
            openweb.tooltip_text = "Abrir en el navegador";
            openweb.clicked.connect (() => {
                if (issue.url.length > 0) {
                    try { AppInfo.launch_default_for_uri (issue.url, null); } catch (Error e) { }
                }
            });
            header.pack_end (openweb);
            tv.add_top_bar (header);

            body = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {
                margin_top = 12, margin_bottom = 12, margin_start = 14, margin_end = 14
            };
            var scroll = new Gtk.ScrolledWindow () { hscrollbar_policy = Gtk.PolicyType.NEVER, vexpand = true, child = body };
            tv.content = scroll;
            set_child (tv);
        }

        private void load () {
            var loading = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) { halign = Gtk.Align.CENTER, margin_top = 20 };
            var sp = new Gtk.Spinner () { spinning = true };
            loading.append (sp);
            loading.append (new Gtk.Label ("Cargando detalle…"));
            body.append (loading);

            jira.fetch_issue_detail.begin (issue.key, (obj, res) => {
                string err;
                var detail = jira.fetch_issue_detail.end (res, out err);
                // clear
                var c = body.get_first_child ();
                while (c != null) { var n = c.get_next_sibling (); body.remove (c); c = n; }
                if (detail == null) {
                    var lbl = new Gtk.Label (err.length > 0 ? err : "No se pudo cargar el detalle.") { wrap = true, xalign = 0 };
                    body.append (lbl);
                    return;
                }
                render_detail (detail);
            });
        }

        private void render_detail (Json.Object raw) {
            var f = JiraStore._obj (raw, "fields");
            string summary = JiraStore._str (f, "summary");
            var summ = new Gtk.Label (summary) { wrap = true, xalign = 0 };
            summ.add_css_class ("title-3");
            body.append (summ);

            // Consumed-hours bar (from timetracking).
            var tt = JiraStore._obj (f, "timetracking");
            int orig = JiraStore._int (tt, "originalEstimateSeconds");
            int spent = JiraStore._int (tt, "timeSpentSeconds");
            var hb = Widgets.hours_bar (spent, orig);
            if (hb != null) { hb.halign = Gtk.Align.START; body.append (hb); }

            var meta = new Adw.PreferencesGroup ();
            var status = JiraStore._obj (f, "status");
            _kv (meta, "Estado", JiraStore._str (status, "name"));
            _kv (meta, "Tipo", JiraStore._str (JiraStore._obj (f, "issuetype"), "name"));
            _kv (meta, "Prioridad", JiraStore._str (JiraStore._obj (f, "priority"), "name"));
            var assignee = JiraStore._obj (f, "assignee");
            _kv (meta, "Responsable", JiraStore._str (assignee, "displayName"));
            body.append (meta);

            string desc = "";
            if (f.has_member ("description"))
                desc = JiraStore.adf_to_text (f.get_member ("description"));
            if (desc.length > 0) {
                var dg = new Gtk.Label ("Descripción") { xalign = 0 };
                dg.add_css_class ("heading");
                body.append (dg);
                var dl = new Gtk.Label (desc) { wrap = true, xalign = 0, selectable = true };
                body.append (dl);
            }

            // Comments
            if (f.has_member ("comment")) {
                var cm = JiraStore._obj (f, "comment");
                if (cm.has_member ("comments")) {
                    var arr = cm.get_array_member ("comments");
                    if (arr.get_length () > 0) {
                        var ch = new Gtk.Label ("Comentarios") { xalign = 0, margin_top = 6 };
                        ch.add_css_class ("heading");
                        body.append (ch);
                        for (uint i = 0; i < arr.get_length (); i++) {
                            var co = arr.get_object_element (i);
                            string author = JiraStore._str (JiraStore._obj (co, "author"), "displayName");
                            string text = co.has_member ("body") ? JiraStore.adf_to_text (co.get_member ("body")) : "";
                            var cbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
                            cbox.add_css_class ("card");
                            cbox.add_css_class ("card-pad");
                            var al = new Gtk.Label (author) { xalign = 0 };
                            al.add_css_class ("caption-heading");
                            var tl = new Gtk.Label (text) { xalign = 0, wrap = true, selectable = true };
                            cbox.append (al);
                            cbox.append (tl);
                            body.append (cbox);
                        }
                    }
                }
            }
        }

        private void _kv (Adw.PreferencesGroup g, string key, string val) {
            if (val.length == 0) return;
            var row = new Adw.ActionRow () { title = key, subtitle = val };
            g.add (row);
        }
    }
}
