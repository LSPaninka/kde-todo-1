# Worklog Calendar — Python / PyGObject (GTK 4 + libadwaita)

Aplicación de escritorio para **Ubuntu 24.04 (GNOME)** que muestra una **vista
semanal** (Domingo a Sábado) con tus **worklogs** de **Jira** y **Clockify**.
Es la versión en **Python (PyGObject)** del mismo programa que también existe
escrito en Vala (`worklog-gtk/`) y, originalmente, como plasmoide de KDE.

Funciona de dos maneras a la vez:

1. **Aplicación completa** — una ventana de escritorio redimensionable
   (`Worklog Calendar`) que abrís desde el menú de aplicaciones o el dock.
2. **Ventanita flotante** — un **reloj blanco** en la barra superior; al
   hacerle clic se abre una ventana chica de **1000 × 700 px** con toda la
   pantalla de Jira/Clockify a escala (planilla, anillos, heatmap, sincronizar
   y un botón para saltar a la app completa).

La app **sigue corriendo en segundo plano** cuando cerrás cualquiera de las dos
ventanas. Para **salir de verdad** hacés **clic derecho en el reloj de la barra
superior → Salir** (o `Ctrl+Q` / el menú hamburguesa de la app → *Salir*).

---

## Qué incluye

| Componente | Descripción |
|---|---|
| **La planilla** | Grilla semanal de 30 min por fila. Modo **9h** (09:00–18:00) o **24h**. Arrastrá para crear, clic para editar, arrastrá un bloque para moverlo, los bordes para redimensionar. Botón derecho → *Duplicar / Editar*. |
| **Tres fuentes** | **Jira** (lila), **Clockify** (verde) o **Jira / Clockify** combinado (día partido al medio). |
| **Los anillos** | Gauges de **Sprint** (% transcurrido) y **Horas** (% cargado), con animación de llenado. |
| **El heatmap** | Tabla mensual de horas por día (Clockify + Jira). Clic en un día salta a esa semana. |
| **Tabla de subtareas** | Tus subtareas (JQL configurable) con estado, horas restantes y menú de transiciones. |
| **Sincronizar** | ↻ refresca la semana; en modo combinado, **Jira → Clockify** replica los worklogs. |
| **Configurable** | Preferencias completas guardadas en **GSettings**. |

---

## Instalación

### Dependencias (Ubuntu 24.04)

```bash
sudo apt install meson ninja-build \
  python3-gi python3-gi-cairo gir1.2-gtk-4.0 gir1.2-adw-1 \
  gnome-shell-extension-appindicator
```

(o `./install.sh --deps`).

> **No hay dependencias externas de Python**: el cliente HTTP usa `urllib` y el
> parseo JSON usa `json`, ambos de la **biblioteca estándar**. Sólo se necesita
> PyGObject (`python3-gi`) y los *typelibs* de GTK4/Adwaita.
>
> El reloj de la barra usa **StatusNotifierItem**; en GNOME requiere la
> extensión **Ubuntu AppIndicators** (ya viene en Ubuntu, activala con
> *Extensiones*).

### Compilar e instalar

```bash
cd worklog-python
./install.sh            # instala en ~/.local (sin root)
./install.sh --run      # instala y lanza
./install.sh --system   # instala en /usr (con sudo)
./install.sh --uninstall
```

O a mano con Meson:

```bash
meson setup build --prefix ~/.local
meson install -C build
```

### Correr sin instalar (desarrollo)

```bash
cd worklog-python
mkdir -p _schemas && cp data/*.gschema.xml _schemas/ && glib-compile-schemas _schemas/
GSETTINGS_SCHEMA_DIR=$PWD/_schemas python3 -m worklogcalendar.main
```

> En Ubuntu 24.04 `python3` es 3.12 e incluye PyGObject tras instalar
> `python3-gi`. Si tu `python3` por defecto es otro (pyenv/conda), usá
> `/usr/bin/python3`.

---

## Primer uso

1. Abrí la app → menú hamburguesa → **Preferencias** (o el ⚙ del pie).
2. Pestaña **Jira**: *Site URL*, *Email* y *API token*
   ([generá uno acá](https://id.atlassian.com/manage-profile/security/api-tokens)).
3. Pestaña **Clockify** (opcional): pegá tu *API key*.
4. Cerrá Preferencias y tocá ↻.

Más detalle en [`docs/`](docs/): [CONFIGURACION](docs/CONFIGURACION.md),
[JIRA](docs/JIRA.md), [CLOCKIFY](docs/CLOCKIFY.md).

---

## Segundo plano y "Salir"

- Cerrar la ventana **la oculta**; la app sigue viva en la barra superior
  (preferencia *Seguir en segundo plano al cerrar*, por defecto **on**).
- **Clic en el reloj** → ventanita flotante.
- **Clic derecho en el reloj** → *Mostrar reloj* / *Abrir aplicación* / **Salir**.
- *Salir* (o `Ctrl+Q`) cierra el proceso de verdad.

---

## Arquitectura

```
worklogcalendar/
  main.py            Punto de entrada
  application.py     Adw.Application: ventanas, stores y reloj de la barra
  config.py          Wrapper sobre GSettings
  http.py            HTTP async (urllib en un hilo + GLib.idle_add)
  jira_store.py      Jira Cloud REST v3
  clockify_store.py  Clockify REST v1
  models.py          dataclasses de datos
  util.py            Helpers de fecha / JSON / color
  calendar_grid.py   La planilla (Cairo + gestos)
  ring_gauge.py      Anillo donut animado
  sprint_gauges.py   Anillos Sprint + Horas
  month_heatmap.py   Heatmap mensual
  subtask_table.py   Tabla de subtareas
  jira_edit_dialog.py / clockify_edit_dialog.py  Modales
  worklog_view.py    Compositor de toda la UI (lo usan ambas ventanas)
  windows.py         MainWindow + PopupWindow
  preferences.py     Adw.PreferencesWindow
  tray.py            StatusNotifierItem + dbusmenu (GDBus puro)
data/                gschema, .desktop, iconos (reloj blanco)
```

Cada *store* es `GObject.GObject` y emite la señal `changed`; la UI se
re-renderiza al recibirla. Las peticiones de red corren en un hilo y el
resultado vuelve al hilo principal con `GLib.idle_add`, así la UI nunca se
bloquea.

---

## Diferencias con la versión en Vala

Misma funcionalidad y misma UI. La versión Vala compila a un binario nativo;
esta es Python puro (sin paso de compilación), un poco más fácil de hackear y
sin dependencias de C más allá de PyGObject. Usan **esquemas de GSettings
distintos** (`...WorklogCalendarPy`), así que podés tener ambas instaladas sin
que se pisen la configuración.

---

## Licencia

MIT — ver [LICENSE](LICENSE).
