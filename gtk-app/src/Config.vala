/*
 * Config.vala — thin typed wrapper around the GSettings schema
 * (io.github.categorizedtodo). Replaces the KDE Plasmoid.configuration
 * (KConfig main.xml). GSettings is durable per-user (dconf), so — unlike
 * the plasmoid — we do not need to mirror credentials into SQLite.
 *
 * The underlying GSettings object is exposed as `settings` so the
 * preferences UI can bind widgets directly, and `changed` fires on any key.
 */

namespace Ct {

    public class Config : Object {
        public GLib.Settings settings { get; private set; }

        public signal void changed (string key);

        public Config () {
            settings = new GLib.Settings (Ct.APP_ID);
            settings.changed.connect ((key) => this.changed (key));
        }

        // ---- scalar helpers --------------------------------------------
        public string get_string (string key) { return settings.get_string (key); }
        public void   set_string (string key, string v) { settings.set_string (key, v); }
        public int    get_int (string key) { return settings.get_int (key); }
        public void   set_int (string key, int v) { settings.set_int (key, v); }
        public bool   get_bool (string key) { return settings.get_boolean (key); }
        public void   set_bool (string key, bool v) { settings.set_boolean (key, v); }

        public string[] get_strv (string key) { return settings.get_strv (key); }
        public void     set_strv (string key, string[] v) { settings.set_strv (key, v); }

        // Safe indexed access into a string-list key.
        public string strv_at (string key, int index, string fallback = "") {
            var arr = settings.get_strv (key);
            if (index >= 0 && index < arr.length && arr[index] != null)
                return arr[index];
            return fallback;
        }

        // ---- convenience accessors used across the app -----------------
        public string mode {
            owned get { return get_string ("mode"); }
            set { set_string ("mode", value); }
        }

        public int category_count {
            get { return int.min (7, int.max (1, get_int ("category-count"))); }
        }

        public string category_name (int i) {
            return strv_at ("category-names", i, "Categoría %d".printf (i + 1));
        }
        public string category_color (int i) {
            return strv_at ("category-colors", i, "#3498db");
        }

        public int popup_width  { get { return get_int ("popup-width"); } }
        public int popup_height { get { return get_int ("popup-height"); } }
        public int popup_scale  { get { return get_int ("popup-scale"); } }
    }
}
