"""calendar_grid.py - the week grid ("la planilla").

A single Cairo DrawingArea inside a ScrolledWindow renders the day headers,
totals row, hour column and 7 day columns with worklog blocks for both sources.
Combined mode splits each day in half (Jira left / Clockify right).

Interaction (GestureDrag + secondary GestureClick):
  drag empty -> create | click block -> edit | drag block -> move | edge -> resize
  right-click block -> menu (Duplicar / Editar)
"""
from __future__ import annotations
import math
from datetime import datetime

import cairo
from gi.repository import Gtk, Gdk, GObject

from . import util
from .models import Worklog, ClockifyEntry

HOUR_W = 56.0
ROW_H = 22.0
HEADER_H = 22.0
TOTALS_H = 22.0
GRID_TOP = HEADER_H + TOTALS_H
EDGE = 6.0

MODE_NONE, MODE_CREATE, MODE_MOVE, MODE_RTOP, MODE_RBOT = range(5)


class CalendarGrid(Gtk.Box):
    __gsignals__ = {
        "create-requested": (GObject.SignalFlags.RUN_FIRST, None,
                             (bool, GObject.TYPE_INT64, GObject.TYPE_INT64, GObject.TYPE_INT64)),
        "edit-requested": (GObject.SignalFlags.RUN_FIRST, None, (bool, GObject.TYPE_PYOBJECT)),
        "move-requested": (GObject.SignalFlags.RUN_FIRST, None,
                           (bool, GObject.TYPE_PYOBJECT, GObject.TYPE_INT64, GObject.TYPE_INT)),
        "duplicate-requested": (GObject.SignalFlags.RUN_FIRST, None, (bool, GObject.TYPE_PYOBJECT)),
    }

    def __init__(self, cfg, jira, clockify):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.cfg = cfg
        self.jira = jira
        self.clockify = clockify
        self.week_start = util.sunday_of(util.now_ms())
        self.source = "jira"
        self.last_width = 800

        self.scroller = Gtk.ScrolledWindow()
        self.scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.scroller.set_vexpand(True)
        self.scroller.set_hexpand(True)
        self.append(self.scroller)

        self.area = Gtk.DrawingArea()
        self.area.set_hexpand(True)
        self.area.set_content_height(int(GRID_TOP + self._slots() * ROW_H))
        self.area.set_draw_func(self._draw)
        self.scroller.set_child(self.area)

        jira.connect("changed", lambda *_: (self._update_height(), self.area.queue_draw()))
        clockify.connect("changed", lambda *_: self.area.queue_draw())

        drag = Gtk.GestureDrag()
        drag.connect("drag-begin", self._on_drag_begin)
        drag.connect("drag-update", self._on_drag_update)
        drag.connect("drag-end", self._on_drag_end)
        self.area.add_controller(drag)
        self._drag = drag

        rclick = Gtk.GestureClick()
        rclick.set_button(3)
        rclick.connect("released", self._on_right_click)
        self.area.add_controller(rclick)

        # drag state
        self.drag_mode = MODE_NONE
        self.press_x = self.press_y = 0.0
        self.press_is_jira = True
        self.press_day = 0
        self.drag_entry = None
        self.drag_started = 0
        self.drag_dur = 0
        self.fine = False
        self.sel_top = self.sel_bottom = 0.0

    def set_week(self, ms):
        self.week_start = ms
        self._update_height()
        self.area.queue_draw()

    def change_source(self, s):
        self.source = s
        self.area.queue_draw()

    def refresh(self):
        self._update_height()
        self.area.queue_draw()

    def _update_height(self):
        self.area.set_content_height(int(GRID_TOP + self._slots() * ROW_H))

    # ---- geometry ----
    def _combined(self):
        return self.source == "jira-clockify"

    def _show_jira(self):
        return self.source in ("jira", "jira-clockify")

    def _show_clockify(self):
        return self.source in ("clockify", "jira-clockify")

    def _start_hour(self):
        return 0 if self.cfg.view_mode == "24h" else 9

    def _end_hour(self):
        return 24 if self.cfg.view_mode == "24h" else 18

    def _slots(self):
        return (self._end_hour() - self._start_hour()) * 2

    def _col_w(self):
        return (self.last_width - HOUR_W) / 7.0

    def _day_ms(self, d):
        return util.add_days_ms(self.week_start, d)

    def _day_index_of(self, started):
        for d in range(7):
            if self._day_ms(d) <= started < self._day_ms(d + 1):
                return d
        return -1

    def _y_for(self, started, d):
        mins = (started - self._day_ms(d)) / 60000.0 - self._start_hour() * 60
        return GRID_TOP + (mins / 30.0) * ROW_H

    def _h_for(self, dur):
        return max(ROW_H / 3.0, (dur / 1800.0) * ROW_H)

    # ---- drawing ----
    def _draw(self, area, cr, width, height):
        self.last_width = width
        cr.select_font_face("Sans", cairo.FontSlant.NORMAL, cairo.FontWeight.NORMAL)
        cr.set_font_size(9)
        cw = self._col_w()
        slots = self._slots()

        for d in range(7):
            bx = HOUR_W + d * cw
            if self._is_weekend(d):
                cr.set_source_rgba(0, 0, 0, 0.18)
                cr.rectangle(bx, GRID_TOP, cw, slots * ROW_H)
                cr.fill()
            if self._is_today(d):
                cr.set_source_rgba(0.30, 0.55, 0.90, 0.10)
                cr.rectangle(bx, GRID_TOP, cw, slots * ROW_H)
                cr.fill()
            for s in range(slots):
                ry = GRID_TOP + s * ROW_H
                if s % 2 == 0:
                    cr.set_source_rgba(1, 1, 1, 0.03)
                    cr.rectangle(bx, ry, cw, ROW_H)
                    cr.fill()
                cr.set_source_rgba(1, 1, 1, 0.06)
                cr.set_line_width(1)
                cr.rectangle(bx + 0.5, ry + 0.5, cw - 1, ROW_H - 1)
                cr.stroke()
            if self._combined():
                cr.set_source_rgba(1, 1, 1, 0.12)
                cr.set_line_width(1)
                cr.move_to(bx + cw / 2, GRID_TOP)
                cr.line_to(bx + cw / 2, GRID_TOP + slots * ROW_H)
                cr.stroke()

        for s in range(slots):
            ry = GRID_TOP + s * ROW_H
            if s % 2 == 0:
                cr.set_source_rgba(1, 1, 1, 0.02)
                cr.rectangle(0, ry, HOUR_W, ROW_H)
                cr.fill()
            minutes = self._start_hour() * 60 + s * 30
            lbl = "%02d:%02d" % (minutes // 60, minutes % 60)
            cr.set_source_rgba(1, 1, 1, 0.85 if s % 2 == 0 else 0.45)
            ext = cr.text_extents(lbl)
            cr.move_to(HOUR_W - ext.width - 4, ry + ROW_H / 2 + ext.height / 2)
            cr.show_text(lbl)

        if self._show_jira():
            for w in self.jira.worklogs:
                self._draw_block(cr, w, True)
        if self._show_clockify():
            for e in self.clockify.entries:
                self._draw_block(cr, e, False)

        # headers + totals
        cr.set_source_rgba(0.12, 0.12, 0.14, 1)
        cr.rectangle(0, 0, width, GRID_TOP)
        cr.fill()
        self._cell_border(cr, 0, 0, HOUR_W, GRID_TOP)
        cr.set_source_rgba(1, 1, 1, 0.6)
        self._center(cr, "total", 0, 0, HOUR_W, GRID_TOP, False)
        for d in range(7):
            bx = HOUR_W + d * cw
            if self._is_today(d):
                cr.set_source_rgba(0.30, 0.55, 0.90, 0.22)
            elif self._is_weekend(d):
                cr.set_source_rgba(0, 0, 0, 0.18)
            else:
                cr.set_source_rgba(1, 1, 1, 0.04)
            cr.rectangle(bx, 0, cw, HEADER_H)
            cr.fill()
            self._cell_border(cr, bx, 0, cw, HEADER_H)
            cr.set_source_rgba(1, 1, 1, 1)
            self._center(cr, self._day_header(d), bx, 0, cw, HEADER_H, True)
            sec = self._total_for_day(d)
            t = self.cfg.daily_target_hours * 3600
            if sec <= 0:
                cr.set_source_rgba(1, 1, 1, 0.02)
            elif sec >= t:
                cr.set_source_rgba(0.18, 0.80, 0.44, 0.18)
            else:
                cr.set_source_rgba(0.95, 0.77, 0.06, 0.18)
            cr.rectangle(bx, HEADER_H, cw, TOTALS_H)
            cr.fill()
            self._cell_border(cr, bx, HEADER_H, cw, TOTALS_H)
            cr.set_source_rgba(1, 1, 1, 0.9)
            self._center(cr, self._totals_text(sec), bx, HEADER_H, cw, TOTALS_H, False)

        if self.drag_mode == MODE_CREATE:
            bx = HOUR_W + self.press_day * cw
            x, w = bx, cw
            if self._combined():
                x = bx if self.press_is_jira else bx + cw / 2
                w = cw / 2
            cr.set_source_rgba(0.30, 0.55, 0.90, 0.30)
            cr.rectangle(x, GRID_TOP + self.sel_top, w, self.sel_bottom - self.sel_top)
            cr.fill()
            cr.set_source_rgba(0.30, 0.55, 0.90, 1)
            cr.set_line_width(1)
            cr.rectangle(x + 0.5, GRID_TOP + self.sel_top + 0.5, w - 1, self.sel_bottom - self.sel_top - 1)
            cr.stroke()
            rng = util.fmt_clock(self._px_to_ms(self.press_day, self.sel_top)) + " - " + \
                util.fmt_clock(self._px_to_ms(self.press_day, self.sel_bottom))
            cr.set_source_rgba(1, 1, 1, 1)
            self._center(cr, rng, x, GRID_TOP + self.sel_top, w, self.sel_bottom - self.sel_top, True)

    def _draw_block(self, cr, entry, is_jira):
        eff_start = entry.started
        eff_dur = entry.duration_sec
        if self.drag_entry is entry:
            if self.drag_mode == MODE_MOVE:
                eff_start = self.drag_started
            elif self.drag_mode == MODE_RTOP:
                eff_start, eff_dur = self.drag_started, self.drag_dur
            elif self.drag_mode == MODE_RBOT:
                eff_dur = self.drag_dur
        d = self._day_index_of(eff_start)
        if d < 0:
            return
        cw = self._col_w()
        bx = HOUR_W + d * cw
        if self._combined():
            x = bx + 2 if is_jira else bx + cw / 2 + 1
            w = cw / 2 - 3
        else:
            x, w = bx + 2, cw - 4
        y = self._y_for(eff_start, d)
        h = self._h_for(eff_dur)

        if is_jira:
            cr.set_source_rgba(155 / 255, 145 / 255, 230 / 255, 0.55)
        else:
            if not self._combined() and entry.project_color:
                c = util.hex_rgba(entry.project_color, 0.6)
                cr.set_source_rgba(c.red, c.green, c.blue, c.alpha)
            else:
                cr.set_source_rgba(120 / 255, 215 / 255, 145 / 255, 0.55)
        self._rounded(cr, x, y, w, h, 3)
        cr.fill()
        if is_jira:
            cr.set_source_rgba(120 / 255, 110 / 255, 200 / 255, 0.95)
        else:
            cr.set_source_rgba(70 / 255, 170 / 255, 100 / 255, 0.95)
        cr.set_line_width(1)
        self._rounded(cr, x + 0.5, y + 0.5, w - 1, h - 1, 3)
        cr.stroke()

        cr.save()
        cr.rectangle(x + 2, y, w - 4, h)
        cr.clip()
        cr.set_source_rgba(1, 1, 1, 0.95)
        cr.set_font_size(8 if self._combined() else 9)
        top = "%s-%s" % (util.fmt_clock(eff_start), util.fmt_clock(eff_start + eff_dur * 1000))
        if is_jira:
            bottom = (entry.issue_key + ": " + entry.issue_summary) if (self.cfg.show_issue_summary and entry.issue_summary) else entry.issue_key
        else:
            bottom = entry.description or entry.project_name or "(sin descripción)"
        if h <= ROW_H + 1:
            cr.move_to(x + 4, y + h / 2 + 3)
            cr.show_text(util.fmt_clock(eff_start) + "  " + bottom)
        else:
            cr.move_to(x + 4, y + 11)
            cr.show_text(top)
            cr.move_to(x + 4, y + 22)
            cr.show_text(bottom)
        cr.restore()

    # ---- gestures ----
    def _shift(self, gesture):
        state = gesture.get_current_event_state()
        return bool(state & Gdk.ModifierType.SHIFT_MASK)

    def _on_drag_begin(self, gesture, x, y):
        self.press_x, self.press_y = x, y
        self.fine = self._shift(gesture)
        self.drag_entry = None
        self.drag_mode = MODE_NONE

        hit = self._hit_test(x, y)
        if hit is not None:
            entry, is_jira = hit
            self.drag_entry = entry
            self.press_is_jira = is_jira
            es, ed = entry.started, entry.duration_sec
            d = self._day_index_of(es)
            by = self._y_for(es, d)
            bh = self._h_for(ed)
            self.drag_started, self.drag_dur = es, ed
            if y - by <= EDGE:
                self.drag_mode = MODE_RTOP
            elif by + bh - y <= EDGE:
                self.drag_mode = MODE_RBOT
            else:
                self.drag_mode = MODE_MOVE
            return

        day = self._day_index_at(x)
        if day < 0:
            self.drag_mode = MODE_NONE
            return
        self.press_day = day
        cw = self._col_w()
        bx = HOUR_W + day * cw
        self.press_is_jira = (x - bx < cw / 2) if self._combined() else (self.source != "clockify")
        local_y = y - GRID_TOP
        self.sel_top = self._snap_px(local_y)
        self.sel_bottom = self.sel_top + self._step_px()
        self.drag_mode = MODE_CREATE
        self.area.queue_draw()

    def _on_drag_update(self, gesture, ox, oy):
        self.fine = self._shift(gesture)
        if self.drag_mode == MODE_CREATE:
            lo = min(self.press_y, self.press_y + oy) - GRID_TOP
            hi = max(self.press_y, self.press_y + oy) - GRID_TOP
            self.sel_top = self._snap_px(lo)
            self.sel_bottom = max(self.sel_top + self._step_px(), self._snap_px(hi) + self._step_px())
            self.area.queue_draw()
        elif self.drag_mode == MODE_MOVE:
            step = self._px_to_min(oy)
            cw = self._col_w()
            days = round(ox / cw) if cw > 0 else 0
            self.drag_started = self.drag_entry.started + days * util.DAY_MS + step * 60000
            self.area.queue_draw()
        elif self.drag_mode == MODE_RTOP:
            step = self._px_to_min(oy)
            self.drag_started = self.drag_entry.started + step * 60000
            self.drag_dur = max(600, self.drag_entry.duration_sec - step * 60)
            self.area.queue_draw()
        elif self.drag_mode == MODE_RBOT:
            step = self._px_to_min(oy)
            self.drag_dur = max(600, self.drag_entry.duration_sec + step * 60)
            self.area.queue_draw()

    def _on_drag_end(self, gesture, ox, oy):
        mode = self.drag_mode
        entry = self.drag_entry
        self.drag_mode = MODE_NONE
        self.drag_entry = None

        if mode == MODE_CREATE:
            start_ms = self._px_to_ms(self.press_day, self.sel_top)
            end_ms = self._px_to_ms(self.press_day, self.sel_bottom)
            if end_ms <= start_ms:
                end_ms = start_ms + (10 if self.fine else 30) * 60000
            self.emit("create-requested", self.press_is_jira, self._day_ms(self.press_day), start_ms, end_ms)
            self.area.queue_draw()
            return
        if entry is None:
            self.area.queue_draw()
            return

        moved = abs(ox) > 3 or abs(oy) > 3
        if not moved and mode == MODE_MOVE:
            self.emit("edit-requested", self.press_is_jira, entry)
            self.area.queue_draw()
            return
        ns = self._clamp_start(self.drag_started, self.drag_dur)
        nd = max(600, self.drag_dur)
        if ns != entry.started or nd != entry.duration_sec:
            self.emit("move-requested", self.press_is_jira, entry, ns, nd)
        else:
            self.area.queue_draw()

    def _on_right_click(self, gesture, n, x, y):
        hit = self._hit_test(x, y)
        if hit is None:
            return
        entry, is_jira = hit
        pop = Gtk.Popover()
        pop.set_parent(self.area)
        pop.set_pointing_to(Gdk.Rectangle(x=int(x), y=int(y), width=1, height=1))
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        for m in (box.set_margin_start, box.set_margin_end, box.set_margin_top, box.set_margin_bottom):
            m(6)
        dup = Gtk.Button.new_with_label("Duplicar")
        dup.add_css_class("flat")
        dup.connect("clicked", lambda *_: (self.emit("duplicate-requested", is_jira, entry), pop.popdown()))
        box.append(dup)
        ed = Gtk.Button.new_with_label("Editar")
        ed.add_css_class("flat")
        ed.connect("clicked", lambda *_: (self.emit("edit-requested", is_jira, entry), pop.popdown()))
        box.append(ed)
        pop.set_child(box)
        pop.popup()

    # ---- hit testing ----
    def _hit_test(self, x, y):
        if self._show_clockify():
            for e in reversed(self.clockify.entries):
                if self._point_in(x, y, e, False):
                    return (e, False)
        if self._show_jira():
            for w in reversed(self.jira.worklogs):
                if self._point_in(x, y, w, True):
                    return (w, True)
        return None

    def _point_in(self, x, y, entry, is_jira):
        d = self._day_index_of(entry.started)
        if d < 0:
            return False
        cw = self._col_w()
        bx = HOUR_W + d * cw
        if self._combined():
            rx = bx + 2 if is_jira else bx + cw / 2 + 1
            rw = cw / 2 - 3
        else:
            rx, rw = bx + 2, cw - 4
        ry = self._y_for(entry.started, d)
        rh = self._h_for(entry.duration_sec)
        return rx <= x <= rx + rw and ry <= y <= ry + rh

    # ---- snapping ----
    def _step_px(self):
        return ROW_H / 3.0 if self.fine else ROW_H

    def _snap_px(self, y):
        step = self._step_px()
        maxpx = self._slots() * ROW_H
        return max(0.0, min(maxpx, round(y / step) * step))

    def _px_to_min(self, px):
        g = 10 if self.fine else 30
        raw = (px / ROW_H) * 30
        return int(round(raw / g) * g)

    def _px_to_ms(self, day, px):
        mins = (px / ROW_H) * 30
        return self._day_ms(day) + int((self._start_hour() * 60 + mins) * 60000)

    def _day_index_at(self, x):
        if x < HOUR_W:
            return -1
        idx = int((x - HOUR_W) / self._col_w())
        return max(0, min(6, idx))

    def _clamp_start(self, start, dur):
        ws = self.week_start
        we = self._day_ms(7)
        durms = dur * 1000
        if start < ws:
            start = ws
        if start + durms > we:
            start = we - durms
        return start

    # ---- misc ----
    def _is_weekend(self, d):
        return d in (0, 6)

    def _is_today(self, d):
        return util.same_day(self._day_ms(d), util.now_ms())

    def _day_header(self, d):
        names = ["Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"]
        dt = datetime.fromtimestamp(self._day_ms(d) / 1000)
        return "%s %d/%s" % (names[d], dt.day, util.short_month(dt.month - 1))

    def _total_for_day(self, d):
        s = 0
        if self._show_jira():
            s = sum(w.duration_sec for w in self.jira.worklogs if self._day_index_of(w.started) == d)
        else:
            s = sum(e.duration_sec for e in self.clockify.entries if self._day_index_of(e.started) == d)
        return s

    def _totals_text(self, sec):
        if sec <= 0:
            return "—"
        diff = ""
        target = self.cfg.daily_target_hours * 3600
        d = sec - int(target)
        if d != 0:
            sign = "+" if d > 0 else "-"
            ad = abs(d)
            h, m = ad // 3600, (ad % 3600) // 60
            diff = " (%s%s%s)" % (sign, ("%dh" % h) if h else "", (("  " if h else "") + "%dm" % m) if m else "")
        return util.fmt_hm(sec) + diff

    @staticmethod
    def _rounded(cr, x, y, w, h, r):
        if w < 2 * r:
            r = w / 2
        if h < 2 * r:
            r = h / 2
        cr.new_sub_path()
        cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
        cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
        cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
        cr.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
        cr.close_path()

    @staticmethod
    def _cell_border(cr, x, y, w, h):
        cr.set_source_rgba(1, 1, 1, 0.1)
        cr.set_line_width(1)
        cr.rectangle(x + 0.5, y + 0.5, w - 1, h - 1)
        cr.stroke()

    @staticmethod
    def _center(cr, s, x, y, w, h, bold):
        cr.select_font_face("Sans", cairo.FontSlant.NORMAL,
                            cairo.FontWeight.BOLD if bold else cairo.FontWeight.NORMAL)
        cr.set_font_size(9)
        ext = cr.text_extents(s)
        cr.move_to(x + (w - ext.width) / 2 - ext.x_bearing, y + (h - ext.height) / 2 - ext.y_bearing)
        cr.show_text(s)
