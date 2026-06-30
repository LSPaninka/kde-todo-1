"""application.py - the Adw.Application orchestrating windows, stores and tray.

Background behaviour: when "run in background" is on, closing a window hides it
(handled in windows.py) and the app is kept alive with hold(); the only true
exit is the tray's "Salir" (or the in-app menu's Salir).
"""
from __future__ import annotations

from gi.repository import Gtk, Adw, Gio, Gdk

from . import APP_ID
from .config import Config
from .http import Http
from .jira_store import JiraStore
from .clockify_store import ClockifyStore
from .windows import MainWindow, PopupWindow
from .preferences import PreferencesWindow
from .tray import TrayIcon

_CSS = """
.dim-line { background: alpha(@theme_fg_color, 0.10); min-height: 1px; }
.worklog-badge { font-size: 0.8em; border-radius: 6px; padding: 1px 6px; color: white; }
.wb-green     { background: #2ea043; }
.wb-yellow    { background: #d29922; }
.wb-bluegray  { background: #6e7681; }
.wb-brown     { background: #a36a3d; }
.wb-warmred   { background: #e5534b; }
.wb-mediumgray{ background: #8b949e; }
.error { color: @error_color; }
"""


class WorklogApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.DEFAULT_FLAGS)
        self.cfg = None
        self.http = None
        self.jira = None
        self.clockify = None
        self.tray = None
        self.main_window = None
        self.popup = None
        self.prefs = None
        self._held = False

    def do_startup(self):
        Adw.Application.do_startup(self)
        self.cfg = Config()
        self.http = Http()
        self.jira = JiraStore(self.cfg, self.http)
        self.clockify = ClockifyStore(self.cfg, self.http)
        self._load_css()

        self.hold()
        self._held = True

        if self.cfg.show_tray_icon:
            self._setup_tray()

        quit_action = Gio.SimpleAction.new("quit", None)
        quit_action.connect("activate", lambda *_: self.quit_app())
        self.add_action(quit_action)
        self.set_accels_for_action("app.quit", ["<Control>q"])

    def do_activate(self):
        self.show_main()

    def _setup_tray(self):
        self.tray = TrayIcon()
        self.tray.connect("activate", lambda *_: self.show_clock())
        self.tray.connect("show-clock", lambda *_: self.show_clock())
        self.tray.connect("open-app", lambda *_: self.show_main())
        self.tray.connect("quit", lambda *_: self.quit_app())
        self.tray.register()

    def show_clock(self):
        if self.popup is None:
            self.popup = PopupWindow(self, self.cfg, self.jira, self.clockify)
        self.popup.present()
        self.popup.sync()

    def show_main(self):
        if self.main_window is None:
            self.main_window = MainWindow(self, self.cfg, self.jira, self.clockify)
        self.main_window.present()
        self.main_window.sync()

    def open_prefs(self, parent):
        if self.prefs is None:
            self.prefs = PreferencesWindow(parent, self.cfg, self.jira, self.clockify)
            self.prefs.connect("close-request", self._on_prefs_closed)
        self.prefs.present()

    def _on_prefs_closed(self, *_):
        self.prefs = None
        return False

    def quit_app(self):
        if self._held:
            self.release()
            self._held = False
        if self.popup is not None:
            self.popup.destroy()
        if self.main_window is not None:
            self.main_window.destroy()
        self.quit()

    def _load_css(self):
        provider = Gtk.CssProvider()
        provider.load_from_string(_CSS)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
