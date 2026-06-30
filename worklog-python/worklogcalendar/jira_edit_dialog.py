"""jira_edit_dialog.py - create / edit / delete a Jira worklog."""
from __future__ import annotations
from datetime import datetime

from gi.repository import Gtk, Adw, GObject, Pango

from . import util


class JiraEditDialog(Adw.Window):
    __gsignals__ = {"saved": (GObject.SignalFlags.RUN_FIRST, None, ())}

    def __init__(self, parent, store):
        super().__init__(transient_for=parent, modal=True, title="Worklog de Jira")
        self.store = store
        self.is_edit = False
        self.editing = None
        self.start_ms = 0
        self.end_ms = 0
        self.selected_key = ""
        self.set_default_size(640, 540)
        self._build()

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
        self.start_entry.set_max_width_chars(6)
        self.start_entry.set_width_chars(6)
        timerow.append(self.start_entry)
        timerow.append(Gtk.Label(label="Fin"))
        self.end_entry = Gtk.Entry()
        self.end_entry.set_max_width_chars(6)
        self.end_entry.set_width_chars(6)
        timerow.append(self.end_entry)
        self.dur_label = Gtk.Label(label="")
        self.dur_label.add_css_class("dim-label")
        timerow.append(self.dur_label)
        content.append(timerow)
        self.start_entry.connect("changed", lambda *_: self._update_duration())
        self.end_entry.connect("changed", lambda *_: self._update_duration())

        self.picker_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.picker_box.set_vexpand(True)
        lbl = Gtk.Label(label="Issue")
        lbl.set_halign(Gtk.Align.START)
        self.picker_box.append(lbl)
        self.picker_selected = Gtk.Label(label="(ninguno)")
        self.picker_selected.add_css_class("dim-label")
        self.picker_selected.set_halign(Gtk.Align.START)
        self.picker_box.append(self.picker_selected)
        self.picker_search = Gtk.SearchEntry()
        self.picker_search.set_placeholder_text("Filtrar issues…")
        self.picker_search.connect("search-changed", lambda *_: self._filter_picker())
        self.picker_box.append(self.picker_search)
        sw = Gtk.ScrolledWindow()
        sw.set_vexpand(True)
        sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.picker_list = Gtk.ListBox()
        self.picker_list.add_css_class("boxed-list")
        self.picker_list.connect("row-activated", self._on_pick)
        sw.set_child(self.picker_list)
        self.picker_box.append(sw)
        content.append(self.picker_box)

        clbl = Gtk.Label(label="Comentario")
        clbl.set_halign(Gtk.Align.START)
        content.append(clbl)
        csw = Gtk.ScrolledWindow()
        csw.set_min_content_height(70)
        self.comment_view = Gtk.TextView()
        self.comment_view.set_wrap_mode(Gtk.WrapMode.WORD)
        self.comment_view.add_css_class("card")
        csw.set_child(self.comment_view)
        content.append(csw)

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

    def open_create(self, day_ms, s, e):
        self.is_edit = False
        self.editing = None
        self.start_ms, self.end_ms = s, e
        self.selected_key = ""
        self.picker_selected.set_label("(ninguno)")
        self.start_entry.set_text(util.fmt_clock(s))
        self.end_entry.set_text(util.fmt_clock(e))
        self.comment_view.get_buffer().set_text("")
        self.status.set_label("")
        self.picker_box.set_visible(True)
        self.delete_btn.set_visible(False)
        self._refresh_picker()
        self.present()

    def open_edit(self, w):
        self.is_edit = True
        self.editing = w
        self.start_ms = w.started
        self.end_ms = w.started + w.duration_sec * 1000
        self.selected_key = w.issue_key
        self.picker_selected.set_label(w.issue_key + ((": " + w.issue_summary) if w.issue_summary else ""))
        self.start_entry.set_text(util.fmt_clock(self.start_ms))
        self.end_entry.set_text(util.fmt_clock(self.end_ms))
        self.comment_view.get_buffer().set_text(w.comment)
        self.status.set_label("")
        self.picker_box.set_visible(False)
        self.delete_btn.set_visible(True)
        self.present()

    def _refresh_picker(self):
        self.status.set_label("Cargando issues…")

        def done(ok):
            self.status.set_label("")
            self._filter_picker()
        self.store.fetch_assignable_issues(done)

    def _filter_picker(self):
        c = self.picker_list.get_first_child()
        while c is not None:
            n = c.get_next_sibling()
            self.picker_list.remove(c)
            c = n
        q = self.picker_search.get_text().lower()
        for iss in self.store.assignable_issues:
            if q and q not in (iss.key + " " + iss.summary + " " + iss.status).lower():
                continue
            row = Gtk.ListBoxRow()
            box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            for m in (box.set_margin_start, box.set_margin_end):
                m(8)
            box.set_margin_top(3)
            box.set_margin_bottom(3)
            k = Gtk.Label(label=iss.key)
            k.add_css_class("monospace")
            k.set_width_chars(9)
            k.set_xalign(0)
            box.append(k)
            s = Gtk.Label(label=iss.summary)
            s.set_xalign(0)
            s.set_ellipsize(Pango.EllipsizeMode.END)
            s.set_hexpand(True)
            box.append(s)
            if iss.remaining_sec > 0:
                rem = Gtk.Label(label=util.fmt_hm(iss.remaining_sec))
                rem.add_css_class("dim-label")
                box.append(rem)
            row.set_child(box)
            row._key = iss.key
            row._summary = iss.summary
            self.picker_list.append(row)

    def _on_pick(self, listbox, row):
        self.selected_key = row._key
        self.picker_selected.set_label(self.selected_key + ((": " + row._summary) if row._summary else ""))

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

    def _update_duration(self):
        a = self._parse_hhmm(self.start_entry.get_text())
        b = self._parse_hhmm(self.end_entry.get_text())
        if a and b:
            s = (b[0] * 60 + b[1]) - (a[0] * 60 + a[1])
            self.dur_label.set_label("(%s)" % util.fmt_hm(s * 60) if s > 0 else "")

    def _on_save(self):
        if not self._apply_time(self.start_entry.get_text(), True) or not self._apply_time(self.end_entry.get_text(), False):
            self._set_status("Hora inválida (usá HH:MM).", True)
            return
        if self.end_ms <= self.start_ms:
            self._set_status("El fin debe ser posterior al inicio.", True)
            return
        if not self.selected_key:
            self._set_status("Elegí un issue.", True)
            return
        dur = int((self.end_ms - self.start_ms) / 1000)
        buf = self.comment_view.get_buffer()
        comment = buf.get_text(buf.get_start_iter(), buf.get_end_iter(), True)
        self.save_btn.set_sensitive(False)
        self._set_status("Guardando…", False)
        if self.is_edit:
            self.store.update_worklog(self.editing.issue_key, self.editing.id, self.start_ms, dur, comment, self._finish)
        else:
            self.store.create_worklog(self.selected_key, self.start_ms, dur, comment, self._finish)

    def _on_delete(self):
        if self.editing is None:
            return
        self.delete_btn.set_sensitive(False)
        self._set_status("Borrando…", False)
        self.store.delete_worklog(self.editing.issue_key, self.editing.id, self._finish)

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
