/*
 * MainWindow.vala — the full desktop window, plus the shared ModeContent
 * widget (ToDo / Jira / GitHub switcher) reused by the tray popup.
 *
 * Closing the window keeps the app alive in the background when
 * `run-in-background` is on and the tray icon is showing; otherwise it quits.
 */

namespace Ct {

    // Shared body: an Adw.ViewStack with the three mode views, kept in sync
    // with config.mode. Windows embed one and place a switcher in their header.
    public class ModeContent : Gtk.Box {
        public Adw.ViewStack stack { get; private set; }
        private Application app;
        private Config config;

        public ModeContent (Application app) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.app = app;
            this.config = app.config;

            stack = new Adw.ViewStack () { vexpand = true };
            var pt = stack.add_titled (new TodoView (app), "todo", "ToDo");
            pt.icon_name = "view-list-symbolic";
            var pj = stack.add_titled (new JiraView (app), "jira", "Jira");
            pj.icon_name = "network-server-symbolic";
            var pg = stack.add_titled (new GhView (app), "gh", "GitHub");
            pg.icon_name = "applications-development-symbolic";
            append (stack);

            string m = config.mode;
            if (stack.get_child_by_name (m) != null) stack.visible_child_name = m;

            stack.notify["visible-child-name"].connect (() => {
                if (stack.visible_child_name != null && stack.visible_child_name != config.mode)
                    config.mode = stack.visible_child_name;
            });
            config.changed.connect ((key) => {
                if (key == "mode" && stack.get_child_by_name (config.mode) != null
                    && stack.visible_child_name != config.mode)
                    stack.visible_child_name = config.mode;
            });
        }

        public Adw.ViewSwitcher make_switcher () {
            return new Adw.ViewSwitcher () { stack = stack, policy = Adw.ViewSwitcherPolicy.WIDE };
        }
    }

    public class MainWindow : Adw.ApplicationWindow {
        private Application app;
        private Config config;

        public MainWindow (Application app) {
            Object (application: app);
            this.app = app;
            this.config = app.config;

            title = "Categorized ToDo";
            icon_name = APP_ID;
            set_default_size (config.get_int ("main-width"), config.get_int ("main-height"));

            var content = new ModeContent (app);

            var tv = new Adw.ToolbarView ();
            var header = new Adw.HeaderBar ();
            header.title_widget = content.make_switcher ();

            var popup_btn = new Gtk.Button.from_icon_name ("view-restore-symbolic");
            popup_btn.tooltip_text = "Abrir la ventanita de la bandeja";
            popup_btn.clicked.connect (() => app.toggle_popup ());
            header.pack_start (popup_btn);

            header.pack_end (build_menu_button ());
            tv.add_top_bar (header);
            tv.content = content;
            set_content (tv);

            close_request.connect (on_close);
        }

        private Gtk.MenuButton build_menu_button () {
            var menu = new Menu ();
            menu.append ("Preferencias", "app.preferences");
            menu.append ("Ventanita de la bandeja", "app.popup");
            menu.append ("Acerca de", "app.about");
            menu.append ("Salir", "app.quit");
            var btn = new Gtk.MenuButton () { icon_name = "open-menu-symbolic", menu_model = menu, primary = true };
            return btn;
        }

        private bool on_close () {
            // Remember size.
            int w, h;
            get_default_size (out w, out h);
            if (w > 0 && h > 0) {
                config.set_int ("main-width", w);
                config.set_int ("main-height", h);
            }
            if (config.get_bool ("run-in-background") && config.get_bool ("show-tray-icon")) {
                set_visible (false);
                return true;   // keep app alive in background
            }
            app.do_quit ();
            return true;
        }
    }
}
