"""preferences.py - Adwaita preferences (General / Jira / Clockify / Sprint)."""
from __future__ import annotations

from gi.repository import Gtk, Adw, Gio

from . import APP_ID


class PreferencesWindow(Adw.PreferencesWindow):
    def __init__(self, parent, cfg, jira, clockify):
        super().__init__(transient_for=parent, modal=False)
        self.cfg = cfg
        self.jira = jira
        self.clockify = clockify
        self.set_title("Preferencias")
        self.set_default_size(620, 720)
        self.add(self._general())
        self.add(self._jira_page())
        self.add(self._clockify_page())
        self.add(self._sprint_page())

    # ---- pages ----
    def _general(self):
        page = Adw.PreferencesPage(title="General", icon_name="preferences-system-symbolic")

        view = Adw.PreferencesGroup(title="Vista")
        mode = Adw.ComboRow(title="Modo de vista", subtitle="Rango horario del grid")
        mode.set_model(Gtk.StringList.new(["9h (09:00–18:00)", "24h (00:00–24:00)"]))
        mode.set_selected(1 if self.cfg.view_mode == "24h" else 0)
        mode.connect("notify::selected", lambda r, _p: self.cfg.settings.set_string("view-mode", "24h" if r.get_selected() == 1 else "9h"))
        view.add(mode)

        src = Adw.ComboRow(title="Fuente por defecto")
        src.set_model(Gtk.StringList.new(["Jira", "Jira / Clockify", "Clockify"]))
        src.set_selected({"jira": 0, "jira-clockify": 1, "clockify": 2}.get(self.cfg.source, 0))
        src.connect("notify::selected", lambda r, _p: self.cfg.settings.set_string("worklog-source", ["jira", "jira-clockify", "clockify"][r.get_selected()]))
        view.add(src)
        view.add(self._spin("Objetivo diario (horas)", "daily-target-hours", 0, 24, 0.5, True))
        view.add(self._switch("Mostrar título del issue en los bloques", "show-issue-summary"))
        page.add(view)

        panel = Adw.PreferencesGroup(title="Panel inferior")
        panel.add(self._switch("Mostrar panel inferior (anillos / tabla / heatmap)", "show-bottom-panel"))
        panel.add(self._switch("Habilitar la tabla de subtareas", "show-subtask-table"))
        panel.add(self._switch("Mostrar columna del issue padre", "subtask-show-parent"))
        panel.add(self._entry("JQL de subtareas", "subtask-jql"))
        page.add(panel)

        picker = Adw.PreferencesGroup(title="Picker de issues (modal de Jira)")
        picker.add(self._entry("JQL del picker", "issue-jql"))
        picker.add(self._spin("Máximo de issues", "issue-max", 10, 200, 5, False))
        page.add(picker)

        win = Adw.PreferencesGroup(title="Ventana y comportamiento")
        win.add(self._switch("Mostrar el reloj en la barra superior", "show-tray-icon"))
        win.add(self._switch("Seguir en segundo plano al cerrar", "run-in-background"))
        win.add(self._spin("Ancho de la ventanita (popup)", "popup-width", 600, 2200, 10, False))
        win.add(self._spin("Alto de la ventanita (popup)", "popup-height", 400, 1500, 10, False))
        win.add(self._switch("Registrar peticiones en stdout (debug)", "debug"))
        page.add(win)
        return page

    def _jira_page(self):
        page = Adw.PreferencesPage(title="Jira", icon_name="network-server-symbolic")
        g = Adw.PreferencesGroup(title="Credenciales de Jira Cloud",
                                 description="Generá un API token en id.atlassian.com → Security → API tokens.")
        g.add(self._entry("Site URL", "jira-site"))
        g.add(self._entry("Email", "jira-email"))
        g.add(self._password("API token", "jira-token"))
        g.add(self._test_row("Probar conexión", self._test_jira))
        page.add(g)
        return page

    def _clockify_page(self):
        page = Adw.PreferencesPage(title="Clockify", icon_name="alarm-symbolic")
        g = Adw.PreferencesGroup(title="Credenciales de Clockify",
                                 description="Generá tu API key en Clockify → Profile → Settings → API.")
        g.add(self._password("API key", "clockify-api-key"))
        g.add(self._entry("Workspace ID (opcional)", "clockify-workspace-id"))
        g.add(self._switch("Facturable por defecto", "clockify-billable-default"))
        g.add(self._test_row("Probar conexión", self._test_clockify))
        page.add(g)
        return page

    def _sprint_page(self):
        page = Adw.PreferencesPage(title="Sprint", icon_name="office-chart-ring-symbolic")
        g = Adw.PreferencesGroup(title="Anillos de Sprint / Horas")
        strat = Adw.ComboRow(title="Estrategia de descubrimiento")
        strat.set_model(Gtk.StringList.new(["subtask-customfield", "agile-board", "assignee-jql"]))
        strat.set_selected({"subtask-customfield": 0, "agile-board": 1, "assignee-jql": 2}.get(self.cfg.sprint_strategy, 0))
        strat.connect("notify::selected", lambda r, _p: self.cfg.settings.set_string("sprint-strategy", ["subtask-customfield", "agile-board", "assignee-jql"][r.get_selected()]))
        g.add(strat)
        g.add(self._entry("Campo del sprint (customfield)", "sprint-field"))
        g.add(self._spin("Board ID (estrategia agile-board)", "sprint-board-id", 0, 9999999, 1, False))
        rem = Adw.ComboRow(title="Cálculo de horas restantes")
        rem.set_model(Gtk.StringList.new(["api (remainingEstimate)", "calculated (original - spent)"]))
        rem.set_selected(1 if self.cfg.remaining_mode == "calculated" else 0)
        rem.connect("notify::selected", lambda r, _p: self.cfg.settings.set_string("remaining-mode", "calculated" if r.get_selected() == 1 else "api"))
        g.add(rem)
        page.add(g)
        return page

    # ---- test rows ----
    def _test_row(self, title, fn):
        row = Adw.ActionRow(title=title)
        btn = Gtk.Button.new_with_label("Probar")
        btn.set_valign(Gtk.Align.CENTER)
        lbl = Gtk.Label(label="")
        btn.connect("clicked", lambda *_: fn(lbl))
        row.add_suffix(lbl)
        row.add_suffix(btn)
        return row

    def _test_jira(self, lbl):
        lbl.set_label("Probando…")

        def done(ok):
            lbl.set_label("✓ OK (%d issues)" % len(self.jira.assignable_issues) if ok else "✗ " + self.jira.last_error)
        self.jira.fetch_assignable_issues(done)

    def _test_clockify(self, lbl):
        lbl.set_label("Probando…")

        def done(ok):
            lbl.set_label("✓ OK (%d proyectos)" % len(self.clockify.projects) if ok else "✗ " + self.clockify.last_error)
        self.clockify.ensure_context(done)

    # ---- row factories ----
    def _switch(self, title, key):
        r = Adw.SwitchRow(title=title)
        self.cfg.settings.bind(key, r, "active", Gio.SettingsBindFlags.DEFAULT)
        return r

    def _entry(self, title, key):
        r = Adw.EntryRow(title=title)
        self.cfg.settings.bind(key, r, "text", Gio.SettingsBindFlags.DEFAULT)
        return r

    def _password(self, title, key):
        r = Adw.PasswordEntryRow(title=title)
        self.cfg.settings.bind(key, r, "text", Gio.SettingsBindFlags.DEFAULT)
        return r

    def _spin(self, title, key, lo, hi, step, is_double):
        adj = Gtk.Adjustment(lower=lo, upper=hi, step_increment=step, page_increment=step)
        r = Adw.SpinRow(adjustment=adj, climb_rate=step, digits=1 if is_double else 0, title=title)
        if is_double:
            self.cfg.settings.bind(key, adj, "value", Gio.SettingsBindFlags.DEFAULT)
        else:
            adj.set_value(self.cfg.settings.get_int(key))
            adj.connect("value-changed", lambda a: self.cfg.settings.set_int(key, int(a.get_value())))
            self.cfg.settings.connect("changed::" + key, lambda s, k: adj.set_value(s.get_int(k)) if int(adj.get_value()) != s.get_int(k) else None)
        return r
