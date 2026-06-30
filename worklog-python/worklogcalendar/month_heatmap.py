"""month_heatmap.py - month-at-a-glance hours table (Clockify + Jira rows)."""
from __future__ import annotations
import math
from datetime import datetime, date

import cairo
from gi.repository import Gtk, GObject

from . import util

LETTER_H = 14
NUMBER_H = 16
CELL_H = 20
ICON_COL = 26


class MonthHeatmap(Gtk.Box):
    __gsignals__ = {"day-selected": (GObject.SignalFlags.RUN_FIRST, None, (GObject.TYPE_INT64,))}

    def __init__(self, clockify, jira):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        self.clockify = clockify
        self.jira = jira
        self.month_offset = 0
        self.clk_totals = {}
        self.jira_totals = {}
        self.clk_key = ""
        self.jira_key = ""
        self.req_id = 0
        self._build()
        self.refresh()

    def _build(self):
        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        title = Gtk.Label(label="Horas del mes")
        title.add_css_class("heading")
        header.append(title)
        spacer = Gtk.Box()
        spacer.set_hexpand(True)
        header.append(spacer)
        self.prev_btn = Gtk.Button.new_from_icon_name("go-previous-symbolic")
        self.prev_btn.add_css_class("flat")
        self.prev_btn.set_tooltip_text("Mes anterior")
        self.prev_btn.connect("clicked", lambda *_: self._set_offset(-1))
        header.append(self.prev_btn)
        self.month_label = Gtk.Label(label="")
        self.month_label.add_css_class("heading")
        self.month_label.set_width_chars(14)
        header.append(self.month_label)
        self.next_btn = Gtk.Button.new_from_icon_name("go-next-symbolic")
        self.next_btn.add_css_class("flat")
        self.next_btn.set_tooltip_text("Mes actual")
        self.next_btn.connect("clicked", lambda *_: self._set_offset(0))
        header.append(self.next_btn)
        self.append(header)

        self.grid = Gtk.DrawingArea()
        self.grid.set_content_height(LETTER_H + NUMBER_H + CELL_H * 2 + 6)
        self.grid.set_hexpand(True)
        self.grid.set_draw_func(self._draw)
        self.append(self.grid)

        click = Gtk.GestureClick()
        click.connect("released", self._on_click)
        self.grid.add_controller(click)

        self.footer = Gtk.Label(label="")
        self.footer.add_css_class("caption")
        self.footer.set_halign(Gtk.Align.START)
        self.append(self.footer)

    def _set_offset(self, off):
        if (off == -1 and self.month_offset > -1) or (off == 0 and self.month_offset < 0):
            self.month_offset = off
            self.refresh()

    def _ref_date(self):
        d = date.today().replace(day=1)
        m = d.month - 1 + self.month_offset
        y = d.year + m // 12
        return date(y, m % 12 + 1, 1)

    def _year(self):
        return self._ref_date().year

    def _month0(self):
        return self._ref_date().month - 1

    def _cur_key(self):
        return "%d-%d" % (self._year(), self._month0())

    def _days_in_month(self):
        r = self._ref_date()
        nxt = date(r.year + r.month // 12, r.month % 12 + 1, 1)
        return (nxt.toordinal() - r.toordinal())

    def refresh(self):
        self.prev_btn.set_sensitive(self.month_offset > -1)
        self.next_btn.set_sensitive(self.month_offset < 0)
        self.month_label.set_label("%s %d" % (util.month_name(self._month0()), self._year()))

        self.clk_totals, self.jira_totals = {}, {}
        self.clk_key, self.jira_key = "", ""
        self.grid.queue_draw()
        self._update_footer()

        self.req_id += 1
        req = self.req_id
        y, m = self._year(), self._month0()
        key = "%d-%d" % (y, m)

        def clk_done(ok, totals):
            if req != self.req_id:
                return
            self.clk_totals, self.clk_key = totals, key
            self.grid.queue_draw()
            self._update_footer()

        def jira_done(ok, totals):
            if req != self.req_id:
                return
            self.jira_totals, self.jira_key = totals, key
            self.grid.queue_draw()
            self._update_footer()
        self.clockify.fetch_month_totals(y, m, clk_done)
        self.jira.fetch_month_totals(y, m, jira_done)

    def _dow(self, day):
        return (date(self._year(), self._month0() + 1, day).weekday() + 1) % 7  # Sun=0

    def _is_weekend(self, day):
        return self._dow(day) in (0, 6)

    def _weekday_letter(self, day):
        return ["D", "L", "M", "Mi", "J", "V", "S"][self._dow(day)]

    def _clk_hours(self, day):
        if self.clk_key != self._cur_key():
            return 0
        return round((self.clk_totals.get(day, 0) / 3600.0) * 10) / 10

    def _jira_hours(self, day):
        if self.jira_key != self._cur_key():
            return 0
        return round((self.jira_totals.get(day, 0) / 3600.0) * 10) / 10

    @staticmethod
    def _lerp(a, b, t):
        c = util.hex_rgba("#000000")
        c.red = a.red + (b.red - a.red) * t
        c.green = a.green + (b.green - a.green) * t
        c.blue = a.blue + (b.blue - a.blue) * t
        c.alpha = 1
        return c

    def _cell_color(self, h):
        if h <= 0:
            g = util.hex_rgba("#ffffff", 0.06)
            return g
        red = util.hex_rgba("#e74c3c")
        yellow = util.hex_rgba("#f1c40f")
        green = util.hex_rgba("#81C784")
        c = min(4, h)
        if c <= 2:
            return self._lerp(red, yellow, c / 2)
        return self._lerp(yellow, green, (c - 2) / 2)

    def _draw(self, area, cr, width, height):
        days = self._days_in_month()
        col_w = (width - ICON_COL) / days
        if col_w <= 0:
            return
        cr.select_font_face("Sans", cairo.FontSlant.NORMAL, cairo.FontWeight.NORMAL)
        cr.set_font_size(9)
        self._text(cr, "⏱", 2, LETTER_H + NUMBER_H + CELL_H // 2 + 3, "#cccccc")
        self._text(cr, "J", 2, LETTER_H + NUMBER_H + CELL_H + CELL_H // 2 + 3, "#cccccc")

        for i in range(days):
            day = i + 1
            x = ICON_COL + i * col_w
            we = self._is_weekend(day)
            tc = "#888888" if we else "#dddddd"
            self._text_c(cr, self._weekday_letter(day), x, 0, col_w, LETTER_H, tc)
            self._text_c(cr, str(day), x, LETTER_H, col_w, NUMBER_H, tc)
            self._cell(cr, x, LETTER_H + NUMBER_H, col_w, CELL_H, self._clk_hours(day))
            self._cell(cr, x, LETTER_H + NUMBER_H + CELL_H, col_w, CELL_H, self._jira_hours(day))

    def _cell(self, cr, x, y, w, h, hours):
        c = self._cell_color(hours)
        self._rounded(cr, x + 1, y + 1, w - 2, h - 2, 2)
        cr.set_source_rgba(c.red, c.green, c.blue, c.alpha)
        cr.fill()
        if hours > 0:
            t = "%d" % int(hours) if hours == math.floor(hours) else "%.1f" % hours
            self._text_c(cr, t, x, y, w, h, "#1a1a1a", bold=True)

    @staticmethod
    def _rounded(cr, x, y, w, h, r):
        cr.new_sub_path()
        cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
        cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
        cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
        cr.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
        cr.close_path()

    @staticmethod
    def _text(cr, s, x, y, hexcol):
        c = util.hex_rgba(hexcol)
        cr.set_source_rgba(c.red, c.green, c.blue, 1)
        cr.move_to(x, y)
        cr.show_text(s)

    @staticmethod
    def _text_c(cr, s, x, y, w, h, hexcol, bold=False):
        cr.select_font_face("Sans", cairo.FontSlant.NORMAL,
                            cairo.FontWeight.BOLD if bold else cairo.FontWeight.NORMAL)
        ext = cr.text_extents(s)
        c = util.hex_rgba(hexcol)
        cr.set_source_rgba(c.red, c.green, c.blue, 1)
        cr.move_to(x + (w - ext.width) / 2 - ext.x_bearing, y + (h - ext.height) / 2 - ext.y_bearing)
        cr.show_text(s)

    def _on_click(self, gesture, n, x, y):
        days = self._days_in_month()
        width = self.grid.get_width()
        col_w = (width - ICON_COL) / days
        if x < ICON_COL or col_w <= 0:
            return
        i = int((x - ICON_COL) / col_w)
        if 0 <= i < days:
            d = datetime(self._year(), self._month0() + 1, i + 1)
            self.emit("day-selected", int(d.timestamp() * 1000))

    def _update_footer(self):
        clk = sum(self.clk_totals.values()) if self.clk_key == self._cur_key() else 0
        jr = sum(self.jira_totals.values()) if self.jira_key == self._cur_key() else 0
        self.footer.set_label("Total del mes — ⏱ %s · Jira %s" % (util.fmt_hm(clk), util.fmt_hm(jr)))
