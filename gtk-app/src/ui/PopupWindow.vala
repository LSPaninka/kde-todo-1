/*
 * PopupWindow.vala — the small tray popup (default 1000x700, parametrizable
 * via popup-width / popup-height / popup-scale). Left-clicking the tray icon
 * toggles it. It hosts the same three modes and a button to open the full app.
 * Closing it just hides it (the app stays in the background).
 */

namespace Ct {

    public class PopupWindow : Adw.Window {
        private Application app;
        private Config config;
        private Gtk.CssProvider? scale_provider = null;

        public PopupWindow (Application app) {
            Object (application: app);
            this.app = app;
            this.config = app.config;

            title = "Categorized ToDo";
            icon_name = APP_ID;
            resizable = true;
            apply_size ();
            apply_scale ();

            var content = new ModeContent (app);

            var tv = new Adw.ToolbarView ();
            var header = new Adw.HeaderBar () { show_end_title_buttons = true };
            header.title_widget = content.make_switcher ();

            var open_app = new Gtk.Button.from_icon_name ("view-fullscreen-symbolic");
            open_app.tooltip_text = "Abrir la aplicación completa";
            open_app.clicked.connect (() => {
                app.activate_main ();
                set_visible (false);
            });
            header.pack_start (open_app);

            var menu = new Menu ();
            menu.append ("Preferencias", "app.preferences");
            menu.append ("Abrir aplicación", "app.open-app");
            menu.append ("Acerca de", "app.about");
            menu.append ("Salir", "app.quit");
            header.pack_end (new Gtk.MenuButton () { icon_name = "open-menu-symbolic", menu_model = menu, primary = true });

            tv.add_top_bar (header);
            tv.content = content;
            set_content (tv);

            // Hide (don't destroy) on close so it can be reopened from the tray.
            close_request.connect (() => { set_visible (false); return true; });

            // Escape hides the popup.
            var key = new Gtk.EventControllerKey ();
            key.key_pressed.connect ((keyval, keycode, state) => {
                if (keyval == Gdk.Key.Escape) { set_visible (false); return true; }
                return false;
            });
            ((Gtk.Widget) this).add_controller (key);

            config.changed.connect ((k) => {
                if (k == "popup-width" || k == "popup-height") apply_size ();
                if (k == "popup-scale") apply_scale ();
            });
        }

        private void apply_size () {
            set_default_size (config.popup_width, config.popup_height);
        }

        private void apply_scale () {
            int scale = config.popup_scale;
            add_css_class ("ct-popup-scaled");
            if (scale_provider != null) {
                Gtk.StyleContext.remove_provider_for_display (get_display (), scale_provider);
                scale_provider = null;
            }
            if (scale != 100) {
                // Scope the font-size to this popup only (class selector). An
                // absolute point size avoids the compounding of em/% across the
                // nested widget tree. 10.5pt is the typical GNOME default.
                double pt = 10.5 * (scale / 100.0);
                scale_provider = new Gtk.CssProvider ();
                scale_provider.load_from_string (".ct-popup-scaled { font-size: %.1fpt; }".printf (pt));
                Gtk.StyleContext.add_provider_for_display (
                    get_display (), scale_provider, Gtk.STYLE_PROVIDER_PRIORITY_USER);
            }
        }
    }
}
