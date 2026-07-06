/*
 * Tray.vala — a StatusNotifierItem (SNI) tray icon for the top bar, with a
 * com.canonical.dbusmenu right-click menu. This is the standard modern Linux
 * tray protocol (KStatusNotifierItem), supported by KDE Plasma and by the
 * GNOME "AppIndicator and KStatusNotifierItem Support" extension that ships
 * with Ubuntu.
 *
 *  - Left click  → Activate()      → toggle the tray popup window.
 *  - Right click → the dbusmenu    → Abrir aplicación / modes / Salir.
 *
 * Everything is pure GDBus (no GTK3 appindicator dependency), so it coexists
 * with GTK 4. The dbusmenu methods expose their exact D-Bus signatures via
 * [DBus (signature = …)] Variant parameters.
 */

namespace Ct {

    // ---- StatusNotifierItem ---------------------------------------------
    [DBus (name = "org.kde.StatusNotifierItem")]
    public class SNItem : Object {
        private weak Tray tray;
        public SNItem (Tray tray) { this.tray = tray; }

        [DBus (name = "Category")]
        public string category { owned get { return "ApplicationStatus"; } }
        [DBus (name = "Id")]
        public string id { owned get { return "categorized-todo"; } }
        [DBus (name = "Title")]
        public string title { owned get { return "Categorized ToDo"; } }
        [DBus (name = "Status")]
        public string status { owned get { return "Active"; } }
        [DBus (name = "WindowId")]
        public int32 window_id { get { return 0; } }
        [DBus (name = "IconName")]
        public string icon_name { owned get { return APP_ID; } }
        [DBus (name = "OverlayIconName")]
        public string overlay_icon_name { owned get { return ""; } }
        [DBus (name = "AttentionIconName")]
        public string attention_icon_name { owned get { return ""; } }
        [DBus (name = "AttentionMovieName")]
        public string attention_movie_name { owned get { return ""; } }
        [DBus (name = "IconThemePath")]
        public string icon_theme_path { owned get { return tray.icon_theme_path; } }
        [DBus (name = "ItemIsMenu")]
        public bool item_is_menu { get { return false; } }
        [DBus (name = "Menu")]
        public ObjectPath menu { owned get { return new ObjectPath ("/MenuBar"); } }

        public signal void NewIcon ();
        public signal void NewTitle ();
        public signal void NewToolTip ();
        public signal void NewStatus (string status);

        public void Activate (int x, int y) { tray.activate_requested (); }
        public void SecondaryActivate (int x, int y) { tray.activate_requested (); }
        public void ContextMenu (int x, int y) { /* host shows the dbusmenu */ }
        public void Scroll (int delta, string orientation) { }
    }

    // ---- com.canonical.dbusmenu -----------------------------------------
    public struct MenuEntry {
        public int id;
        public string label;
        public bool is_separator;
    }

    [DBus (name = "com.canonical.dbusmenu")]
    public class DBusMenu : Object {
        private weak Tray tray;
        private MenuEntry[] entries;
        private uint revision = 1;

        public DBusMenu (Tray tray, MenuEntry[] entries) {
            this.tray = tray;
            this.entries = entries;
        }

        [DBus (name = "Version")]
        public uint version { get { return 3; } }
        [DBus (name = "TextDirection")]
        public string text_direction { owned get { return "ltr"; } }
        [DBus (name = "Status")]
        public string status { owned get { return "normal"; } }
        [DBus (name = "IconThemePath")]
        public string[] icon_theme_path { owned get { return {}; } }

        public signal void ItemsPropertiesUpdated (
            [DBus (signature = "a(ia{sv})")] Variant updated,
            [DBus (signature = "a(ias)")] Variant removed);
        public signal void LayoutUpdated (uint revision, int parent);
        public signal void ItemActivationRequested (int id, uint timestamp);

        private Variant build_item (int id, bool with_children) {
            var props = new VariantBuilder (new VariantType ("a{sv}"));
            if (id == 0) {
                props.add ("{sv}", "children-display", new Variant.string ("submenu"));
            } else {
                var e = _entry (id);
                if (e != null && e.is_separator) {
                    props.add ("{sv}", "type", new Variant.string ("separator"));
                } else {
                    props.add ("{sv}", "label", new Variant.string (e != null ? e.label : ""));
                    props.add ("{sv}", "enabled", new Variant.boolean (true));
                    props.add ("{sv}", "visible", new Variant.boolean (true));
                }
            }
            var children = new VariantBuilder (new VariantType ("av"));
            if (id == 0 && with_children) {
                foreach (var e in entries)
                    children.add ("v", build_item (e.id, false));
            }
            var tb = new VariantBuilder (new VariantType ("(ia{sv}av)"));
            tb.add_value (new Variant.int32 (id));
            tb.add_value (props.end ());
            tb.add_value (children.end ());
            return tb.end ();
        }

        private MenuEntry? _entry (int id) {
            foreach (var e in entries)
                if (e.id == id) return e;
            return null;
        }

        [DBus (name = "GetLayout")]
        public void get_layout (int parent_id, int recursion_depth, string[] property_names,
                out uint revision_out, [DBus (signature = "(ia{sv}av)")] out Variant layout) {
            revision_out = revision;
            layout = build_item (parent_id, true);
        }

        [DBus (name = "GetGroupProperties")]
        public void get_group_properties (int[] ids, string[] property_names,
                [DBus (signature = "a(ia{sv})")] out Variant props) {
            var arr = new VariantBuilder (new VariantType ("a(ia{sv})"));
            foreach (int id in ids) {
                var item = build_item (id, false);
                // item is (i a{sv} av); re-emit as (i a{sv}).
                int iid = item.get_child_value (0).get_int32 ();
                var pv = item.get_child_value (1);
                var eb = new VariantBuilder (new VariantType ("(ia{sv})"));
                eb.add_value (new Variant.int32 (iid));
                eb.add_value (pv);
                arr.add_value (eb.end ());
            }
            props = arr.end ();
        }

        [DBus (name = "GetProperty")]
        public void get_property_dbus (int id, string name, out Variant val) {
            var e = _entry (id);
            if (name == "label") val = new Variant.string (e != null ? e.label : "");
            else if (name == "enabled") val = new Variant.boolean (true);
            else if (name == "visible") val = new Variant.boolean (true);
            else val = new Variant.string ("");
        }

        [DBus (name = "Event")]
        public void event (int id, string event_id, Variant data, uint timestamp) {
            if (event_id == "clicked")
                tray.menu_item_clicked (id);
        }

        [DBus (name = "EventGroup")]
        public void event_group ([DBus (signature = "a(isvu)")] Variant events,
                out int[] id_errors) {
            id_errors = {};
        }

        [DBus (name = "AboutToShow")]
        public void about_to_show (int id, out bool need_update) {
            need_update = false;
        }

        [DBus (name = "AboutToShowGroup")]
        public void about_to_show_group (int[] ids, out int[] updates_needed, out int[] id_errors) {
            updates_needed = {};
            id_errors = {};
        }
    }

    // ---- Tray manager ----------------------------------------------------
    public class Tray : Object {
        public signal void activate_requested ();
        public signal void open_app_requested ();
        public signal void quit_requested ();
        public signal void mode_requested (string mode);

        public string icon_theme_path { get; set; default = ""; }

        private Application app;
        private DBusConnection? conn = null;
        private uint owner_id = 0;
        private uint sni_reg = 0;
        private uint menu_reg = 0;
        private SNItem? sni = null;
        private DBusMenu? menu = null;
        private string bus_name;

        // Menu item ids.
        private const int ID_OPEN_APP = 1;
        private const int ID_POPUP    = 2;
        private const int ID_SEP1     = 3;
        private const int ID_TODO     = 4;
        private const int ID_JIRA     = 5;
        private const int ID_GH       = 6;
        private const int ID_SEP2     = 7;
        private const int ID_QUIT     = 8;

        public Tray (Application app) {
            this.app = app;
            bus_name = "org.kde.StatusNotifierItem-%d-1".printf ((int) Posix.getpid ());
            // If our icon isn't in the theme, point the host at our data dir.
            _resolve_icon_theme_path ();
        }

        private void _resolve_icon_theme_path () {
            // Prefer an installed hicolor icon (found via theme); otherwise
            // expose the first data dir that actually contains our icon.
            foreach (var dir in Environment.get_system_data_dirs ()) {
                string p = Path.build_filename (dir, "icons");
                string svg = Path.build_filename (p, "hicolor", "scalable", "apps", APP_ID + ".svg");
                if (FileUtils.test (svg, FileTest.EXISTS)) { icon_theme_path = p; return; }
            }
            string local = Path.build_filename (Environment.get_user_data_dir (), "icons");
            icon_theme_path = local;
        }

        public void register () {
            var entries = new MenuEntry[] {
                { ID_OPEN_APP, "Abrir aplicación", false },
                { ID_POPUP,    "Ventanita",        false },
                { ID_SEP1,     "",                 true  },
                { ID_TODO,     "ToDo",             false },
                { ID_JIRA,     "Jira",             false },
                { ID_GH,       "GitHub Projects",  false },
                { ID_SEP2,     "",                 true  },
                { ID_QUIT,     "Salir",            false }
            };
            sni = new SNItem (this);
            menu = new DBusMenu (this, entries);

            owner_id = Bus.own_name (
                BusType.SESSION, bus_name, BusNameOwnerFlags.NONE,
                on_bus_acquired,
                () => { },
                () => { warning ("Tray: lost bus name %s", bus_name); });
        }

        private void on_bus_acquired (DBusConnection connection, string name) {
            conn = connection;
            try {
                sni_reg = conn.register_object ("/StatusNotifierItem", sni);
                menu_reg = conn.register_object ("/MenuBar", menu);
            } catch (Error e) {
                warning ("Tray: register_object failed: %s", e.message);
                return;
            }
            _register_with_watcher.begin ();
        }

        private async void _register_with_watcher () {
            try {
                yield conn.call (
                    "org.kde.StatusNotifierWatcher",
                    "/StatusNotifierWatcher",
                    "org.kde.StatusNotifierWatcher",
                    "RegisterStatusNotifierItem",
                    new Variant ("(s)", bus_name),
                    null, DBusCallFlags.NONE, -1, null);
            } catch (Error e) {
                warning ("Tray: no StatusNotifierWatcher available (%s). " +
                         "Install a tray/AppIndicator extension to see the icon.", e.message);
            }
        }

        public void menu_item_clicked (int id) {
            switch (id) {
                case ID_OPEN_APP: open_app_requested (); break;
                case ID_POPUP:    activate_requested (); break;
                case ID_TODO:     mode_requested ("todo"); activate_requested (); break;
                case ID_JIRA:     mode_requested ("jira"); activate_requested (); break;
                case ID_GH:       mode_requested ("gh"); activate_requested (); break;
                case ID_QUIT:     quit_requested (); break;
                default: break;
            }
        }

        public void unregister () {
            if (conn != null) {
                if (sni_reg != 0) { conn.unregister_object (sni_reg); sni_reg = 0; }
                if (menu_reg != 0) { conn.unregister_object (menu_reg); menu_reg = 0; }
            }
            if (owner_id != 0) { Bus.unown_name (owner_id); owner_id = 0; }
        }
    }
}
