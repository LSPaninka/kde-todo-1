/*
 * Preferences.vala — Adw.PreferencesDialog exposing every GSettings key:
 * General, Window & tray, ToDo categories, Jira, GitHub Projects and Notion.
 * Simple scalar keys are bound directly; the parallel string-list category
 * config is edited through small helper rows.
 */

namespace Ct {

    public class Preferences : Adw.PreferencesDialog {
        private Application app;
        private Config config;
        private GLib.Settings s;

        public Preferences (Application app) {
            this.app = app;
            this.config = app.config;
            this.s = app.config.settings;
            title = "Preferencias";
            add (build_general ());
            add (build_window ());
            add (build_todo ());
            add (build_jira ());
            add (build_gh ());
            add (build_notion ());
        }

        // ================= General =================
        private Adw.PreferencesPage build_general () {
            var page = new Adw.PreferencesPage () { title = "General", icon_name = "preferences-system-symbolic" };
            var g = new Adw.PreferencesGroup () { title = "Modo" };

            var mode = new Adw.ComboRow () { title = "Modo activo" };
            string[] modes = { "todo", "jira", "gh" };
            string[] labels = { "ToDo (local)", "Jira", "GitHub Projects" };
            mode.model = new Gtk.StringList (labels);
            mode.selected = _index_of (modes, config.mode, 0);
            mode.notify["selected"].connect (() => config.mode = modes[mode.selected]);
            s.changed["mode"].connect (() => mode.selected = _index_of (modes, config.mode, 0));
            g.add (mode);
            page.add (g);

            var g2 = new Adw.PreferencesGroup () { title = "Apariencia de tareas" };
            var prio = new Adw.SwitchRow () { title = "Mostrar insignias de prioridad" };
            s.bind ("show-priority-icons", prio, "active", SettingsBindFlags.DEFAULT);
            g2.add (prio);
            var confirm = new Adw.SwitchRow () { title = "Confirmar al eliminar tareas archivadas" };
            s.bind ("confirm-delete", confirm, "active", SettingsBindFlags.DEFAULT);
            g2.add (confirm);
            page.add (g2);
            return page;
        }

        // ================= Window & tray =================
        private Adw.PreferencesPage build_window () {
            var page = new Adw.PreferencesPage () { title = "Ventana", icon_name = "video-display-symbolic" };

            var gw = new Adw.PreferencesGroup () { title = "Ventana principal" };
            gw.add (_spin ("main-width", "Ancho (px)", 600, 4000, 20));
            gw.add (_spin ("main-height", "Alto (px)", 400, 3000, 20));
            page.add (gw);

            var gp = new Adw.PreferencesGroup () {
                title = "Ventanita de la bandeja",
                description = "Tamaño de la ventana emergente que abre el icono de la barra superior."
            };
            gp.add (_spin ("popup-width", "Ancho (px)", 480, 2400, 20));
            gp.add (_spin ("popup-height", "Alto (px)", 360, 1800, 20));
            gp.add (_spin ("popup-scale", "Escala del contenido (%)", 70, 130, 5));
            var autohide = new Adw.SwitchRow () { title = "Cerrar al perder el foco",
                subtitle = "Se comporta como un widget momentáneo (se cierra al clickear afuera)" };
            s.bind ("popup-autohide", autohide, "active", SettingsBindFlags.DEFAULT);
            gp.add (autohide);
            var frameless = new Adw.SwitchRow () { title = "Sin barra de título (aspecto de widget)" };
            s.bind ("popup-frameless", frameless, "active", SettingsBindFlags.DEFAULT);
            gp.add (frameless);
            page.add (gp);

            var gt = new Adw.PreferencesGroup () { title = "Bandeja y segundo plano" };
            var tray = new Adw.SwitchRow () { title = "Mostrar icono en la barra superior",
                subtitle = "StatusNotifierItem (requiere soporte de AppIndicator)" };
            s.bind ("show-tray-icon", tray, "active", SettingsBindFlags.DEFAULT);
            gt.add (tray);
            var bg = new Adw.SwitchRow () { title = "Seguir en segundo plano al cerrar la ventana",
                subtitle = "Cerrá del todo con «Salir» en el menú del icono de la bandeja" };
            s.bind ("run-in-background", bg, "active", SettingsBindFlags.DEFAULT);
            gt.add (bg);
            var hidden = new Adw.SwitchRow () { title = "Arrancar oculto (solo en la bandeja)" };
            s.bind ("start-hidden", hidden, "active", SettingsBindFlags.DEFAULT);
            gt.add (hidden);
            page.add (gt);
            return page;
        }

        // ================= ToDo categories =================
        private Adw.PreferencesGroup? _todo_cats_group;
        private Adw.PreferencesPage build_todo () {
            var page = new Adw.PreferencesPage () { title = "Categorías", icon_name = "view-list-symbolic" };
            var g = new Adw.PreferencesGroup () { title = "Categorías ToDo (1–7)" };
            g.add (_spin ("category-count", "Cantidad de categorías", 1, 7, 1));
            page.add (g);

            _todo_cats_group = new Adw.PreferencesGroup () { title = "Nombres y colores" };
            page.add (_todo_cats_group);
            rebuild_todo_cats ();
            s.changed["category-count"].connect (rebuild_todo_cats);
            return page;
        }

        private void rebuild_todo_cats () {
            _clear_group (_todo_cats_group);
            int n = config.category_count;
            for (int i = 0; i < n; i++) {
                var row = new Adw.EntryRow () { title = "Categoría %d".printf (i + 1) };
                row.text = config.strv_at ("category-names", i, "");
                int idx = i;
                row.changed.connect (() => write_strv_at ("category-names", idx, row.text));
                var color = new Gtk.Entry () { text = config.strv_at ("category-colors", i, "#3498db"),
                    max_width_chars = 9, valign = Gtk.Align.CENTER, tooltip_text = "Color hex" };
                color.changed.connect (() => write_strv_at ("category-colors", idx, color.text));
                row.add_suffix (color);
                _track_add (_todo_cats_group, row);
            }
        }

        // ================= Jira =================
        private Adw.PreferencesGroup? _jira_cats_group;
        private Gtk.Label? _jira_test_label;
        private Adw.PreferencesPage build_jira () {
            var page = new Adw.PreferencesPage () { title = "Jira", icon_name = "network-server-symbolic" };

            var g = new Adw.PreferencesGroup () { title = "Conexión" };
            g.add (_entry ("jira-site", "Sitio (https://…atlassian.net)"));
            g.add (_entry ("jira-email", "Correo"));
            g.add (_password ("jira-token", "Token de API"));
            g.add (_entry ("jira-jql", "Consulta JQL"));
            var test = new Adw.ActionRow () { title = "Probar conexión" };
            var tb = new Gtk.Button.with_label ("Probar") { valign = Gtk.Align.CENTER };
            _jira_test_label = new Gtk.Label ("") { xalign = 1, wrap = true };
            _jira_test_label.add_css_class ("dim");
            tb.clicked.connect (() => {
                _jira_test_label.label = "Probando…";
                app.jira.test_connection.begin (config.get_string ("jira-site"),
                    config.get_string ("jira-email"), config.get_string ("jira-token"), (obj, res) => {
                    string msg; app.jira.test_connection.end (res, out msg);
                    _jira_test_label.label = msg;
                });
            });
            test.add_suffix (_jira_test_label);
            test.add_suffix (tb);
            g.add (test);
            page.add (g);

            var g2 = new Adw.PreferencesGroup () { title = "Actualización" };
            g2.add (_spin ("jira-refresh-minutes", "Intervalo de refresco (min, 0 = manual)", 0, 1440, 1));
            g2.add (_spin ("jira-max-results", "Máximo de incidencias", 10, 200, 10));
            page.add (g2);

            var g3 = new Adw.PreferencesGroup () { title = "Categorías Jira (tabs)" };
            g3.add (_spin ("jira-category-count", "Cantidad de categorías", 1, 10, 1));
            page.add (g3);
            _jira_cats_group = new Adw.PreferencesGroup () { title = "Filtros por categoría",
                description = "Campo: statusCategory / issuetype / status / priority (vacío = todo). Valor: usá ';' para OR." };
            page.add (_jira_cats_group);
            rebuild_jira_cats ();
            s.changed["jira-category-count"].connect (rebuild_jira_cats);
            return page;
        }

        private void rebuild_jira_cats () {
            _clear_group (_jira_cats_group);
            int n = int.min (10, int.max (1, config.get_int ("jira-category-count")));
            string[] fields = { "", "statusCategory", "issuetype", "status", "priority" };
            for (int i = 0; i < n; i++) {
                int idx = i;
                var exp = new Adw.ExpanderRow () { title = config.strv_at ("jira-category-names", i, "Cat %d".printf (i + 1)) };
                var name = new Adw.EntryRow () { title = "Nombre" };
                name.text = config.strv_at ("jira-category-names", i, "");
                name.changed.connect (() => { write_strv_at ("jira-category-names", idx, name.text); exp.title = name.text; });
                exp.add_row (name);
                var field = new Adw.ComboRow () { title = "Campo" };
                field.model = new Gtk.StringList (fields);
                field.selected = _index_of (fields, config.strv_at ("jira-category-filter-fields", i, ""), 0);
                field.notify["selected"].connect (() => write_strv_at ("jira-category-filter-fields", idx, fields[field.selected]));
                exp.add_row (field);
                var val = new Adw.EntryRow () { title = "Valor" };
                val.text = config.strv_at ("jira-category-filter-values", i, "");
                val.changed.connect (() => write_strv_at ("jira-category-filter-values", idx, val.text));
                exp.add_row (val);
                var color = new Adw.EntryRow () { title = "Color hex" };
                color.text = config.strv_at ("jira-category-colors", i, "#42526e");
                color.changed.connect (() => write_strv_at ("jira-category-colors", idx, color.text));
                exp.add_row (color);
                _track_add (_jira_cats_group, exp);
            }
        }

        // ================= GitHub =================
        private Adw.PreferencesGroup? _gh_cats_group;
        private Gtk.Label? _gh_test_label;
        private Adw.PreferencesPage build_gh () {
            var page = new Adw.PreferencesPage () { title = "GitHub", icon_name = "applications-development-symbolic" };

            var g = new Adw.PreferencesGroup () { title = "Conexión" };
            g.add (_password ("gh-token", "Personal Access Token"));
            g.add (_entry ("gh-owner", "Owner (usuario u organización)"));
            var otype = new Adw.ComboRow () { title = "Tipo de owner" };
            string[] otypes = { "user", "organization" };
            otype.model = new Gtk.StringList (otypes);
            otype.selected = _index_of (otypes, config.get_string ("gh-owner-type"), 0);
            otype.notify["selected"].connect (() => config.set_string ("gh-owner-type", otypes[otype.selected]));
            g.add (otype);
            g.add (_spin ("gh-project-number", "Número de proyecto (V2)", 1, 99999, 1));
            g.add (_entry ("gh-status-field", "Campo de estado (single-select)"));
            var closed = new Adw.SwitchRow () { title = "Incluir cerrados / merged" };
            s.bind ("gh-include-closed", closed, "active", SettingsBindFlags.DEFAULT);
            g.add (closed);
            var test = new Adw.ActionRow () { title = "Probar conexión" };
            var tb = new Gtk.Button.with_label ("Probar") { valign = Gtk.Align.CENTER };
            _gh_test_label = new Gtk.Label ("") { xalign = 1, wrap = true };
            _gh_test_label.add_css_class ("dim");
            tb.clicked.connect (() => {
                _gh_test_label.label = "Probando…";
                app.gh.test_connection.begin (config.get_string ("gh-token"), (obj, res) => {
                    string msg; app.gh.test_connection.end (res, out msg);
                    _gh_test_label.label = msg;
                });
            });
            test.add_suffix (_gh_test_label);
            test.add_suffix (tb);
            g.add (test);
            page.add (g);

            var g2 = new Adw.PreferencesGroup () { title = "Actualización" };
            g2.add (_spin ("gh-refresh-minutes", "Intervalo de refresco (min, 0 = manual)", 0, 1440, 1));
            g2.add (_spin ("gh-max-results", "Máximo de ítems", 10, 300, 10));
            page.add (g2);

            var g3 = new Adw.PreferencesGroup () { title = "Categorías GitHub (tabs)" };
            g3.add (_spin ("gh-category-count", "Cantidad de categorías", 1, 4, 1));
            page.add (g3);
            _gh_cats_group = new Adw.PreferencesGroup () { title = "Filtros por categoría",
                description = "Campo: status / type / state / repo (vacío = todo). Valor: usá ';' para OR." };
            page.add (_gh_cats_group);
            rebuild_gh_cats ();
            s.changed["gh-category-count"].connect (rebuild_gh_cats);
            return page;
        }

        private void rebuild_gh_cats () {
            _clear_group (_gh_cats_group);
            int n = int.min (4, int.max (1, config.get_int ("gh-category-count")));
            string[] fields = { "", "status", "type", "state", "repo" };
            for (int i = 0; i < n; i++) {
                int idx = i;
                var exp = new Adw.ExpanderRow () { title = config.strv_at ("gh-category-names", i, "Cat %d".printf (i + 1)) };
                var name = new Adw.EntryRow () { title = "Nombre" };
                name.text = config.strv_at ("gh-category-names", i, "");
                name.changed.connect (() => { write_strv_at ("gh-category-names", idx, name.text); exp.title = name.text; });
                exp.add_row (name);
                var field = new Adw.ComboRow () { title = "Campo" };
                field.model = new Gtk.StringList (fields);
                field.selected = _index_of (fields, config.strv_at ("gh-category-filter-fields", i, ""), 0);
                field.notify["selected"].connect (() => write_strv_at ("gh-category-filter-fields", idx, fields[field.selected]));
                exp.add_row (field);
                var val = new Adw.EntryRow () { title = "Valor" };
                val.text = config.strv_at ("gh-category-filter-values", i, "");
                val.changed.connect (() => write_strv_at ("gh-category-filter-values", idx, val.text));
                exp.add_row (val);
                var color = new Adw.EntryRow () { title = "Color hex" };
                color.text = config.strv_at ("gh-category-colors", i, "#6e7681");
                color.changed.connect (() => write_strv_at ("gh-category-colors", idx, color.text));
                exp.add_row (color);
                _track_add (_gh_cats_group, exp);
            }
        }

        // ================= Notion =================
        private Gtk.Label? _notion_test_label;
        private Adw.PreferencesPage build_notion () {
            var page = new Adw.PreferencesPage () { title = "Notion", icon_name = "emblem-synchronizing-symbolic" };

            var g = new Adw.PreferencesGroup () { title = "Sincronización con Notion (modo ToDo)",
                description = "Sincronización bidireccional con una base de datos de Notion." };
            g.add (_password ("notion-api-token", "Token de integración interna"));
            g.add (_entry ("notion-parent-page-id", "ID de la página padre (para crear la base)"));
            g.add (_entry ("notion-database-id", "ID de la base de datos (se completa solo)"));

            var test = new Adw.ActionRow () { title = "Probar token" };
            var tb = new Gtk.Button.with_label ("Probar") { valign = Gtk.Align.CENTER };
            _notion_test_label = new Gtk.Label ("") { xalign = 1, wrap = true };
            _notion_test_label.add_css_class ("dim");
            tb.clicked.connect (() => {
                _notion_test_label.label = "Probando…";
                app.notion_sync.test_connection.begin (config.get_string ("notion-api-token"), (obj, res) => {
                    string msg; app.notion_sync.test_connection.end (res, out msg);
                    _notion_test_label.label = msg;
                });
            });
            test.add_suffix (_notion_test_label);
            test.add_suffix (tb);
            g.add (test);

            var create = new Adw.ActionRow () { title = "Crear base de datos", subtitle = "Bajo la página padre indicada" };
            var cb = new Gtk.Button.with_label ("Crear") { valign = Gtk.Align.CENTER };
            cb.clicked.connect (() => {
                app.notion_sync.create_database.begin ((obj, res) => {
                    string result; bool ok = app.notion_sync.create_database.end (res, out result);
                    _notion_test_label.label = ok ? "Base creada." : result;
                });
            });
            create.add_suffix (cb);
            g.add (create);

            var syncnow = new Adw.ActionRow () { title = "Sincronizar ahora" };
            var sb = new Gtk.Button.with_label ("Sincronizar") { valign = Gtk.Align.CENTER };
            sb.clicked.connect (() => app.notion_sync.sync.begin ());
            syncnow.add_suffix (sb);
            g.add (syncnow);
            page.add (g);

            var g2 = new Adw.PreferencesGroup () { title = "Opciones" };
            var on_open = new Adw.SwitchRow () { title = "Sincronizar al abrir la app / ventanita" };
            s.bind ("notion-sync-on-open", on_open, "active", SettingsBindFlags.DEFAULT);
            g2.add (on_open);
            g2.add (_spin ("notion-refresh-minutes", "Intervalo de auto-sync (min, 0 = manual)", 0, 1440, 1));
            page.add (g2);
            return page;
        }

        // ================= helpers =================
        private Adw.SpinRow _spin (string key, string title, int lo, int hi, int step) {
            var row = new Adw.SpinRow.with_range (lo, hi, step) { title = title };
            s.bind (key, row, "value", SettingsBindFlags.DEFAULT);
            return row;
        }
        private Adw.EntryRow _entry (string key, string title) {
            var row = new Adw.EntryRow () { title = title };
            s.bind (key, row, "text", SettingsBindFlags.DEFAULT);
            return row;
        }
        private Adw.PasswordEntryRow _password (string key, string title) {
            var row = new Adw.PasswordEntryRow () { title = title };
            s.bind (key, row, "text", SettingsBindFlags.DEFAULT);
            return row;
        }

        private void write_strv_at (string key, int index, string val) {
            var arr = s.get_strv (key);
            if (index >= arr.length) {
                var grown = new string[index + 1];
                for (int i = 0; i < grown.length; i++) grown[i] = (i < arr.length) ? arr[i] : "";
                arr = grown;
            }
            if (arr[index] == val) return;
            arr[index] = val;
            s.set_strv (key, arr);
        }

        private static uint _index_of (string[] arr, string val, uint fallback) {
            for (uint i = 0; i < arr.length; i++)
                if (arr[i] == val) return i;
            return fallback;
        }

        // track rows added per group so we can clear them on rebuild
        private Gee.HashMap<Adw.PreferencesGroup, Gee.ArrayList<Gtk.Widget>> _track =
            new Gee.HashMap<Adw.PreferencesGroup, Gee.ArrayList<Gtk.Widget>> ();
        private Gee.ArrayList<Gtk.Widget> _tracked (Adw.PreferencesGroup g) {
            if (!_track.has_key (g)) _track.set (g, new Gee.ArrayList<Gtk.Widget> ());
            return _track.get (g);
        }
        private void _track_add (Adw.PreferencesGroup g, Gtk.Widget w) {
            g.add (w);
            _tracked (g).add (w);
        }
        private void _clear_group (Adw.PreferencesGroup? g) {
            if (g == null) return;
            foreach (var w in _tracked (g)) g.remove (w);
            _tracked (g).clear ();
        }
    }
}
