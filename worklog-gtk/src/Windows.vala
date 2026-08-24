/*
 * Windows.vala - the two top-level windows.
 *
 * MainWindow : full desktop application window (resizable). Header bar with a
 *              hamburger menu (Preferencias / Acerca de / Salir).
 * PopupWindow: the small 1000x700 floating "clock" window opened from the
 *              top-bar indicator. Same WorklogView, plus an "Abrir aplicación"
 *              button in the header.
 *
 * Both hide instead of quitting when "run in background" is on, so the app
 * keeps living in the tray; the only true exit is the indicator's "Salir".
 */

namespace Worklog {

    public class MainWindow : Adw.ApplicationWindow {
        private App app;
        private Config cfg;
        private WorklogView view;

        public MainWindow(App app, Config cfg, JiraStore jira, JiraStore jira2, ClockifyStore clockify, GoogleStore google) {
            Object(application: app);
            this.app = app;
            this.cfg = cfg;
            set_title("Worklog Calendar");
            set_default_size(cfg.settings.get_int("window-width"), cfg.settings.get_int("window-height"));
            set_icon_name("io.github.peperina.WorklogCalendar");

            var toolbar = new Adw.ToolbarView();
            var header = new Adw.HeaderBar();
            var menu_btn = new Gtk.MenuButton();
            menu_btn.set_icon_name("open-menu-symbolic");
            menu_btn.set_menu_model(build_menu());
            header.pack_end(menu_btn);
            toolbar.add_top_bar(header);

            view = new WorklogView(cfg, jira, jira2, clockify, google, false);
            view.open_prefs_requested.connect(() => app.open_prefs(this));
            toolbar.set_content(view);
            set_content(toolbar);

            // Window actions.
            var prefs_action = new SimpleAction("preferences", null);
            prefs_action.activate.connect(() => app.open_prefs(this));
            add_action(prefs_action);
            var about_action = new SimpleAction("about", null);
            about_action.activate.connect(show_about);
            add_action(about_action);
            var quit_action = new SimpleAction("quit", null);
            quit_action.activate.connect(() => app.quit_app());
            add_action(quit_action);

            close_request.connect(() => {
                cfg.settings.set_int("window-width", get_width());
                cfg.settings.set_int("window-height", get_height());
                // Only hide to background when the tray can bring it back.
                if (cfg.run_in_background && cfg.show_tray_icon) { set_visible(false); return true; }
                return false;
            });
        }

        private GLib.MenuModel build_menu() {
            var menu = new GLib.Menu();
            menu.append("Preferencias", "win.preferences");
            menu.append("Acerca de", "win.about");
            menu.append("Salir", "win.quit");
            return menu;
        }

        public void sync() { view.sync_now(); }

        private void show_about() {
            var about = new Adw.AboutWindow();
            about.set_transient_for(this);
            about.set_application_name("Worklog Calendar");
            about.set_application_icon("io.github.peperina.WorklogCalendar");
            about.set_version("2.0.0");
            about.set_developer_name("Peperina");
            about.set_comments("Vista semanal de worklogs de Jira y Clockify para GNOME / Ubuntu 24.");
            about.set_license_type(Gtk.License.MIT_X11);
            about.set_website("https://github.com/lspaninka/kde-todo-1");
            about.present();
        }
    }

    // The floating "clock" popup. Styled as a momentary drop-down widget
    // (like the shell's calendar panel): frameless, fixed size, and it hides
    // itself as soon as focus leaves it — unless focus went to one of our own
    // dialogs (e.g. the worklog editor), in which case it stays open.
    public class PopupWindow : Adw.ApplicationWindow {
        private App app;
        private Config cfg;
        private WorklogView view;
        private uint hide_check_id = 0;

        public PopupWindow(App app, Config cfg, JiraStore jira, JiraStore jira2, ClockifyStore clockify, GoogleStore google) {
            Object(application: app);
            this.app = app;
            this.cfg = cfg;
            set_title("Worklog");
            set_default_size(cfg.settings.get_int("popup-width"), cfg.settings.get_int("popup-height"));
            set_icon_name("io.github.peperina.WorklogCalendar");

            // Widget look: no title bar, non-resizable, transparent window so
            // the rounded card shows through at the corners.
            set_decorated(false);
            set_resizable(false);
            add_css_class("worklog-popup");

            view = new WorklogView(cfg, jira, jira2, clockify, google, true);
            view.open_app_requested.connect(() => { app.show_main(); set_visible(false); });
            view.open_prefs_requested.connect(() => app.open_prefs(this));

            var card = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            card.add_css_class("worklog-popup-card");
            card.append(view);
            set_content(card);

            // Escape dismisses the popup.
            var keys = new Gtk.EventControllerKey();
            keys.key_pressed.connect((keyval, keycode, state) => {
                if (keyval == Gdk.Key.Escape) { set_visible(false); return true; }
                return false;
            });
            // Disambiguate from Gtk.ShortcutManager.add_controller.
            ((Gtk.Widget) this).add_controller(keys);

            // Auto-hide on focus loss (deferred so focus can settle on a child
            // dialog first).
            notify["is-active"].connect(on_active_changed);

            close_request.connect(() => {
                if (cfg.run_in_background) { set_visible(false); return true; }
                return false;
            });
        }

        // Ask for the popup to be placed near the tray icon. Called right after
        // present(); the surface only exists once mapped, so retry briefly.
        public void anchor_now() {
            int tries = 0;
            Timeout.add(40, () => {
                tries++;
                if (anchor_to_tray()) return Source.REMOVE;
                return (tries < 5) ? Source.CONTINUE : Source.REMOVE;
            });
        }

        // Place the popup under the top-right corner of the monitor, next to the
        // indicator. X11 only: on Wayland a client cannot position its own
        // window (GTK4 removed the API and Mutter does not allow it), so there
        // the compositor decides where it lands. See docs/SYSTEM_TRAY.md.
        private bool anchor_to_tray() {
            if (!cfg.popup_anchor_top_right) return true;   // nothing to do
            var surface = get_surface();
            if (surface == null) return false;              // not mapped yet
            var xsurf = surface as Gdk.X11.Surface;
            var xdisp = get_display() as Gdk.X11.Display;
            if (xsurf == null || xdisp == null) return true; // not X11: give up quietly

            var mon = get_display().get_monitor_at_surface(surface);
            if (mon == null) return true;
            Gdk.Rectangle geo = mon.get_geometry();
            if (geo.width <= 0) return true;

            int w = cfg.settings.get_int("popup-width");
            int h = cfg.settings.get_int("popup-height");
            int x = geo.x + geo.width - w - 8;
            int y = geo.y + cfg.popup_anchor_margin;
            if (x < geo.x) x = geo.x;
            if (y + h > geo.y + geo.height) y = int.max(geo.y, geo.y + geo.height - h);
            xdisp.get_xdisplay().move_window(xsurf.get_xid(), x, y);
            return true;
        }

        private void on_active_changed() {
            if (is_active) return;
            if (hide_check_id != 0) Source.remove(hide_check_id);
            hide_check_id = Timeout.add(180, () => {
                hide_check_id = 0;
                if (is_active) return false;               // regained focus
                foreach (var w in app.get_windows()) {      // a dialog of ours?
                    if (w != this && w.is_active) return false;
                }
                set_visible(false);
                return false;
            });
        }

        public void sync() { view.sync_now(); }
    }
}
