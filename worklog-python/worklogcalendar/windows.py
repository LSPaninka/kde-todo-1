"""windows.py - MainWindow (full app) + PopupWindow (1000x700 clock window).

Both hide instead of quitting when "run in background" is on, so the app keeps
living in the tray; the only true exit is the indicator's "Salir".
"""
from __future__ import annotations

from gi.repository import Gtk, Adw, Gio

from . import APP_ID, VERSION
from .worklog_view import WorklogView


class MainWindow(Adw.ApplicationWindow):
    def __init__(self, app, cfg, jira, clockify):
        super().__init__(application=app)
        self.app = app
        self.cfg = cfg
        self.set_title("Worklog Calendar")
        self.set_default_size(cfg.settings.get_int("window-width"), cfg.settings.get_int("window-height"))
        self.set_icon_name(APP_ID)

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()
        menu_btn = Gtk.MenuButton()
        menu_btn.set_icon_name("open-menu-symbolic")
        menu_btn.set_menu_model(self._menu())
        header.pack_end(menu_btn)
        toolbar.add_top_bar(header)

        self.view = WorklogView(cfg, jira, clockify, False)
        self.view.connect("open-prefs-requested", lambda *_: app.open_prefs(self))
        toolbar.set_content(self.view)
        self.set_content(toolbar)

        for name, fn in (("preferences", lambda *_: app.open_prefs(self)),
                         ("about", lambda *_: self._about()),
                         ("quit", lambda *_: app.quit_app())):
            action = Gio.SimpleAction.new(name, None)
            action.connect("activate", fn)
            self.add_action(action)

        self.connect("close-request", self._on_close)

    def _menu(self):
        menu = Gio.Menu()
        menu.append("Preferencias", "win.preferences")
        menu.append("Acerca de", "win.about")
        menu.append("Salir", "win.quit")
        return menu

    def _on_close(self, *_):
        self.cfg.settings.set_int("window-width", self.get_width())
        self.cfg.settings.set_int("window-height", self.get_height())
        if self.cfg.run_in_background:
            self.set_visible(False)
            return True
        return False

    def sync(self):
        self.view.sync_now()

    def _about(self):
        about = Adw.AboutWindow(transient_for=self)
        about.set_application_name("Worklog Calendar")
        about.set_application_icon(APP_ID)
        about.set_version(VERSION)
        about.set_developer_name("Peperina")
        about.set_comments("Vista semanal de worklogs de Jira y Clockify para GNOME / Ubuntu 24 (PyGObject).")
        about.set_license_type(Gtk.License.MIT_X11)
        about.present()


class PopupWindow(Adw.ApplicationWindow):
    def __init__(self, app, cfg, jira, clockify):
        super().__init__(application=app)
        self.app = app
        self.cfg = cfg
        self.set_title("Worklog")
        self.set_default_size(cfg.settings.get_int("popup-width"), cfg.settings.get_int("popup-height"))
        self.set_icon_name(APP_ID)

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()
        header.set_show_title(False)
        toolbar.add_top_bar(header)

        self.view = WorklogView(cfg, jira, clockify, True)
        self.view.connect("open-app-requested", lambda *_: (app.show_main(), self.set_visible(False)))
        self.view.connect("open-prefs-requested", lambda *_: app.open_prefs(self))
        toolbar.set_content(self.view)
        self.set_content(toolbar)

        self.connect("close-request", self._on_close)

    def _on_close(self, *_):
        if self.cfg.run_in_background:
            self.set_visible(False)
            return True
        return False

    def sync(self):
        self.view.sync_now()
