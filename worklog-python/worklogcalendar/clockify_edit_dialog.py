"""clockify_edit_dialog.py - create / edit / delete a Clockify time entry."""
from __future__ import annotations
from datetime import datetime

from gi.repository import Gtk, Adw, GObject

from . import util


class ClockifyEditDialog(Adw.Window):
    __gsignals__ = {"saved": (GObject.SignalFlags.RUN_FIRST, None, ())}

    def __init__(self, parent, store, cfg):
        super().__init__(transient_for=parent, modal=True, title="Entrada de Clockify")
        self.store = store
        self.cfg = cfg
        self.is_edit = False
        self.editing = None
        self.start_ms = 0
        self.end_ms = 0
        self.project_ids = []
        self.tag_toggles = []
        self.set_default_size(560, 480)
        self._build()

    def _label(self, t):
        l = Gtk.Label(label=t)
        l.set_halign(Gtk.Align.START)
        l.add_css_class("dim-label")
        return l

    def _build(self):
        toolbar = Adw.ToolbarView()
        toolbar.add_top_bar(Adw.HeaderBar())
        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        for m in (content.set_margin_start, content.set_margin_end):
            m(16)
        content.set_margin_top(12)
        content.set_margin_bottom(12)

        timerow = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        timerow.append(Gtk.Label(label="Inicio"))
        self.start_entry = Gtk.Entry()
        self.start_entry.set_width_chars(6)
        self.start_entry.set_max_width_chars(6)
        timerow.append(self.start_entry)
        timerow.append(Gtk.Label(label="Fin"))
        self.end_entry = Gtk.Entry()
        self.end_entry.set_width_chars(6)
        self.end_entry.set_max_width_chars(6)
        timerow.append(self.end_entry)
        content.append(timerow)

        content.append(self._label("Descripción"))
        self.desc_entry = Gtk.Entry()
        self.desc_entry.set_placeholder_text("Qué hiciste…")
        content.append(self.desc_entry)

        content.append(self._label("Proyecto"))
        self.project_drop = Gtk.DropDown.new(None, None)
        content.append(self.project_drop)

        content.append(self._label("Tags"))
        tags_scroll = Gtk.ScrolledWindow()
        tags_scroll.set_min_content_height(60)
        tags_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.tags_box = Gtk.FlowBox()
        self.tags_box.set_selection_mode(Gtk.SelectionMode.NONE)
        self.tags_box.set_max_children_per_line(6)
        tags_scroll.set_child(self.tags_box)
        content.append(tags_scroll)

        self.billable_check = Gtk.CheckButton.new_with_label("Facturable")
        content.append(self.billable_check)

        self.status = Gtk.Label(label="")
        self.status.set_halign(Gtk.Align.START)
        content.append(self.status)

        btnrow = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.delete_btn = Gtk.Button.new_with_label("Borrar")
        self.delete_btn.add_css_class("destructive-action")
        self.delete_btn.connect("clicked", lambda *_: self._on_delete())
        btnrow.append(self.delete_btn)
        spacer = Gtk.Box()
        spacer.set_hexpand(True)
        btnrow.append(spacer)
        cancel = Gtk.Button.new_with_label("Cancelar")
        cancel.connect("clicked", lambda *_: self.close())
        btnrow.append(cancel)
        self.save_btn = Gtk.Button.new_with_label("Guardar")
        self.save_btn.add_css_class("suggested-action")
        self.save_btn.connect("clicked", lambda *_: self._on_save())
        btnrow.append(self.save_btn)
        content.append(btnrow)

        toolbar.set_content(content)
        self.set_content(toolbar)

    def _populate_projects(self, selected_id):
        model = Gtk.StringList()
        ids = []
        model.append("(sin proyecto)")
        ids.append("")
        sel = 0
        for i, p in enumerate(self.store.projects, start=1):
            model.append(p.name)
            ids.append(p.id)
            if p.id == selected_id:
                sel = i
        self.project_ids = ids
        self.project_drop.set_model(model)
        self.project_drop.set_selected(sel)

    def _populate_tags(self, selected):
        self.tag_toggles = []
        c = self.tags_box.get_first_child()
        while c is not None:
            n = c.get_next_sibling()
            self.tags_box.remove(c)
            c = n
        for t in self.store.tags:
            tb = Gtk.ToggleButton.new_with_label(t.name)
            tb._tid = t.id
            if t.id in selected:
                tb.set_active(True)
            self.tag_toggles.append(tb)
            self.tags_box.append(tb)

    def open_create(self, s, e):
        self.is_edit = False
        self.editing = None
        self.start_ms, self.end_ms = s, e
        self.start_entry.set_text(util.fmt_clock(s))
        self.end_entry.set_text(util.fmt_clock(e))
        self.desc_entry.set_text("")
        self.status.set_label("")
        self.billable_check.set_active(self.cfg.clockify_billable_default)
        self.delete_btn.set_visible(False)
        self._ensure_then(lambda: (self._populate_projects(self.cfg.clockify_default_project_id), self._populate_tags([])))
        self.present()

    def open_edit(self, entry):
        self.is_edit = True
        self.editing = entry
        self.start_ms = entry.started
        self.end_ms = entry.started + entry.duration_sec * 1000
        self.start_entry.set_text(util.fmt_clock(self.start_ms))
        self.end_entry.set_text(util.fmt_clock(self.end_ms))
        self.desc_entry.set_text(entry.description)
        self.status.set_label("")
        self.billable_check.set_active(entry.billable)
        self.delete_btn.set_visible(True)
        self._ensure_then(lambda: (self._populate_projects(entry.project_id), self._populate_tags(entry.tag_ids)))
        self.present()

    def _ensure_then(self, cb):
        if self.store.projects:
            cb()
            return
        self.status.set_label("Cargando proyectos…")

        def done(ok):
            self.status.set_label("")
            cb()
        self.store.ensure_context(done)

    @staticmethod
    def _parse_hhmm(t):
        parts = t.strip().split(":")
        if len(parts) != 2:
            return None
        try:
            hh, mm = int(parts[0]), int(parts[1])
        except ValueError:
            return None
        if 0 <= hh <= 23 and 0 <= mm <= 59:
            return hh, mm
        return None

    def _apply_time(self, text, is_start):
        p = self._parse_hhmm(text)
        if p is None:
            return False
        hh, mm = p
        base = self.start_ms if is_start else self.end_ms
        d = datetime.fromtimestamp(base / 1000).replace(hour=hh, minute=mm, second=0, microsecond=0)
        ms = int(d.timestamp() * 1000)
        if is_start:
            self.start_ms = ms
        else:
            self.end_ms = ms
        return True

    def _selected_tag_ids(self):
        return [tb._tid for tb in self.tag_toggles if tb.get_active()]

    def _selected_project_id(self):
        sel = self.project_drop.get_selected()
        return self.project_ids[sel] if 0 <= sel < len(self.project_ids) else ""

    def _on_save(self):
        if not self._apply_time(self.start_entry.get_text(), True) or not self._apply_time(self.end_entry.get_text(), False):
            self._set_status("Hora inválida (HH:MM).", True)
            return
        if self.end_ms <= self.start_ms:
            self._set_status("El fin debe ser posterior al inicio.", True)
            return
        self.save_btn.set_sensitive(False)
        self._set_status("Guardando…", False)
        desc = self.desc_entry.get_text()
        pid = self._selected_project_id()
        tids = self._selected_tag_ids()
        bill = self.billable_check.get_active()
        if self.is_edit:
            self.store.update_entry(self.editing.id, self.start_ms, self.end_ms, desc, pid, tids, bill, self._finish)
        else:
            self.store.create_entry(self.start_ms, self.end_ms, desc, pid, tids, bill, self._finish)

    def _on_delete(self):
        if self.editing is None:
            return
        self.delete_btn.set_sensitive(False)
        self._set_status("Borrando…", False)
        self.store.delete_entry(self.editing.id, self._finish)

    def _finish(self, res):
        self.save_btn.set_sensitive(True)
        self.delete_btn.set_sensitive(True)
        if res.ok:
            self.emit("saved")
            self.close()
        else:
            self._set_status(res.err, True)

    def _set_status(self, msg, error):
        self.status.set_label(msg)
        if error:
            self.status.add_css_class("error")
        else:
            self.status.remove_css_class("error")
