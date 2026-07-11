/*
 * Widgets.vala — shared UI helpers: global CSS, priority badges, colored
 * category dots, and small utilities used across the mode views.
 */

namespace Ct {

    namespace Widgets {

        private static bool _css_loaded = false;

        public void init_css () {
            if (_css_loaded) return;
            _css_loaded = true;
            var provider = new Gtk.CssProvider ();
            provider.load_from_string ("""
                .prio-badge {
                    font-size: 0.72em;
                    font-weight: bold;
                    color: #ffffff;
                    padding: 0px 5px;
                    border-radius: 4px;
                    min-width: 14px;
                }
                .prio-XS { background: #95a5a6; }
                .prio-S  { background: #3498db; }
                .prio-M  { background: #2ecc71; }
                .prio-L  { background: #f39c12; }
                .prio-XL { background: #e74c3c; }
                .count-badge {
                    font-size: 0.72em;
                    font-weight: bold;
                    padding: 0px 6px;
                    border-radius: 8px;
                    background: alpha(@accent_bg_color, 0.85);
                    color: @accent_fg_color;
                }
                .task-done { opacity: 0.55; }
                .dim { opacity: 0.6; }
                .cat-tab-dot { min-width: 10px; min-height: 10px; border-radius: 5px; }
                .status-chip {
                    font-size: 0.78em;
                    padding: 1px 8px;
                    border-radius: 9px;
                    color: #ffffff;
                }
                .mono { font-family: monospace; }
                .card-pad { padding: 6px; }
                progressbar.ct-hours trough { min-height: 5px; }
                progressbar.ct-hours progress { min-height: 5px; background: #3498db; }
                progressbar.ct-hours-full progress { background: #e74c3c; }
            """);
            Gtk.StyleContext.add_provider_for_display (
                Gdk.Display.get_default (),
                provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
        }

        public Gdk.RGBA parse_color (string hex, string fallback = "#3498db") {
            var rgba = Gdk.RGBA ();
            if (!rgba.parse (hex))
                rgba.parse (fallback);
            return rgba;
        }

        // Small "XS/S/M/L/XL" chip.
        public Gtk.Widget priority_badge (string level) {
            var lbl = new Gtk.Label (level);
            lbl.add_css_class ("prio-badge");
            lbl.add_css_class ("prio-" + level);
            lbl.valign = Gtk.Align.CENTER;
            return lbl;
        }

        // A count pill (e.g. pending tasks per tab).
        public Gtk.Label count_badge (int n) {
            var lbl = new Gtk.Label (n.to_string ());
            lbl.add_css_class ("count-badge");
            lbl.valign = Gtk.Align.CENTER;
            return lbl;
        }

        // A filled circle of an arbitrary color (category swatch).
        public Gtk.Widget color_dot (string hex, int size = 12) {
            var area = new Gtk.DrawingArea ();
            area.content_width = size;
            area.content_height = size;
            area.valign = Gtk.Align.CENTER;
            var rgba = parse_color (hex);
            area.set_draw_func ((da, cr, w, h) => {
                double r = double.min (w, h) / 2.0;
                cr.arc (w / 2.0, h / 2.0, r, 0, 2 * Math.PI);
                cr.set_source_rgba (rgba.red, rgba.green, rgba.blue, rgba.alpha);
                cr.fill ();
            });
            return area;
        }

        // A colored status chip with white/auto text (used in Jira/GH lists).
        public Gtk.Widget status_chip (string text, string hex) {
            var lbl = new Gtk.Label (text);
            lbl.add_css_class ("status-chip");
            lbl.valign = Gtk.Align.CENTER;
            lbl.ellipsize = Pango.EllipsizeMode.END;
            var rgba = parse_color (hex, "#6e7681");
            var prov = new Gtk.CssProvider ();
            prov.load_from_string (".status-chip { background: %s; }".printf (rgba.to_string ()));
            lbl.get_style_context ().add_provider (prov, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1);
            return lbl;
        }

        // Map a Jira statusCategory colorName to a hex color.
        public string jira_status_color (string color_name) {
            switch (color_name.down ()) {
                case "green":         return "#2ecc71";
                case "yellow":        return "#f5a623";
                case "blue-gray":
                case "blue_gray":
                case "medium-gray":   return "#42526e";
                case "brown":         return "#e67e22";
                case "warm-red":      return "#e74c3c";
                default:              return "#6e7681";
            }
        }

        // Compact consumed-hours bar: "spent / original" over a thin bar.
        // Returns null when there's no estimate to show.
        public Gtk.Widget? hours_bar (int spent_sec, int original_sec) {
            double ratio = Ct.JiraStore.consumed_ratio (original_sec, spent_sec);
            if (ratio < 0) return null;
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 1) { valign = Gtk.Align.CENTER, width_request = 92 };
            var lbl = new Gtk.Label ("%s / %s".printf (
                Ct.JiraStore.fmt_seconds (spent_sec), Ct.JiraStore.fmt_seconds (original_sec)));
            lbl.add_css_class ("caption");
            lbl.add_css_class ("dim");
            lbl.halign = Gtk.Align.CENTER;
            var bar = new Gtk.ProgressBar () { fraction = ratio };
            bar.add_css_class ("ct-hours");
            if (ratio >= 1.0) bar.add_css_class ("ct-hours-full");
            box.append (lbl);
            box.append (bar);
            box.tooltip_text = "Consumido %s de %s".printf (
                Ct.JiraStore.fmt_seconds (spent_sec), Ct.JiraStore.fmt_seconds (original_sec));
            return box;
        }

        public string gh_state_color (string state) {
            switch (state) {
                case "OPEN":   return "#238636";
                case "CLOSED": return "#8957e5";
                case "MERGED": return "#8957e5";
                case "DRAFT":  return "#6e7681";
                default:       return "#6e7681";
            }
        }
    }
}
