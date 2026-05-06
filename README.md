# Categorized ToDo — KDE Plasma 5 plasmoid

Un plasmoide (gadget de escritorio y de panel) para **Kubuntu 24.04**
(**KDE Plasma 5.27** + **Qt 5.15**) que implementa una lista de tareas con
categorías, prioridades, subtareas y archivo.

Todo el código es QML puro. **No se usan librerías externas**: sólo los módulos
que vienen con Plasma 5 y Qt 5.15 (`org.kde.plasma.*`, `org.kde.kirigami`,
`QtQuick`, `QtQuick.Controls 2`, `QtQuick.Dialogs`).

---

## Modos

El plasmoide soporta dos modos (configurable en la pestaña *General*
del diálogo de configuración):

- **ToDo** (por defecto): la lista local con categorías, prioridades,
  subtareas, archivado, export/import JSON. Persiste a archivos JSON
  bajo `~/.local/share/categorizedtodo/`.
- **Jira**: vista de **solo lectura** de las incidencias asignadas a
  tu usuario en Jira Cloud. Configurás sitio + email + API token y
  listo. Detalles, JQL de ejemplo y notas de seguridad en
  [`docs/JIRA.md`](docs/JIRA.md).

---

## Características

### Vista completa (popup)

- **Pestañas por categoría** (hasta 4, configurable de 1 a 4). Cada pestaña
  tiene el color de la categoría, su nombre y un contador de tareas pendientes.
- **Alta rápida** de tareas por categoría (título + prioridad).
- **Botón “Nueva…”** para el diálogo completo con descripción, categoría
  y prioridad.
- Cada tarea muestra:
  - Casilla para marcarla como hecha.
  - Título (con tachado si está hecha).
  - Franja de color de la categoría a la izquierda.
  - Chip de prioridad **XS / S / M / L / XL** (coloreado según nivel).
  - Botón para **expandir** (ver descripción y subtareas).
  - Botón **Editar** (título, descripción, categoría, prioridad).
  - Botón **Archivar** (la manda al módulo de archivado; sólo ahí se
    puede borrar).
- **Subtareas** dentro de cada tarea: cada una con su propia casilla,
  prioridad, botón para editar y botón para eliminar. También una fila inline
  de “Agregar subtarea”.
- **Exportar / Importar JSON por categoría**:
  - Botón **Exportar** (icono de exportación) en la cabecera de cada
    pestaña: abre un diálogo con todo el JSON de esa categoría
    (incluyendo subtareas) listo para copiar al portapapeles.
  - Botón **Importar** (icono de importación) en la cabecera de cada
    pestaña: abre un diálogo donde se pega un JSON y se agregan las
    tareas a esa categoría. Soporta tanto el formato exportado
    (`{ schema, tasks: [...] }`) como un array plano de tareas.
- Pestaña **Archivo**:
  - Muestra las tareas archivadas con fecha y la categoría original.
  - Botón para **restaurar** a la lista activa.
  - Botón para **borrar permanentemente** (con confirmación opcional).
  - Botón para **vaciar archivo**.

### Vista compacta (panel / systray)

Diseñada para ir en una barra de tareas. Muestra, **en horizontal**, una
casilla con el color de cada categoría seguida del número de tareas
pendientes de esa categoría. Por ejemplo:

```
[verde] 1   [amarillo] 3   [azul] 5   [rojo] 0
```

Opciones (pestaña *Apariencia* de la configuración):
- **Disposición del contador**: a la derecha del cuadrado (predeterminado)
  o **dentro** del cuadrado (en ese caso el cuadrado es más grande y el
  número se centra dentro).
- **Color del número por categoría**: blanco o negro, elegido
  individualmente para que contraste con cada color de categoría.
- Mostrar u ocultar el nombre al lado del contador.
- Ocultar las categorías con 0 pendientes.

Clic abre el popup.

### Configuración (todo configurable)

Pestaña **General**:
- Cantidad de categorías activas (1 – 4).
- Mostrar / ocultar las insignias de prioridad.
- Confirmar antes de borrar permanentemente.
- Tamaño del popup (alto y ancho).

Pestaña **Categorías**:
- Nombre y color de las 4 ranuras de categoría (las que excedan la cantidad
  activa simplemente no se muestran; los datos no se pierden).
- Selector de color nativo Qt (`QtQuick.Dialogs.ColorDialog`).

Pestaña **Apariencia** (controla la vista compacta):
- Disposición del contador: a la derecha o dentro del cuadrado.
- Color del número (blanco / negro) por categoría con vista previa.
- Mostrar nombre al lado de cada contador.
- Mostrar categorías con cero pendientes.

---

## Instalación

Requisitos: Kubuntu 24.04 con Plasma 5.27 y Qt 5.15 (vienen por defecto).

### Dependencias QML

El plasmoide depende de tres módulos QML que **a veces no se instalan
con Plasma por defecto**:

| Módulo QML                 | Paquete (Debian/Ubuntu)              |
| -------------------------- | ------------------------------------ |
| `QtQuick.LocalStorage`     | `qml-module-qtquick-localstorage`    |
| `QtQuick.Controls 2`       | `qml-module-qtquick-controls2`       |
| `Qt.labs.platform`         | `qml-module-qt-labs-platform`        |

El `install.sh` los detecta automáticamente y ofrece instalarlos vía
`sudo apt install`. Si preferís hacerlo a mano:

```bash
sudo apt install qml-module-qtquick-localstorage \
                 qml-module-qtquick-controls2 \
                 qml-module-qt-labs-platform
```

En Fedora: `sudo dnf install qt5-qtdeclarative qt5-qtquickcontrols2`
En Arch: `sudo pacman -S qt5-declarative qt5-quickcontrols2`

> **Nota**: si al cargar el plasmoide ves el error
> `module "QtQuick.LocalStorage" is not installed`, instalá el paquete
> de arriba y reiniciá plasmashell con
> `kquitapp5 plasmashell && kstart5 plasmashell`.

### Instalar el plasmoide

```bash
# Desde el clon del repo
./install.sh            # instala para el usuario actual (chequea deps)
./install.sh --dev      # en su lugar, hace un symlink (modo desarrollo)
./install.sh --no-deps  # salta el chequeo de dependencias
./install.sh --uninstall
```

El script usa `kpackagetool5` (o `plasmapkg2` si está presente). Ambos ya
vienen con la sesión Plasma.

Una vez instalado, agrega el widget con:

1. Clic derecho en el escritorio o en el panel → **Agregar widgets…**.
2. Buscá **“ToDo”** o **“Categorized ToDo”**.
3. Arrastralo al escritorio (vista completa) o al panel (vista compacta).

Si el widget no aparece en el buscador, reiniciá Plasma:
```bash
kquitapp5 plasmashell && kstart5 plasmashell
```

---

## Estructura del paquete

```
package/
├── metadata.desktop              # metadatos del plasmoide (id, autor, …)
├── contents/
│   ├── config/
│   │   ├── main.xml              # esquema KCfg: opciones + datos serializados
│   │   └── config.qml            # define las pestañas del diálogo de config
│   └── ui/
│       ├── main.qml              # root: dispatcher por modo
│       ├── CompactRepresentation.qml   # vista para el panel (todo + jira)
│       ├── FullRepresentation.qml      # popup dispatcher por modo
│       ├── TodoView.qml          # popup contents en modo ToDo
│       ├── JiraView.qml          # popup contents en modo Jira
│       ├── JiraIssueItem.qml     # delegate de una incidencia
│       ├── SwatchBadge.qml       # entrada del panel reusable
│       ├── CategoryView.qml      # lista de tareas de una categoría
│       ├── ArchiveView.qml       # lista de archivadas
│       ├── TaskItem.qml          # delegate de una tarea (con subtareas)
│       ├── PriorityBadge.qml     # chip XS/S/M/L/XL
│       ├── PrioritySelector.qml  # combo XS/S/M/L/XL
│       ├── TabCountBadge.qml     # contador circular dentro de las pestañas
│       ├── TaskEditDialog.qml    # diálogo nuevo/editar tarea
│       ├── SubtaskEditDialog.qml # diálogo editar subtarea
│       ├── ExportDialog.qml      # diálogo de exportación JSON por categoría
│       ├── ImportDialog.qml      # diálogo de importación JSON por categoría
│       ├── CategoryHelper.qml    # helper: lee nombres/colores desde config
│       ├── Database.qml          # wrapper SQLite (QtQuick.LocalStorage)
│       ├── TaskStore.qml         # modelo en memoria + persistencia (SQLite)
│       ├── JiraStore.qml         # cliente REST de Jira + cache (SQLite)
│       ├── configGeneral.qml     # pestaña General + selector de modo
│       ├── configCategories.qml  # pestaña Categorías ToDo
│       ├── configAppearance.qml  # pestaña Apariencia
│       ├── configJira.qml        # pestaña Jira (sitio, email, token, JQL)
│       └── configJiraCategories.qml # pestaña Categorías Jira (filtros + colores)
├── install.sh
├── docs/
│   ├── PERSISTENCE.md            # cómo persiste el modo ToDo
│   └── JIRA.md                   # cómo configurar el modo Jira
└── README.md
```

---

## Modelo de datos

Las tareas, subtareas, cache de Jira y credenciales de Jira se guardan
en una base **SQLite** vía `QtQuick.LocalStorage 2.0` (incluido en
Qt 5, no es una librería externa). El archivo `.sqlite` vive bajo
`~/.local/share/KDE/plasmashell/QML/OfflineStorage/Databases/`. Cada
mutación es una transacción atómica con `fsync()`, así que sobrevive a
reinicios y crashes de plasmashell.

La configuración del widget (modo, categorías, colores, opciones del
panel) sigue en `Plasmoid.configuration`. Las **credenciales de Jira**
se persisten en los dos lados a la vez: si Plasma las pierde, el
plasmoide las recupera del SQLite en el siguiente arranque. Los
detalles —esquema, ubicación exacta, backup, debugging— están en
[`docs/PERSISTENCE.md`](docs/PERSISTENCE.md).

Forma de cada tarea:

```json
{
    "id": 12,
    "title": "Comprar pan",
    "description": "Panadería de la esquina",
    "category": 0,
    "priority": "M",
    "done": false,
    "createdAt": 1730000000000,
    "archivedAt": 0,
    "subtasks": [
        { "id": 13, "title": "Pedir integral", "priority": "S", "done": false }
    ]
}
```

Dos arrays independientes: `tasksJson` (activas) y `archivedJson`
(archivadas). Cuando se **archiva** una tarea se mueve de uno a otro; cuando
se **restaura** se hace el movimiento inverso; cuando se **borra permanentemente**
se remueve del archivo. De esta forma, **una tarea sólo puede eliminarse
desde el archivo**, que es lo que pedimos.

---

## Flujo de uso

1. Crear una tarea: escribí el título en el campo superior de una pestaña y
   Enter, o clic en **“Nueva…”** para abrir el diálogo con descripción.
2. Expandí la tarea (botón ▼) para agregar subtareas y verlas.
3. Marcá la tarea (o subtarea) como completada con la casilla.
4. Cuando termines la tarea, clic en el botón de **archivar** (icono de caja).
   La tarea deja de aparecer en la pestaña de su categoría y pasa a
   **Archivo**.
5. Desde la pestaña **Archivo** podés:
   - Restaurarla a la lista activa.
   - Eliminarla permanentemente.
6. La vista compacta del panel refleja en tiempo real cuántas tareas
   pendientes hay por categoría.

---

## Desarrollo

Para iterar sin desinstalar/reinstalar cada vez:

```bash
./install.sh --dev            # hace un symlink al paquete
kquitapp5 plasmashell && kstart5 plasmashell
```

A partir de ahí cualquier cambio en `package/contents/ui/*.qml` se aplica
al recargar el plasmoide (o reiniciar plasmashell).

Logs de errores QML:
```bash
journalctl --user -f -u plasma-plasmashell.service
# o bien:
plasmashell --replace 2>&1 | grep -i -E 'qml|warning|error'
```

---

## Licencia

MIT. Ver cabecera en `metadata.desktop`.
