"""tray.py - top-bar "white clock" indicator via the StatusNotifierItem spec.

Exports org.kde.StatusNotifierItem + a minimal com.canonical.dbusmenu over the
session bus and registers with org.kde.StatusNotifierWatcher (provided on
GNOME/Ubuntu by the bundled AppIndicators extension). Left-click -> Activate ->
show the clock window; right-click -> menu whose last item is "Salir".

If no watcher is present the registration just fails; the app keeps working
through its windows.
"""
from __future__ import annotations
import random

from gi.repository import Gio, GLib, GObject

from . import APP_ID

ID_CLOCK, ID_APP, ID_SEP, ID_QUIT = 1, 2, 3, 4

SNI_XML = """
<node>
  <interface name="org.kde.StatusNotifierItem">
    <property name="Category" type="s" access="read"/>
    <property name="Id" type="s" access="read"/>
    <property name="Title" type="s" access="read"/>
    <property name="Status" type="s" access="read"/>
    <property name="IconName" type="s" access="read"/>
    <property name="IconThemePath" type="s" access="read"/>
    <property name="ItemIsMenu" type="b" access="read"/>
    <property name="Menu" type="o" access="read"/>
    <method name="ContextMenu"><arg name="x" type="i" direction="in"/><arg name="y" type="i" direction="in"/></method>
    <method name="Activate"><arg name="x" type="i" direction="in"/><arg name="y" type="i" direction="in"/></method>
    <method name="SecondaryActivate"><arg name="x" type="i" direction="in"/><arg name="y" type="i" direction="in"/></method>
    <method name="Scroll"><arg name="delta" type="i" direction="in"/><arg name="orientation" type="s" direction="in"/></method>
    <signal name="NewIcon"/>
    <signal name="NewStatus"><arg name="status" type="s"/></signal>
  </interface>
</node>"""

MENU_XML = """
<node>
  <interface name="com.canonical.dbusmenu">
    <property name="Version" type="u" access="read"/>
    <property name="Status" type="s" access="read"/>
    <method name="GetLayout">
      <arg name="parentId" type="i" direction="in"/>
      <arg name="recursionDepth" type="i" direction="in"/>
      <arg name="propertyNames" type="as" direction="in"/>
      <arg name="revision" type="u" direction="out"/>
      <arg name="layout" type="(ia{sv}av)" direction="out"/>
    </method>
    <method name="GetGroupProperties">
      <arg name="ids" type="ai" direction="in"/>
      <arg name="propertyNames" type="as" direction="in"/>
      <arg name="properties" type="a(ia{sv})" direction="out"/>
    </method>
    <method name="GetProperty">
      <arg name="id" type="i" direction="in"/>
      <arg name="name" type="s" direction="in"/>
      <arg name="value" type="v" direction="out"/>
    </method>
    <method name="Event">
      <arg name="id" type="i" direction="in"/>
      <arg name="eventId" type="s" direction="in"/>
      <arg name="data" type="v" direction="in"/>
      <arg name="timestamp" type="u" direction="in"/>
    </method>
    <method name="AboutToShow">
      <arg name="id" type="i" direction="in"/>
      <arg name="needUpdate" type="b" direction="out"/>
    </method>
    <signal name="LayoutUpdated"><arg name="revision" type="u"/><arg name="parent" type="i"/></signal>
  </interface>
</node>"""


class TrayIcon(GObject.GObject):
    __gsignals__ = {
        "activate": (GObject.SignalFlags.RUN_FIRST, None, ()),
        "show-clock": (GObject.SignalFlags.RUN_FIRST, None, ()),
        "open-app": (GObject.SignalFlags.RUN_FIRST, None, ()),
        "quit": (GObject.SignalFlags.RUN_FIRST, None, ()),
    }

    def __init__(self):
        super().__init__()
        self.bus_name = "org.kde.StatusNotifierItem-%d-1" % random.randint(1, 2_000_000_000)
        self.conn = None

    def register(self):
        Gio.bus_own_name(Gio.BusType.SESSION, self.bus_name, Gio.BusNameOwnerFlags.NONE,
                         self._on_bus_acquired, self._on_name_acquired, self._on_name_lost)

    def _on_bus_acquired(self, conn, name):
        self.conn = conn
        try:
            sni = Gio.DBusNodeInfo.new_for_xml(SNI_XML)
            menu = Gio.DBusNodeInfo.new_for_xml(MENU_XML)
            conn.register_object("/StatusNotifierItem", sni.interfaces[0],
                                 self._sni_method, self._sni_get_prop, None)
            conn.register_object("/MenuBar", menu.interfaces[0],
                                 self._menu_method, self._menu_get_prop, None)
        except Exception as e:  # noqa: BLE001
            print("SNI register_object failed:", e)

    def _on_name_acquired(self, conn, name):
        try:
            conn.call("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher",
                      "org.kde.StatusNotifierWatcher", "RegisterStatusNotifierItem",
                      GLib.Variant("(s)", (self.bus_name,)), None,
                      Gio.DBusCallFlags.NONE, -1, None, None)
        except Exception as e:  # noqa: BLE001
            print("No StatusNotifierWatcher:", e)

    def _on_name_lost(self, conn, name):
        pass

    # ---- StatusNotifierItem ----
    def _sni_method(self, connection, sender, path, interface, method, params, invocation):
        if method == "Activate":
            self.emit("activate")
        elif method == "SecondaryActivate":
            self.emit("show-clock")
        invocation.return_value(None)

    def _sni_get_prop(self, connection, sender, path, interface, name):
        return {
            "Category": GLib.Variant("s", "ApplicationStatus"),
            "Id": GLib.Variant("s", APP_ID),
            "Title": GLib.Variant("s", "Worklog Calendar"),
            "Status": GLib.Variant("s", "Active"),
            "IconName": GLib.Variant("s", APP_ID + "-symbolic"),
            "IconThemePath": GLib.Variant("s", ""),
            "ItemIsMenu": GLib.Variant("b", False),
            "Menu": GLib.Variant("o", "/MenuBar"),
        }.get(name)

    # ---- com.canonical.dbusmenu ----
    def _menu_method(self, connection, sender, path, interface, method, params, invocation):
        if method == "GetLayout":
            invocation.return_value(GLib.Variant("(u(ia{sv}av))", (1, self._layout_root())))
        elif method == "GetGroupProperties":
            rows = [(i, self._props_for(i)) for i in (0, ID_CLOCK, ID_APP, ID_SEP, ID_QUIT)]
            invocation.return_value(GLib.Variant("(a(ia{sv}))", (rows,)))
        elif method == "GetProperty":
            id_, name = params.unpack()
            invocation.return_value(GLib.Variant("(v)", (self._prop_value(id_, name),)))
        elif method == "Event":
            id_, event_id, _data, _ts = params.unpack()
            if event_id == "clicked":
                self._menu_clicked(id_)
            invocation.return_value(None)
        elif method == "AboutToShow":
            invocation.return_value(GLib.Variant("(b)", (False,)))
        else:
            invocation.return_value(None)

    def _menu_get_prop(self, connection, sender, path, interface, name):
        if name == "Version":
            return GLib.Variant("u", 3)
        if name == "Status":
            return GLib.Variant("s", "normal")
        return None

    def _menu_clicked(self, id_):
        if id_ == ID_CLOCK:
            self.emit("show-clock")
        elif id_ == ID_APP:
            self.emit("open-app")
        elif id_ == ID_QUIT:
            self.emit("quit")

    # ---- menu model ----
    @staticmethod
    def _label_for(id_):
        return {ID_CLOCK: "Mostrar reloj", ID_APP: "Abrir aplicación", ID_QUIT: "Salir"}.get(id_, "")

    def _props_for(self, id_):
        if id_ == 0:
            return {"children-display": GLib.Variant("s", "submenu")}
        if id_ == ID_SEP:
            return {"type": GLib.Variant("s", "separator")}
        return {"label": GLib.Variant("s", self._label_for(id_)),
                "enabled": GLib.Variant("b", True),
                "visible": GLib.Variant("b", True)}

    def _item_node(self, id_):
        return GLib.Variant("(ia{sv}av)", (id_, self._props_for(id_), []))

    def _layout_root(self):
        children = [self._item_node(i) for i in (ID_CLOCK, ID_APP, ID_SEP, ID_QUIT)]
        return (0, self._props_for(0), children)

    def _prop_value(self, id_, name):
        if name == "label":
            return GLib.Variant("s", self._label_for(id_))
        if name in ("enabled", "visible"):
            return GLib.Variant("b", True)
        if name == "type" and id_ == ID_SEP:
            return GLib.Variant("s", "separator")
        return GLib.Variant("s", "")
