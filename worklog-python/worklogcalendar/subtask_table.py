"""subtask_table.py - bottom-panel subtask list with search + transitions."""
from __future__ import annotations

from gi.repository import Gtk, Gio, GObject, Pango

from . import util


_STATUS_CLASS = {
    "green": "wb-green", "yellow": "wb-yellow", "blue-gray": "wb-bluegray",
    "brown": "wb-brown", "warm-red": "wb-warmred", "medium-gray": "wb-mediumgray",
}


class SubtaskTable(Gtk.Box):
    __gsignals__ = {"status-message": (GObject.SignalFlags.RUN_FIRST, None, (str, bool))}

    def __init__(self, jira, cfg):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.jira = jira
        self.cfg = cfg
        self.filter = ""
        self._build()
        jira.connect("changed", lambda *_: self._rebuild())

    def _build(self):
        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        title = Gtk.Label(label="Subtareas")
        title.add_css_class("heading")
        title.set_halign(Gtk.Align.START)
        header.append(title)
        sp = Gtk.Box()
        sp.set_hexpand(True)
        header.append(sp)
        self.search = Gtk.SearchEntry()
        self.search.set_placeholder_text("Buscar…")
        self.search.set_width_chars(18)
        self.search.connect("search-changed", self._on_search)
        header.append(self.search)
        refresh_btn = Gtk.Button.new_from_icon_name("view-refresh-symbolic")
        refresh_btn.add_css_class("flat")
        refresh_btn.set_tooltip_text("Actualizar subtareas")
        refresh_btn.connect("clicked", lambda *_: self.refresh())
        header.append(refresh_btn)
        self.append(header)

        scroller = Gtk.ScrolledWindow()
        scroller.set_vexpand(True)
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.list = Gtk.ListBox()
        self.list.add_css_class("boxed-list")
        self.list.set_selection_mode(Gtk.SelectionMode.NONE)
        scroller.set_child(self.list)
        self.append(scroller)
        self._rebuild()

    def _on_search(self, entry):
        self.filter = entry.get_text().lower()
        self._rebuild()

    def refresh(self):
        self.jira.fetch_subtasks()

    def _rebuild(self):
        child = self.list.get_first_child()
        while child is not None:
            nxt = child.get_next_sibling()
            self.list.remove(child)
            child = nxt
        show_parent = self.cfg.subtask_show_parent
        for s in self.jira.subtasks:
            if self.filter:
                hay = (s.key + " " + s.summary + " " + s.status + " " + s.parent_key + " " + s.parent_summary).lower()
                if self.filter not in hay:
                    continue
            self.list.append(self._make_row(s, show_parent))

    def _make_row(self, s, show_parent):
        row = Gtk.ListBoxRow()
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        box.set_margin_start(8)
        box.set_margin_end(8)
        box.set_margin_top(4)
        box.set_margin_bottom(4)

        key = Gtk.Label(label=s.key)
        key.add_css_class("monospace")
        key.set_width_chars(9)
        key.set_xalign(0)
        box.append(key)

        summ = Gtk.Label(label=s.summary)
        summ.set_xalign(0)
        summ.set_ellipsize(Pango.EllipsizeMode.END)
        summ.set_hexpand(True)
        box.append(summ)

        if show_parent and s.parent_key:
            par = Gtk.Label(label=s.parent_key)
            par.add_css_class("dim-label")
            par.set_tooltip_text(s.parent_summary)
            box.append(par)

        badge = Gtk.Label(label=s.status)
        badge.add_css_class("worklog-badge")
        badge.add_css_class(_STATUS_CLASS.get(s.status_color, "wb-bluegray"))
        box.append(badge)

        rem = Gtk.Label(label=util.fmt_hm(s.remaining_sec) if s.remaining_sec > 0 else "—")
        rem.set_width_chars(7)
        rem.set_xalign(1)
        box.append(rem)

        menu_btn = Gtk.MenuButton()
        menu_btn.set_icon_name("view-more-symbolic")
        menu_btn.add_css_class("flat")
        menu_btn.set_popover(self._make_menu(s))
        box.append(menu_btn)

        row.set_child(box)
        return row

    def _make_menu(self, s):
        pop = Gtk.Popover()
        vb = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        for m in (vb.set_margin_start, vb.set_margin_end, vb.set_margin_top, vb.set_margin_bottom):
            m(6)

        open_btn = Gtk.Button.new_with_label("Abrir en Jira")
        open_btn.add_css_class("flat")
        open_btn.connect("clicked", lambda *_: self._open_in_jira(s, pop))
        vb.append(open_btn)

        lbl = Gtk.Label(label="Cambiar estado:")
        lbl.add_css_class("caption")
        lbl.set_halign(Gtk.Align.START)
        lbl.set_margin_top(4)
        vb.append(lbl)

        trans_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        loading = Gtk.Label(label="…")
        loading.add_css_class("dim-label")
        trans_box.append(loading)
        vb.append(trans_box)

        def on_show(_p):
            def got(trs):
                c = trans_box.get_first_child()
                while c is not None:
                    n = c.get_next_sibling()
                    trans_box.remove(c)
                    c = n
                if not trs:
                    none = Gtk.Label(label="(sin transiciones)")
                    none.add_css_class("dim-label")
                    trans_box.append(none)
                    return
                for t in trs:
                    btn = Gtk.Button.new_with_label(t.to_status or t.name)
                    btn.add_css_class("flat")
                    btn.connect("clicked", lambda _b, tid=t.id, key=s.key: self._do_transition(key, tid, pop))
                    trans_box.append(btn)
            self.jira.fetch_transitions(s.key, got)
        pop.connect("show", on_show)
        pop.set_child(vb)
        return pop

    def _open_in_jira(self, s, pop):
        url = self.jira.issue_web_url(s.key)
        if url:
            Gio.AppInfo.launch_default_for_uri(url, None)
        pop.popdown()

    def _do_transition(self, key, tid, pop):
        pop.popdown()
        self.emit("status-message", "Cambiando estado de %s…" % key, False)

        def done(res):
            if res.ok:
                self.emit("status-message", "Estado de %s actualizado." % key, False)
                self.refresh()
            else:
                self.emit("status-message", "No se pudo cambiar el estado: %s" % res.err, True)
        self.jira.transition_issue(key, tid, done)
