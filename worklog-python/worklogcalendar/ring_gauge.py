"""ring_gauge.py - circular donut gauge with a center percentage label."""
from __future__ import annotations
import math

import cairo
from gi.repository import Gtk, GLib

from . import util


class RingGauge(Gtk.DrawingArea):
    def __init__(self, diameter=110):
        super().__init__()
        self.set_content_width(diameter)
        self.set_content_height(diameter)
        self.value = 0.0
        self.base_color = util.hex_rgba("#81C784")
        self.pale_color = util.hex_rgba("#C8E6C9")
        self.track_color = util.hex_rgba("#2a2a2a")
        self.thickness = 12.0
        self.use_fade_loop = False
        self.intermittent = False
        self._display = 0.0
        self._fade_t = 0.0
        self._fill_start = 0
        self._filling = False
        self.set_draw_func(self._draw)
        self.add_tick_callback(self._on_tick)

    def set_value(self, v):
        self.value = v
        if not self._filling:
            self._display = v
            self.queue_draw()

    def start_fill(self):
        self._display = 0.0
        fc = self.get_frame_clock()
        self._fill_start = fc.get_frame_time() if fc else GLib.get_monotonic_time()
        self._filling = True
        self.queue_draw()

    def _on_tick(self, widget, clock):
        now = clock.get_frame_time()
        redraw = False
        if self._filling:
            t = (now - self._fill_start) / 1_000_000.0 / 1.5
            if t >= 1.0:
                t = 1.0
                self._filling = False
            e = 1 - math.pow(1 - t, 4)  # OutQuart
            self._display = self.value * e
            redraw = True
        if self.use_fade_loop:
            cycle = 2.0 if self.intermittent else 4.5
            phase = ((now / 1_000_000.0) % cycle) / cycle
            self._fade_t = 0.5 - 0.5 * math.cos(phase * 2 * math.pi)
            redraw = True
        if redraw:
            self.queue_draw()
        return GLib.SOURCE_CONTINUE

    @staticmethod
    def _lerp(a, b, t):
        c = util.hex_rgba("#000000")
        c.red = a.red + (b.red - a.red) * t
        c.green = a.green + (b.green - a.green) * t
        c.blue = a.blue + (b.blue - a.blue) * t
        c.alpha = 1
        return c

    def _draw(self, area, cr, width, height):
        cx, cy = width / 2.0, height / 2.0
        r = (min(width, height) - self.thickness) / 2.0
        cr.set_line_cap(cairo.LineCap.ROUND)
        cr.set_line_width(self.thickness)

        t = self.track_color
        cr.set_source_rgba(t.red, t.green, t.blue, t.alpha)
        cr.arc(cx, cy, r, 0, 2 * math.pi)
        cr.stroke()

        v = max(0.0, min(100.0, self._display))
        if v > 0:
            col = self._lerp(self.base_color, self.pale_color, self._fade_t) if self.use_fade_loop else self.base_color
            start_a = -math.pi / 2
            end_a = start_a + (v / 100.0) * 2 * math.pi
            cr.set_source_rgba(col.red, col.green, col.blue, 1)
            cr.arc(cx, cy, r, start_a, end_a)
            cr.stroke()

        label = "%d%%" % round(self._display)
        cr.select_font_face("Sans", cairo.FontSlant.NORMAL, cairo.FontWeight.BOLD)
        cr.set_font_size(round(min(width, height) * 0.22))
        ext = cr.text_extents(label)
        fg = self.get_color()
        cr.set_source_rgba(fg.red, fg.green, fg.blue, fg.alpha)
        cr.move_to(cx - ext.width / 2 - ext.x_bearing, cy - ext.height / 2 - ext.y_bearing)
        cr.show_text(label)
