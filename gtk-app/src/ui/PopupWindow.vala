/*
 * PopupWindow.vala — the tray "ventanita": a momentary, frameless panel (like
 * the GNOME calendar/notification popup) rather than a regular window. It has
 * no title bar and, by default, auto-closes as soon as it loses focus (click
 * outside). Default 1000x700, parametrizable via popup-* settings.
 *
 * Note: on GNOME Wayland a third-party app cannot anchor a toplevel under the
 * tray icon (only the shell can). So the panel opens/closes momentarily and
 * dismisses on click-away, but the compositor decides its on-screen placement.
 */

namespace Ct {

    public class PopupWindow : Adw.Window {
        private Application app;
        private Config config;
        private Gtk.CssProvider? scale_provider = null;

        // Monotonic time (µs) of the last auto-hide, so a tray click that both
        // defocuses (hides) and toggles doesn't immediately re-open it.
        public int64 last_hidden_us { get; private set; default = 0; }

        public PopupWindow (Application app) {
            Object (application: app);
            this.app = app;
            this.config = app.config;

            title = "Categorized ToDo";
            icon_name = APP_ID;
            resizable = true;
            add_css_class ("ct-popup");
            set_decorated (!config.get_bool ("popup-frameless"));
            apply_size ();
            apply_scale ();

            var content = new ModeContent (app);

            // Compact top bar (no Adw.HeaderBar → no title bar / window buttons).
            var topbar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                margin_top = 6, margin_bottom = 6, margin_start = 8, margin_end = 8
            };
            var switcher = content.make_switcher ();
            switcher.hexpand = true;
            switcher.halign = Gtk.Align.CENTER;
            topbar.append (switcher);

            var open_app = new Gtk.Button.from_icon_name ("view-fullscreen-symbolic") { valign = Gtk.Align.CENTER };
            open_app.add_css_class ("flat");
            open_app.tooltip_text = "Abrir la aplicación completa";
            open_app.clicked.connect (() => { app.activate_main (); set_visible (false); });
            topbar.append (open_app);

            var menu = new Menu ();
            menu.append ("Preferencias", "app.preferences");
            menu.append ("Abrir aplicación", "app.open-app");
            menu.append ("Acerca de", "app.about");
            menu.append ("Salir", "app.quit");
            topbar.append (new Gtk.MenuButton () {
                icon_name = "open-menu-symbolic", menu_model = menu, valign = Gtk.Align.CENTER,
                css_classes = { "flat" }
            });

            var close = new Gtk.Button.from_icon_name ("window-close-symbolic") { valign = Gtk.Align.CENTER };
            close.add_css_class ("flat");
            close.tooltip_text = "Cerrar";
            close.clicked.connect (() => set_visible (false));
            topbar.append (close);

            var root = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            root.append (topbar);
            root.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            root.append (content);
            set_content (root);

            // Close (hide) on Escape.
            var key = new Gtk.EventControllerKey ();
            key.key_pressed.connect ((keyval, keycode, state) => {
                if (keyval == Gdk.Key.Escape) { set_visible (false); return true; }
                return false;
            });
            ((Gtk.Widget) this).add_controller (key);

            // Momentary-widget behaviour: hide when the panel loses focus.
            notify["is-active"].connect (() => {
                if (!is_active && visible && config.get_bool ("popup-autohide")) {
                    last_hidden_us = get_monotonic_time ();
                    set_visible (false);
                }
            });

            close_request.connect (() => { set_visible (false); return true; });

            config.changed.connect ((k) => {
                if (k == "popup-width" || k == "popup-height") apply_size ();
                if (k == "popup-scale") apply_scale ();
                if (k == "popup-frameless") set_decorated (!config.get_bool ("popup-frameless"));
            });
        }

        private void apply_size () {
            set_default_size (config.popup_width, config.popup_height);
        }

        private void apply_scale () {
            int scale = config.popup_scale;
            if (scale_provider != null) {
                Gtk.StyleContext.remove_provider_for_display (get_display (), scale_provider);
                scale_provider = null;
            }
            if (scale != 100) {
                double pt = 10.5 * (scale / 100.0);
                scale_provider = new Gtk.CssProvider ();
                scale_provider.load_from_string (".ct-popup { font-size: %.1fpt; }".printf (pt));
                Gtk.StyleContext.add_provider_for_display (
                    get_display (), scale_provider, Gtk.STYLE_PROVIDER_PRIORITY_USER);
            }
        }
    }
}
