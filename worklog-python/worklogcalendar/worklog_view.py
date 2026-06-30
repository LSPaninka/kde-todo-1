"""worklog_view.py - the whole worklog UI, reused by both windows."""
from __future__ import annotations
from datetime import datetime

from gi.repository import Gtk, GObject, GLib

from . import util, APP_ID
from .calendar_grid import CalendarGrid
from .sprint_gauges import SprintGauges
from .subtask_table import SubtaskTable
from .month_heatmap import MonthHeatmap
from .jira_edit_dialog import JiraEditDialog
from .clockify_edit_dialog import ClockifyEditDialog


class WorklogView(Gtk.Box):
    __gsignals__ = {
        "open-app-requested": (GObject.SignalFlags.RUN_FIRST, None, ()),
        "open-prefs-requested": (GObject.SignalFlags.RUN_FIRST, None, ()),
    }

    def __init__(self, cfg, jira, clockify, is_popup):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.cfg = cfg
        self.jira = jira
        self.clockify = clockify
        self.is_popup = is_popup
        self.week_start = util.sunday_of(util.now_ms())
        self.jira_dialog = None
        self.clockify_dialog = None
        self.status_clear_id = 0
        self.sync_project_ids = []
        for m in (self.set_margin_start, self.set_margin_end, self.set_margin_top, self.set_margin_bottom):
            m(8)

        self._build()

        jira.connect("changed", lambda *_: self._on_store_changed())
        clockify.connect("changed", lambda *_: self._on_store_changed())
        s = cfg.settings
        s.connect("changed::worklog-source", lambda *_: self._on_source_changed())
        s.connect("changed::view-mode", lambda *_: (self._update_mode_toggle(), self.calendar.refresh()))
        s.connect("changed::bottom-view", lambda *_: (self._apply_bottom_view(), self._refresh_bottom()))

        self._apply_bottom_view()
        self.sync_now()

    def _build(self):
        self._build_header()
        self.status_label = Gtk.Label(label=" ")
        self.status_label.set_halign(Gtk.Align.START)
        self.status_label.add_css_class("caption")
        self.append(self.status_label)

        self.calendar = CalendarGrid(self.cfg, self.jira, self.clockify)
        self.calendar.set_week(self.week_start)
        self.calendar.change_source(self.cfg.source)
        self.calendar.set_vexpand(True)
        self.calendar.connect("create-requested", self._on_create)
        self.calendar.connect("edit-requested", self._on_edit)
        self.calendar.connect("move-requested", self._on_move)
        self.calendar.connect("duplicate-requested", self._on_duplicate)
        self.append(self.calendar)

        self._build_bottom_panel()
        self._build_footer()
        self._update_source_ui()
        self._update_mode_toggle()

    def _build_header(self):
        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        header.append(Gtk.Image.new_from_icon_name(APP_ID + "-symbolic"))
        title = Gtk.Label(label="Worklog")
        title.add_css_class("heading")
        header.append(title)

        prev = Gtk.Button.new_from_icon_name("go-previous-symbolic")
        prev.add_css_class("flat")
        prev.connect("clicked", lambda *_: self._shift_week(-7))
        header.append(prev)
        today = Gtk.Button.new_with_label("Hoy")
        today.connect("clicked", lambda *_: self._go_today())
        header.append(today)
        nxt = Gtk.Button.new_from_icon_name("go-next-symbolic")
        nxt.add_css_class("flat")
        nxt.connect("clicked", lambda *_: self._shift_week(7))
        header.append(nxt)

        self.week_label = Gtk.Label(label="")
        self.week_label.add_css_class("heading")
        self.week_label.set_hexpand(True)
        self.week_label.set_halign(Gtk.Align.CENTER)
        header.append(self.week_label)

        self.mode_toggle = Gtk.Button.new_with_label("Modo 9h")
        self.mode_toggle.set_tooltip_text("Cambiar entre vista 09:00–18:00 y 00:00–24:00")
        self.mode_toggle.connect("clicked", lambda *_: self._toggle_mode())
        header.append(self.mode_toggle)

        sync = Gtk.Button.new_from_icon_name("view-refresh-symbolic")
        sync.add_css_class("flat")
        sync.set_tooltip_text("Sincronizar")
        sync.connect("clicked", lambda *_: self.sync_now())
        header.append(sync)

        menu_btn = Gtk.MenuButton()
        menu_btn.set_icon_name("open-menu-symbolic")
        menu_btn.set_tooltip_text("Fuente de worklog")
        menu_btn.set_popover(self._build_source_popover())
        header.append(menu_btn)

        if self.is_popup:
            open_app = Gtk.Button.new_from_icon_name("view-fullscreen-symbolic")
            open_app.set_tooltip_text("Abrir la aplicación completa")
            open_app.add_css_class("flat")
            open_app.connect("clicked", lambda *_: self.emit("open-app-requested"))
            header.append(open_app)

        self.append(header)
        self._update_week_label()

    def _build_source_popover(self):
        pop = Gtk.Popover()
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        for m in (box.set_margin_start, box.set_margin_end, box.set_margin_top, box.set_margin_bottom):
            m(10)
        group = None
        for val, label in (("jira", "Jira"), ("jira-clockify", "Jira / Clockify"), ("clockify", "Clockify")):
            rb = Gtk.CheckButton.new_with_label(label)
            if group is None:
                group = rb
            else:
                rb.set_group(group)
            rb.set_active(self.cfg.source == val)
            rb.connect("toggled", self._on_source_radio, val, pop)
            box.append(rb)
        pop.set_child(box)
        return pop

    def _on_source_radio(self, rb, val, pop):
        if rb.get_active() and self.cfg.source != val:
            self.cfg.source = val
            pop.popdown()

    def _build_bottom_panel(self):
        self.bottom_panel = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.bottom_panel.set_size_request(-1, 210)

        self.bottom_stack = Gtk.Stack()
        self.bottom_stack.set_transition_type(Gtk.StackTransitionType.SLIDE_UP_DOWN)
        self.bottom_stack.set_hexpand(True)
        self.gauges = SprintGauges(self.jira)
        self.gauges.set_valign(Gtk.Align.CENTER)
        self.bottom_stack.add_named(self.gauges, "rings")
        self.subtask_table = SubtaskTable(self.jira, self.cfg)
        self.subtask_table.connect("status-message", lambda _w, msg, err: self._set_status(msg, err))
        self.bottom_stack.add_named(self.subtask_table, "subtasks")
        self.heatmap = MonthHeatmap(self.clockify, self.jira)
        self.heatmap.set_valign(Gtk.Align.CENTER)
        self.heatmap.connect("day-selected", lambda _w, ms: self._jump_to(ms))
        self.bottom_stack.add_named(self.heatmap, "heatmap")
        self.bottom_panel.append(self.bottom_stack)

        strip = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        strip.set_valign(Gtk.Align.CENTER)
        self._switch_button(strip, "office-chart-ring-symbolic", "Anillos (Sprint / Horas)", "rings")
        if self.cfg.show_subtask_table:
            self._switch_button(strip, "view-list-symbolic", "Tabla de subtareas", "subtasks")
        self._switch_button(strip, "x-office-calendar-symbolic", "Heatmap mensual", "heatmap")
        self.bottom_panel.append(strip)

        self.append(self.bottom_panel)
        self.bottom_panel.set_visible(self.cfg.show_bottom_panel)

    def _switch_button(self, strip, icon, tip, view):
        btn = Gtk.Button.new_from_icon_name(icon)
        btn.add_css_class("flat")
        btn.set_tooltip_text(tip)
        btn.connect("clicked", lambda *_: setattr(self.cfg, "bottom_view", view))
        strip.append(btn)

    def _build_footer(self):
        footer = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.footer_totals = Gtk.Label(label="")
        self.footer_totals.add_css_class("caption")
        self.footer_totals.set_halign(Gtk.Align.START)
        self.footer_totals.set_hexpand(True)
        footer.append(self.footer_totals)

        self.sync_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.sync_project = Gtk.DropDown.new(None, None)
        self.sync_project.set_tooltip_text("Proyecto destino del sync Jira → Clockify")
        self.sync_project.connect("notify::selected", self._on_sync_project_changed)
        self.sync_box.append(self.sync_project)
        sync_btn = Gtk.Button.new_with_label("Jira → Clockify")
        sync_btn.set_tooltip_text("Crea una entrada Clockify por cada worklog de Jira que aún no tenga su réplica.")
        sync_btn.connect("clicked", lambda *_: self._sync_jira_into_clockify())
        self.sync_box.append(sync_btn)
        footer.append(self.sync_box)

        prefs = Gtk.Button.new_from_icon_name("emblem-system-symbolic")
        prefs.set_tooltip_text("Configurar…")
        prefs.add_css_class("flat")
        prefs.connect("clicked", lambda *_: self.emit("open-prefs-requested"))
        footer.append(prefs)
        self.append(footer)

    # ------------------------------------------------------------------
    def _shift_week(self, days):
        self.week_start = util.add_days_ms(self.week_start, days)
        self.calendar.set_week(self.week_start)
        self._update_week_label()
        self.sync_now()

    def _go_today(self):
        self.week_start = util.sunday_of(util.now_ms())
        self.calendar.set_week(self.week_start)
        self._update_week_label()
        self.sync_now()

    def _jump_to(self, ms):
        self.week_start = util.sunday_of(ms)
        self.calendar.set_week(self.week_start)
        self._update_week_label()
        self.sync_now()

    def _toggle_mode(self):
        self.cfg.view_mode = "24h" if self.cfg.view_mode == "9h" else "9h"

    def _update_week_label(self):
        s = datetime.fromtimestamp(self.week_start / 1000)
        e = datetime.fromtimestamp(util.add_days_ms(self.week_start, 6) / 1000)
        self.week_label.set_label("%d %s — %d %s %d" % (
            s.day, util.short_month(s.month - 1), e.day, util.short_month(e.month - 1), e.year))

    def _update_mode_toggle(self):
        self.mode_toggle.set_label("Modo 9h" if self.cfg.view_mode == "9h" else "Modo 24h")

    def _show_jira(self):
        return self.cfg.source in ("jira", "jira-clockify")

    def _show_clockify(self):
        return self.cfg.source in ("clockify", "jira-clockify")

    def _on_source_changed(self):
        self.calendar.change_source(self.cfg.source)
        self._update_source_ui()
        self.sync_now()

    def _update_source_ui(self):
        combined = self.cfg.source == "jira-clockify"
        self.sync_box.set_visible(combined)
        if combined:
            self._populate_sync_projects()

    def sync_now(self):
        if self._show_jira():
            self.jira.fetch_week(self.week_start)
        if self._show_clockify():
            self.clockify.fetch_week(self.week_start)
        self._refresh_bottom()

    def _refresh_bottom(self):
        if not self.cfg.show_bottom_panel:
            return
        v = self.cfg.bottom_view
        if v == "rings":
            self.jira.fetch_sprint_info(lambda ok: self.gauges.start_fill_animation())
        elif v == "subtasks":
            self.subtask_table.refresh()
        elif v == "heatmap":
            self.heatmap.refresh()

    def _apply_bottom_view(self):
        self.bottom_panel.set_visible(self.cfg.show_bottom_panel)
        v = self.cfg.bottom_view
        if v == "subtasks" and not self.cfg.show_subtask_table:
            v = "rings"
        self.bottom_stack.set_visible_child_name(v)

    def _on_store_changed(self):
        self._update_footer_totals()
        if self.jira.last_error and self._show_jira():
            self._set_status("Jira: " + self.jira.last_error, True)
        elif self.clockify.last_error and self._show_clockify():
            self._set_status("Clockify: " + self.clockify.last_error, True)

    def _update_footer_totals(self):
        parts = []
        if self._show_jira():
            parts.append("Jira: %s" % util.fmt_hm(sum(w.duration_sec for w in self.jira.worklogs)))
        if self._show_clockify():
            parts.append("Clockify: %s" % util.fmt_hm(sum(e.duration_sec for e in self.clockify.entries)))
        self.footer_totals.set_label("   ·   ".join(parts))

    def _populate_sync_projects(self):
        model = Gtk.StringList()
        ids = []
        model.append("(sin proyecto)")
        ids.append("")
        sel = 0
        for i, p in enumerate(self.clockify.projects, start=1):
            model.append(p.name)
            ids.append(p.id)
            if p.id == self.cfg.clockify_default_project_id:
                sel = i
        self.sync_project_ids = ids
        self.sync_project.set_model(model)
        self.sync_project.set_selected(sel)

    def _on_sync_project_changed(self, *_):
        sel = self.sync_project.get_selected()
        if 0 <= sel < len(self.sync_project_ids):
            self.cfg.clockify_default_project_id = self.sync_project_ids[sel]

    # ---- dialogs ----
    def _root_window(self):
        return self.get_root()

    def _ensure_jira_dialog(self):
        if self.jira_dialog is None:
            self.jira_dialog = JiraEditDialog(self._root_window(), self.jira)
            self.jira_dialog.connect("saved", lambda *_: self.sync_now())
        return self.jira_dialog

    def _ensure_clockify_dialog(self):
        if self.clockify_dialog is None:
            self.clockify_dialog = ClockifyEditDialog(self._root_window(), self.clockify, self.cfg)
            self.clockify_dialog.connect("saved", lambda *_: self.sync_now())
        return self.clockify_dialog

    def _on_create(self, _w, is_jira, day_ms, start_ms, end_ms):
        if is_jira:
            self._ensure_jira_dialog().open_create(day_ms, start_ms, end_ms)
        else:
            self._ensure_clockify_dialog().open_create(start_ms, end_ms)

    def _on_edit(self, _w, is_jira, entry):
        if is_jira:
            self._ensure_jira_dialog().open_edit(entry)
        else:
            self._ensure_clockify_dialog().open_edit(entry)

    def _on_move(self, _w, is_jira, entry, new_start_ms, new_dur_sec):
        if is_jira:
            self._set_status("Actualizando worklog Jira…", False)

            def done(res):
                if res.ok:
                    self.sync_now()
                else:
                    self._set_status("Jira: " + res.err, True)
            self.jira.update_worklog(entry.issue_key, entry.id, new_start_ms, new_dur_sec, None, done)
        else:
            self._set_status("Actualizando entrada Clockify…", False)
            ne = new_start_ms + new_dur_sec * 1000

            def done(res):
                if res.ok:
                    self.sync_now()
                else:
                    self._set_status("Clockify: " + res.err, True)
            self.clockify.update_entry(entry.id, new_start_ms, ne, entry.description,
                                       entry.project_id, entry.tag_ids, entry.billable, done)

    def _on_duplicate(self, _w, is_jira, entry):
        if is_jira:
            self._set_status("Duplicando worklog Jira…", False)

            def done(res):
                if res.ok:
                    self.sync_now()
                else:
                    self._set_status("Jira: " + res.err, True)
            self.jira.create_worklog(entry.issue_key, entry.started, entry.duration_sec, entry.comment, done)
        else:
            self._set_status("Duplicando entrada Clockify…", False)
            ne = entry.started + entry.duration_sec * 1000

            def done(res):
                if res.ok:
                    self.sync_now()
                else:
                    self._set_status("Clockify: " + res.err, True)
            self.clockify.create_entry(entry.started, ne, entry.description, entry.project_id,
                                       entry.tag_ids, entry.billable, done)

    def _sync_jira_into_clockify(self):
        self._set_status("Copiando Jira → Clockify…", False)
        pid = self.cfg.clockify_default_project_id
        bill = self.cfg.clockify_billable_default

        def done(counts):
            created, skipped, failed = counts
            self._set_status("Sync terminado: %d creadas, %d ya existían, %d fallaron." % (created, skipped, failed), failed > 0)
            self.clockify.fetch_week(self.week_start)
        self.clockify.sync_from_jira(self.jira.worklogs, pid, bill, done)

    def _set_status(self, msg, error):
        self.status_label.set_label(msg)
        if error:
            self.status_label.add_css_class("error")
        else:
            self.status_label.remove_css_class("error")
        if self.status_clear_id:
            GLib.source_remove(self.status_clear_id)

        def clear():
            self.status_label.set_label(" ")
            self.status_label.remove_css_class("error")
            self.status_clear_id = 0
            return GLib.SOURCE_REMOVE
        self.status_clear_id = GLib.timeout_add_seconds(6, clear)
