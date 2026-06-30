"""sprint_gauges.py - twin RingGauge (Sprint % elapsed + Horas % logged)."""
from __future__ import annotations
from datetime import datetime

from gi.repository import Gtk

from . import util
from .ring_gauge import RingGauge


class SprintGauges(Gtk.Box):
    def __init__(self, jira):
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        self.jira = jira
        self._build()
        jira.connect("changed", lambda *_: self.refresh())
        self.refresh()

    def _hline(self):
        sep = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
        sep.set_valign(Gtk.Align.CENTER)
        sep.set_hexpand(True)
        sep.add_css_class("dim-line")
        return sep

    def _build(self):
        self.append(self._hline())

        col1 = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        col1.set_valign(Gtk.Align.CENTER)
        t1 = Gtk.Label(label="Sprint")
        t1.add_css_class("heading")
        col1.append(t1)
        self.sprint_ring = RingGauge(110)
        self.sprint_ring.set_halign(Gtk.Align.CENTER)
        col1.append(self.sprint_ring)
        self.sprint_dates = Gtk.Label(label="Sin sprint activo")
        self.sprint_dates.add_css_class("caption")
        self.sprint_dates.set_justify(Gtk.Justification.CENTER)
        col1.append(self.sprint_dates)
        self.append(col1)

        self.append(self._hline())

        col2 = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        col2.set_valign(Gtk.Align.CENTER)
        t2 = Gtk.Label(label="Horas")
        t2.add_css_class("heading")
        col2.append(t2)
        self.hours_ring = RingGauge(110)
        self.hours_ring.set_halign(Gtk.Align.CENTER)
        self.hours_ring.pale_color = util.hex_rgba("#C8E6C9")
        self.hours_ring.use_fade_loop = True
        col2.append(self.hours_ring)
        self.avail_label = Gtk.Label(label="")
        self.avail_label.add_css_class("caption")
        col2.append(self.avail_label)
        self.burned_label = Gtk.Label(label="")
        self.burned_label.add_css_class("caption")
        col2.append(self.burned_label)
        self.append(col2)

        self.append(self._hline())

    def start_fill_animation(self):
        self.sprint_ring.start_fill()
        self.hours_ring.start_fill()

    def _has_sprint(self):
        return self.jira.current_sprint is not None and self.jira.current_sprint.start_ms > 0

    def _sprint_pct(self):
        if not self._has_sprint():
            return 0.0
        s = self.jira.current_sprint.start_ms
        e = self.jira.current_sprint.end_ms
        now = util.now_ms()
        if e <= s or now <= s:
            return 0.0
        if now >= e:
            return 100.0
        return (now - s) / (e - s) * 100.0

    def _hours_pct(self):
        avail = self.jira.sprint_available_sec
        consumed = self.jira.sprint_consumed_sec
        total = avail + consumed
        if total <= 0:
            return 0.0
        return max(0.0, min(100.0, consumed / total * 100.0))

    @staticmethod
    def _sprint_color(pct):
        if pct >= 100:
            return "#B71C1C"
        if pct >= 90:
            return "#E53935"
        if pct >= 85:
            return "#FB8C00"
        if pct >= 75:
            return "#FBC02D"
        return "#29B6F6"

    @staticmethod
    def _fmt_date(ms):
        if ms == 0:
            return "—"
        d = datetime.fromtimestamp(ms / 1000)
        return "%d/%d" % (d.day, d.month)

    def refresh(self):
        sp = self._sprint_pct()
        hp = self._hours_pct()
        self.sprint_ring.set_value(sp)
        self.sprint_ring.base_color = util.hex_rgba(self._sprint_color(sp))
        self.hours_ring.set_value(hp)
        self.hours_ring.base_color = util.hex_rgba("#4CAF50" if hp >= 100 else "#81C784")
        self.hours_ring.intermittent = sp >= 85 and hp < 99

        if self._has_sprint():
            self.sprint_dates.set_label("Inicio: %s\nFin: %s" % (
                self._fmt_date(self.jira.current_sprint.start_ms),
                self._fmt_date(self.jira.current_sprint.end_ms)))
        else:
            self.sprint_dates.set_label("Sin sprint activo")
        self.avail_label.set_label("Disponible: %s" % util.fmt_hm(self.jira.sprint_available_sec))
        self.burned_label.set_label("Quemadas: %s" % util.fmt_hm(self.jira.sprint_consumed_sec))

        tip = self._breakdown_text()
        self.avail_label.set_tooltip_text(tip or None)

    def _breakdown_text(self):
        bd = self.jira.sprint_breakdown
        if not bd:
            return ""
        lines = ["%s: %s" % (b.key, util.fmt_hm(b.remaining_sec)) for b in bd[:20]]
        if len(bd) > 20:
            lines.append("…y %d más" % (len(bd) - 20))
        return "\n".join(lines)
