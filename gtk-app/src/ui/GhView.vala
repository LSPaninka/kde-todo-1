/*
 * GhView.vala — read-only GitHub Projects (V2) mode. Category switcher over
 * the configured GitHub categories; each row opens the item URL in the
 * browser.
 */

namespace Ct {

    public class GhView : Gtk.Box {
        private Application app;
        private GhStore gh;
        private Config config;

        private Adw.ViewStack stack;
        private Adw.ViewSwitcher switcher;
        private Gtk.Label status_label;
        private Gtk.Button refresh_btn;
        private Gtk.Spinner spinner;

        public GhView (Application app) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.app = app;
            this.gh = app.gh;
            this.config = app.config;
            build ();
            gh.changed.connect (() => { rebuild (); update_status (); });
            config.changed.connect ((key) => { if (key.has_prefix ("gh-category")) rebuild (); });
            rebuild ();
            update_status ();
            if (gh.last_fetched_at == 0) gh.fetch.begin ();
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
            refresh_btn.clicked.connect (() => gh.fetch.begin ());
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
            spinner.spinning = gh.loading;
            refresh_btn.sensitive = !gh.loading;
            if (gh.loading) { status_label.label = "Cargando ítems del proyecto…"; return; }
            if (gh.last_error.length > 0) { status_label.label = gh.last_error; return; }
            string when = gh.last_fetched_at > 0
                ? new DateTime.from_unix_local (gh.last_fetched_at / 1000).format ("%H:%M") : "—";
            status_label.label = "%d ítem(s) · actualizado %s".printf (gh.total_count (), when);
        }

        private int _gh_count () {
            return int.min (4, int.max (1, config.get_int ("gh-category-count")));
        }

        private void rebuild () {
            string? current = stack.visible_child_name;
            var child = stack.get_first_child ();
            while (child != null) { var next = child.get_next_sibling (); stack.remove (child); child = next; }

            int n = _gh_count ();
            for (int i = 0; i < n; i++) {
                var page = stack.add_titled (build_page (i), "ghcat%d".printf (i),
                    config.strv_at ("gh-category-names", i, "Cat %d".printf (i + 1)));
                int c = gh.count_by_category (i);
                if (c > 0) page.badge_number = c;
            }
            if (current != null && stack.get_child_by_name (current) != null)
                stack.visible_child_name = current;
        }

        private Gtk.Widget build_page (int cat) {
            var group = new Adw.PreferencesGroup ();
            var items = gh.items_by_category (cat);
            if (items.size == 0) {
                var e = new Adw.ActionRow () { title = "Sin ítems en esta categoría." };
                e.add_css_class ("dim");
                group.add (e);
            } else {
                foreach (var it in items)
                    group.add (build_item_row (it));
            }
            var clamp = new Adw.Clamp () { maximum_size = 920, child = group,
                margin_top = 10, margin_bottom = 10, margin_start = 10, margin_end = 10 };
            return new Gtk.ScrolledWindow () { hscrollbar_policy = Gtk.PolicyType.NEVER, vexpand = true, child = clamp };
        }

        private Gtk.Widget build_item_row (GhItem it) {
            var row = new Adw.ActionRow ();
            string prefix = it.number > 0 ? "#%d ".printf (it.number) : "";
            row.title = Markup.escape_text (prefix + it.title);
            var sub = new StringBuilder ();
            sub.append (it.item_type);
            if (it.repo.length > 0) { sub.append (" · "); sub.append (it.repo); }
            if (it.status_name.length > 0) { sub.append (" · "); sub.append (it.status_name); }
            row.subtitle = Markup.escape_text (sub.str);
            if (it.state.length > 0)
                row.add_suffix (Widgets.status_chip (it.state, Widgets.gh_state_color (it.state)));
            if (it.url.length > 0) {
                row.activatable = true;
                var open = new Gtk.Image.from_icon_name ("web-browser-symbolic") { valign = Gtk.Align.CENTER };
                open.add_css_class ("dim");
                row.add_suffix (open);
                string url = it.url;
                row.activated.connect (() => {
                    try { AppInfo.launch_default_for_uri (url, null); } catch (Error e) { }
                });
            }
            return row;
        }
    }
}
