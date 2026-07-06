/*
 * Application.vala — the Adw.Application that owns the shared stores and the
 * two windows (full app + tray popup) plus the StatusNotifierItem tray icon.
 *
 * Background running: the app calls hold() at startup so it survives every
 * window being closed. The only way to actually quit is the tray icon's
 * right-click "Salir", the in-app menu "Salir", or `categorized-todo --quit`.
 */

namespace Ct {

    public class Application : Adw.Application {
        public Config config;
        public Database database;
        public TaskStore store;
        public JiraStore jira;
        public GhStore gh;
        public NotionSyncStore notion_sync;

        private MainWindow? main_window = null;
        private PopupWindow? popup_window = null;
        private Tray? tray = null;
        private bool held = false;

        public Application () {
            Object (
                application_id: APP_ID,
                flags: ApplicationFlags.HANDLES_COMMAND_LINE
            );
        }

        construct {
            add_main_option ("quit", 'q', 0, OptionArg.NONE, "Quit the running instance", null);
            add_main_option ("popup", 'p', 0, OptionArg.NONE, "Toggle the tray popup", null);
            add_main_option ("background", 'b', 0, OptionArg.NONE, "Start hidden in the background", null);
            add_main_option ("version", 'v', 0, OptionArg.NONE, "Print version and exit", null);
        }

        // Handle --version locally so it never registers/holds the app.
        public override int handle_local_options (VariantDict options) {
            if (options.contains ("version")) {
                stdout.printf ("categorized-todo %s\n", VERSION);
                return 0;
            }
            return -1;   // continue normal processing
        }

        public override void startup () {
            base.startup ();

            Widgets.init_css ();

            config = new Config ();
            database = new Database ();
            store = new TaskStore (config, database);
            jira = new JiraStore (config, database);
            gh = new GhStore (config, database);
            notion_sync = new NotionSyncStore (config, database, store);

            store.load ();
            jira.init ();
            gh.init ();
            notion_sync.init ();

            // Keep the process alive with no visible windows (background mode).
            hold ();
            held = true;

            _setup_actions ();

            if (config.get_bool ("show-tray-icon")) {
                tray = new Tray (this);
                tray.activate_requested.connect (() => toggle_popup ());
                tray.open_app_requested.connect (() => activate_main ());
                tray.quit_requested.connect (() => do_quit ());
                tray.mode_requested.connect ((m) => { config.mode = m; });
                tray.register ();
            }

            // React to config changes that affect the stores/tray.
            config.changed.connect (on_config_changed);

            // Initial fetches / sync.
            if (config.mode == "jira" && jira.last_fetched_at == 0) jira.fetch.begin ();
            if (config.mode == "gh" && gh.last_fetched_at == 0) gh.fetch.begin ();
            maybe_notion_sync ();
        }

        private void on_config_changed (string key) {
            switch (key) {
                case "category-count":
                    store.reassign_out_of_range_categories (config.category_count);
                    break;
                case "jira-refresh-minutes": jira.apply_refresh_schedule (); break;
                case "gh-refresh-minutes": gh.apply_refresh_schedule (); break;
                case "notion-refresh-minutes":
                case "notion-api-token":
                case "notion-database-id":
                    notion_sync.apply_refresh_schedule ();
                    break;
                case "show-tray-icon":
                    _apply_tray_visibility ();
                    break;
            }
        }

        private void _apply_tray_visibility () {
            bool want = config.get_bool ("show-tray-icon");
            if (want && tray == null) {
                tray = new Tray (this);
                tray.activate_requested.connect (() => toggle_popup ());
                tray.open_app_requested.connect (() => activate_main ());
                tray.quit_requested.connect (() => do_quit ());
                tray.mode_requested.connect ((m) => { config.mode = m; });
                tray.register ();
            } else if (!want && tray != null) {
                tray.unregister ();
                tray = null;
            }
        }

        public void maybe_notion_sync () {
            if (!config.get_bool ("notion-sync-on-open")) return;
            if (!notion_sync.is_configured ()) return;
            if (notion_sync.loading) return;
            notion_sync.sync.begin ();
        }

        // ---- actions ----------------------------------------------------
        private void _setup_actions () {
            var a_pref = new SimpleAction ("preferences", null);
            a_pref.activate.connect (() => show_preferences ());
            add_action (a_pref);
            set_accels_for_action ("app.preferences", { "<Primary>comma" });

            var a_about = new SimpleAction ("about", null);
            a_about.activate.connect (() => show_about ());
            add_action (a_about);

            var a_quit = new SimpleAction ("quit", null);
            a_quit.activate.connect (() => do_quit ());
            add_action (a_quit);
            set_accels_for_action ("app.quit", { "<Primary>q" });

            var a_popup = new SimpleAction ("popup", null);
            a_popup.activate.connect (() => toggle_popup ());
            add_action (a_popup);

            var a_openapp = new SimpleAction ("open-app", null);
            a_openapp.activate.connect (() => activate_main ());
            add_action (a_openapp);

            var a_mode = new SimpleAction ("set-mode", VariantType.STRING);
            a_mode.activate.connect ((param) => { config.mode = param.get_string (); });
            add_action (a_mode);
        }

        // ---- windows ----------------------------------------------------
        public override void activate () {
            activate_main ();
        }

        public void activate_main () {
            if (main_window == null) {
                main_window = new MainWindow (this);
            }
            main_window.present ();
        }

        public void toggle_popup () {
            if (popup_window == null) {
                popup_window = new PopupWindow (this);
            }
            if (popup_window.visible) {
                popup_window.set_visible (false);
            } else {
                maybe_notion_sync ();
                popup_window.present ();
            }
        }

        public void show_preferences () {
            var win = get_active_window () ?? (Gtk.Window?) main_window;
            var prefs = new Preferences (this);
            if (win != null) prefs.present (win);
            else prefs.present (null);
        }

        public void show_about () {
            var about = new Adw.AboutDialog () {
                application_name = "Categorized ToDo",
                application_icon = APP_ID,
                developer_name = "Categorized ToDo contributors",
                version = VERSION,
                license_type = Gtk.License.GPL_3_0,
                comments = "Categorized tasks with Jira and GitHub Projects integration.\nGTK 4 / libadwaita port of the KDE Plasma plasmoid."
            };
            var win = get_active_window ();
            about.present (win);
        }

        public void do_quit () {
            if (tray != null) tray.unregister ();
            if (popup_window != null) popup_window.destroy ();
            if (main_window != null) main_window.destroy ();
            if (held) { release (); held = false; }
            quit ();
        }

        // ---- command line -----------------------------------------------
        public override int command_line (ApplicationCommandLine cmdline) {
            var opts = cmdline.get_options_dict ();
            if (opts.contains ("quit")) {
                do_quit ();
                return 0;
            }
            if (opts.contains ("popup")) {
                toggle_popup ();
                return 0;
            }
            if (opts.contains ("background") && !config.get_bool ("start-hidden")) {
                // Just don't present a window; the tray keeps us alive.
                return 0;
            }
            if (config.get_bool ("start-hidden") && main_window == null && !_first_activated) {
                _first_activated = true;
                return 0;
            }
            _first_activated = true;
            activate_main ();
            return 0;
        }

        private bool _first_activated = false;
    }
}
