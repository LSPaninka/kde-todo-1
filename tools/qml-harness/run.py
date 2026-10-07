#!/usr/bin/env python3
"""Arnés de render offscreen para el plasmoide (Plasma 6 / Qt 6).

Sustituye los módulos KDE por simulaciones mínimas (fake/), genera el
singleton `Plasmoid` con los valores por defecto de contents/config/main.xml,
instancia el main.qml real y captura imágenes. Cuenta los WARNING que salen
del código del plasmoide.

Uso:  python3 run.py <package_dir> <out_dir>
Requisitos: PySide6-Essentials, libegl1 (QT_QPA_PLATFORM=offscreen).
"""
import json, os, sys, tempfile, threading, shutil
import xml.etree.ElementTree as ET
from http.server import BaseHTTPRequestHandler, HTTPServer

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Fusion")

here = os.path.dirname(os.path.abspath(__file__))
pkg = os.path.abspath(sys.argv[1])
out = os.path.abspath(sys.argv[2])
os.makedirs(out, exist_ok=True)
tmp = tempfile.mkdtemp(prefix="qmlharness-")
os.environ["XDG_DATA_HOME"] = os.path.join(tmp, "data")
os.environ["XDG_CONFIG_HOME"] = os.path.join(tmp, "config")

from PySide6.QtCore import (QObject, Slot, QUrl, QTimer, qInstallMessageHandler,
                            QtMsgType, QCoreApplication)
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickView
from PySide6.QtQml import QQmlApplicationEngine  # noqa: F401  (registra QtQml)

# ---------------------------------------------------------------- Jira falso
ISSUES = [
    ("CP-101", "Diseñar la pantalla de login", "Tarea", "To Do", "new", "High", False),
    ("CP-102", "Corregir el cálculo de horas del sprint", "Error", "In Progress", "indeterminate", "Highest", False),
    ("CP-103", "Revisar PR de autenticación", "Subtarea", "In Progress", "indeterminate", "Medium", True),
    ("CP-104", "Documentar la API de reportes", "Tarea", "To Do", "new", "Low", False),
    ("CP-105", "Migrar la base de datos a v5", "Historia", "Done", "done", "Medium", False),
    ("CP-106", "Escribir pruebas de integración", "Subtarea", "To Do", "new", "Medium", True),
]

class FakeJira(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, obj):
        body = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_GET(self):
        if "/search/jql" in self.path:
            issues = []
            for k, s, t, st, cat, pr, sub in ISSUES:
                issues.append({"key": k, "fields": {
                    "summary": s, "status": {"name": st, "statusCategory": {"key": cat}},
                    "priority": {"name": pr}, "issuetype": {"name": t, "subtask": sub},
                    "updated": "2026-10-01T10:00:00.000+0000",
                    "timetracking": {"originalEstimateSeconds": 14400, "timeSpentSeconds": 3600}}})
            self._send({"issues": issues, "isLast": True})
        elif self.path.endswith("/myself"):
            self._send({"accountId": "me-123", "displayName": "Test"})
        else:
            self._send({})
    do_POST = do_GET

srv = HTTPServer(("127.0.0.1", 0), FakeJira)
threading.Thread(target=srv.serve_forever, daemon=True).start()
jira_url = "http://127.0.0.1:%d" % srv.server_port

# ------------------------------------------- módulo plasmoid (generado)
def js(v):
    return json.dumps(v, ensure_ascii=False)

def build_plasmoid_module(main_xml, dest):
    ns = {"k": "http://www.kde.org/standards/kcfg/1.0"}
    root = ET.parse(main_xml).getroot()
    props = []
    for e in root.iterfind(".//k:entry", ns):
        name, typ = e.get("name"), e.get("type")
        d = e.find("k:default", ns)
        raw = (d.text or "") if d is not None else ""
        if typ == "Bool": val = raw.strip().lower() == "true"
        elif typ == "Int": val = int(raw.strip() or 0)
        elif typ == "StringList": val = [x for x in raw.split(",")] if raw else []
        else: val = raw
        props.append("        property var %s: %s" % (name, js(val)))
    os.makedirs(dest, exist_ok=True)
    open(os.path.join(dest, "qmldir"), "w").write(
        "module org.kde.plasma.plasmoid\nsingleton Plasmoid 1.0 Plasmoid.qml\nPlasmoidItem 1.0 PlasmoidItem.qml\n")
    open(os.path.join(dest, "Plasmoid.qml"), "w").write(
        "pragma Singleton\nimport QtQuick\n\nQtObject {\n"
        "    property int formFactor: 2\n    property int location: 3\n"
        "    property bool immutable: false\n"
        "    property QtObject configuration: QtObject {\n" + "\n".join(props) + "\n    }\n"
        "    function internalAction(name) {\n"
        "        return { trigger: function() { console.log('HARNESS internalAction(' + name + ').trigger()'); } };\n"
        "    }\n}\n")
    open(os.path.join(dest, "PlasmoidItem.qml"), "w").write(
        "import QtQuick\n\nItem {\n"
        "    property Component compactRepresentation\n    property Component fullRepresentation\n"
        "    property int preferredRepresentation: 0\n    property bool expanded: false\n"
        "    property real switchWidth: 0\n    property real switchHeight: 0\n"
        "    property string toolTipMainText\n    property string toolTipSubText\n"
        "    property int toolTipTextFormat: 0\n    property bool hideOnWindowDeactivate: true\n}\n")

gen = os.path.join(tmp, "gen")
build_plasmoid_module(os.path.join(pkg, "contents/config/main.xml"),
                      os.path.join(gen, "org/kde/plasma/plasmoid"))

# --------------------------------------------------------------- i18n falso
class I18n(QObject):
    @staticmethod
    def _fmt(fmt, args):
        for i, a in enumerate(args, 1):
            fmt = fmt.replace("%%%d" % i, str(a))
        return fmt
    @Slot(str, result=str)
    @Slot(str, "QVariant", result=str)
    @Slot(str, "QVariant", "QVariant", result=str)
    @Slot(str, "QVariant", "QVariant", "QVariant", result=str)
    def i18n(self, fmt, *args): return self._fmt(fmt, args)
    @Slot(str, str, "QVariant", result=str)
    @Slot(str, str, "QVariant", "QVariant", result=str)
    def i18np(self, one, many, n, *rest):
        return self._fmt(one if int(n) == 1 else many, (n,) + rest)
    @Slot(str, str, result=str)
    @Slot(str, str, "QVariant", result=str)
    @Slot(str, str, "QVariant", "QVariant", result=str)
    def i18nc(self, ctx, fmt, *args): return self._fmt(fmt, args)

# ----------------------------------------------------- captura de mensajes
messages = []
def handler(mode, ctx, msg):
    kind = {QtMsgType.QtDebugMsg: "DEBUG", QtMsgType.QtInfoMsg: "INFO",
            QtMsgType.QtWarningMsg: "WARNING", QtMsgType.QtCriticalMsg: "CRITICAL",
            QtMsgType.QtFatalMsg: "FATAL"}[mode]
    messages.append((kind, ctx.file or "", ctx.line, msg))
qInstallMessageHandler(handler)

app = QGuiApplication(sys.argv)
from PySide6.QtGui import QPalette, QColor
pal = QPalette()
for role, col in [(QPalette.Window, "#2a2e32"), (QPalette.WindowText, "#fcfcfc"),
                  (QPalette.Base, "#1b1e20"), (QPalette.AlternateBase, "#232629"),
                  (QPalette.Text, "#fcfcfc"), (QPalette.Button, "#31363b"),
                  (QPalette.ButtonText, "#fcfcfc"), (QPalette.Highlight, "#3daee9"),
                  (QPalette.HighlightedText, "#fcfcfc"), (QPalette.ToolTipBase, "#31363b"),
                  (QPalette.ToolTipText, "#fcfcfc"), (QPalette.PlaceholderText, "#a1a9b1")]:
    pal.setColor(role, QColor(col))
app.setPalette(pal)
app.setOrganizationName("KDE")
app.setApplicationName("plasmashell")
view = QQuickView()
view.engine().addImportPath(os.path.join(here, "fake"))
view.engine().addImportPath(gen)
i18n = I18n()
view.rootContext().setContextObject(i18n)
view.setResizeMode(QQuickView.SizeRootObjectToView)
view.setSource(QUrl.fromLocalFile(os.path.join(here, "Harness.qml")))
if view.status() != QQuickView.Ready:
    print("Harness no cargó:", view.errors()); sys.exit(2)
view.resize(980, 760)
view.show()
root = view.rootObject()

def pump(ms):
    import time
    end = time.time() + ms / 1000.0
    while time.time() < end:
        app.processEvents()
        time.sleep(0.01)

def call(name, *args):
    from PySide6.QtCore import QMetaObject, Qt, Q_ARG
    from PySide6.QtCore import QGenericArgument
    return QMetaObject.invokeMethod(root, name, Qt.DirectConnection,
                                    *[Q_ARG("QVariant", a) for a in args])

def snap(name):
    pump(500)
    img = view.grabWindow()
    path = os.path.join(out, name + ".png")
    img.save(path)
    print("capturado", path)

def ev(js_code):
    """Evalúa JS en el contexto del arnés (root es `host`)."""
    from PySide6.QtQml import QQmlExpression
    from PySide6.QtQml import QQmlEngine
    ex = QQmlExpression(QQmlEngine.contextForObject(root), root, js_code)
    r = ex.evaluate()
    if ex.hasError(): print("ERROR ev:", ex.error().toString())
    return r

call("start", QUrl.fromLocalFile(os.path.join(pkg, "contents/ui/main.qml")).toString())
pump(800)

# ---- ToDo: datos de ejemplo
ev("""(function(){
  var s = host.store();
  var t1 = s.addTask('Comprar leche', 0, 'M', 'Del súper de la esquina');
  s.addTask('Terminar informe', 1, 'XL', 'Entrega el viernes');
  s.addTask('Estudiar Qt 6', 2, 'L', '');
  s.addTask('Llamar al médico', 4, 'S', '');
  s.addTask('Tarea hecha', 0, 'XS', '');
  return 1;
})()""")
pump(300)
ev("host.store().tasks.length")
snap("01-todo")
# Un par de ciclos de rueda / clic en la compacta
ev("host.app.expanded = true")
ev("host.store().requestCategory(1)")
snap("02-todo-categoria")

# ---- Jira 1
ev("host.cfg('jiraSite', '%s'); host.cfg('jiraEmail', 'a@b.c'); host.cfg('jiraToken', 'tok'); host.cfg('jiraJql', 'assignee = currentUser()')" % jira_url)
ev("host.cfg('jira2Site', '%s'); host.cfg('jira2Email', 'a@b.c'); host.cfg('jira2Token', 'tok'); host.cfg('jira2Jql', 'assignee = currentUser()')" % jira_url)
ev("host.setMode('jira')")
pump(1500)
snap("03-jira")
ev("host.setMode('jira2')")
pump(1500)
snap("04-jira2")
ev("host.setMode('gh')")
snap("05-gh")
ev("host.setMode('todo')")
snap("06-todo-vuelta")
ev("host.app.expanded = false")
pump(300)


# ---- Interacciones con eventos reales de ratón / teclado / rueda
from PySide6.QtTest import QTest
from PySide6.QtCore import Qt, QPoint, QPointF
from PySide6.QtGui import QWheelEvent

def click(x, y, button=Qt.LeftButton):
    QTest.mouseClick(view, button, Qt.NoModifier, QPoint(x, y))
    pump(250)

def key(k):
    QTest.keyClick(view, k)
    pump(250)

def wheel(x, y, dy):
    e = QWheelEvent(QPointF(x, y), QPointF(view.mapToGlobal(QPoint(x, y))), QPoint(0, 0),
                    QPoint(0, dy), Qt.NoButton, Qt.NoModifier, Qt.NoScrollPhase, False)
    QCoreApplication.sendEvent(view, e)
    pump(300)

def state():
    return ev("JSON.stringify({expanded: host.app.expanded, mode: host.cfg_get('mode')})")

ev("host.setMode('todo')")
ev("host.app.expanded = false")
pump(300)
print("estado inicial:", state())
click(443, 31)                      # swatch 2 (Trabajo) de la compacta
print("tras clic en swatch 2 (debe abrir y saltar a Trabajo):", state(),
      "store.selectedCategory:", ev("host.store().selectedCategory"))
snap("07a-todo-tras-clic-swatch")
click(443, 31)
print("tras segundo clic (debe cerrar):", state())
wheel(443, 31, 120)
print("rueda arriba sobre la compacta (todo -> jira):", state())
wheel(443, 31, -120)
print("rueda abajo (jira -> todo):", state())
wheel(443, 31, -120)
print("rueda sobre un swatch:", state())
ev("host.setMode('todo')")
ev("host.app.expanded = true")
ev("host.store().requestCategory(1)")
pump(300)
click(925, 104)                     # botón "New…" de la categoría
snap("07-todo-dialogo-nueva-tarea")
key(Qt.Key_Escape)
click(925, 736)                     # "Configure…"
ev("host.setMode('jira')")
pump(1500)
click(400, 160)                     # tarjeta CP-101 -> JiraIssueDialog
snap("08-jira-detalle")
key(Qt.Key_Escape)
click(400, 211, Qt.RightButton)     # menú contextual de CP-102
snap("09-jira-menu-contextual")
key(Qt.Key_Escape)
ev("host.app.expanded = false")
pump(300)
print("popup colapsado con diálogos abiertos:", state())


# ---- Páginas de configuración que no usan Kirigami.FormData (adjunta, en C++)
import glob
for f in sorted(glob.glob(os.path.join(pkg, "contents/ui/config*.qml"))):
    name = os.path.basename(f)
    if "Kirigami.FormData" in open(f, encoding="utf-8").read() or "Kirigami.FormLayout" in open(f, encoding="utf-8").read():
        print("config omitida (usa Kirigami.FormData/FormLayout): " + name)
        continue
    r = ev("host.loadPage('%s')" % QUrl.fromLocalFile(f).toString())
    print("config", name, "->", r[0] if r and r[0] else "OK")
    snap("cfg-" + name.replace(".qml", ""))
ev("host.loadPage('data:,')")

import re
APP_LOG = re.compile(r"^\[(JiraStore|GhStore|NotionStore|NotionSyncStore)\]")
all_w = [m for m in messages if m[0] in ("WARNING", "CRITICAL", "FATAL")]
app_logs = [m for m in all_w if APP_LOG.match(m[3])]   # console.warn() deliberados de las stores
errs = [m for m in all_w if not APP_LOG.match(m[3])]  # avisos del motor QML / del código
print("\n== Mensajes WARNING/CRITICAL/FATAL: %d ==" % len(errs))
seen = {}
for k, f, l, m in errs:
    key = "%s %s:%s %s" % (k, f.replace(pkg, "<pkg>"), l, m.replace("file://" + pkg, "<pkg>"))
    seen[key] = seen.get(key, 0) + 1
for key, n in seen.items():
    print("%4dx %s" % (n, key))
print("\n(+ %d console.warn deliberados de las stores: credenciales faltantes, HTTP sin TLS, etc.)" % len(app_logs))
print("\n== Consola (console.log) de interés ==")
for k, f, l, m in messages:
    if "HARNESS" in m: print(m)
view.close()
shutil.rmtree(tmp, ignore_errors=True)
sys.exit(1 if errs else 0)
