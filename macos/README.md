# Categorized ToDo — macOS 26 (Tahoe)

Versión nativa en **Swift / SwiftUI** del plasmoide
[`Categorized ToDo` para KDE Plasma 5](../README.md). Vive en la **barra de
menús** (no en el Dock) y mantiene las mismas características: categorías,
prioridades, subtareas, archivado e import/export JSON.

A diferencia de la versión KDE — que muestra un cuadradito por cada
categoría — la versión macOS exhibe en la barra de menús **un único cuadrado
blanco con el número total de pendientes**. Al hacer clic se despliega el
popup completo con todas las pestañas.

---

## Capturas conceptuales

Barra de menús (lo único visible mientras la app está corriendo):

```
…  16°C  Wi-Fi  ⏵  🔊  …  ⌗  [ 7 ]  ⌚  03:17
                              ▲
                              └── click para abrir el popup
```

Popup (al hacer clic):

```
┌──────────────────────────────────────────────┐
│ ▮ Personal (2)  ▮ Trabajo (3)  ▮ Estudio (1) │
│ ▮ Otros (0)     ◻ Archivo (4)                │
├──────────────────────────────────────────────┤
│ Nueva tarea…    [M ▾] (+)        Nueva…      │
├──────────────────────────────────────────────┤
│ ▌ ☐ Comprar pan                M  ▼ ✎  □     │
│ ▌ ☐ Sacar la basura            S  ▼ ✎  □     │
│ ▌ ☑ Ir al banco                M  ▼ ✎  □     │
│ ...                                          │
├──────────────────────────────────────────────┤
│ ⚙ Configuración    Pendientes: 7      ⏻ Salir│
└──────────────────────────────────────────────┘
```

---

## Características

### Barra de menús (compacta)

- **Cuadrado blanco** con el **total de tareas pendientes** centrado.
- Tipografía rounded y monoespaciada para que el número quede prolijo.
- Color del cuadrado y color del número son **configurables** (por defecto
  cuadrado blanco con número negro, según pediste).
- Modo alternativo opcional: una franja de mini-cuadrados de colores como en
  KDE (un swatch por categoría con su número).

### Popup completo

- **Pestañas** — una por cada categoría activa (1 a 4) más la pestaña
  **Archivo**.
- En cada pestaña:
  - **Alta rápida** con `Enter` desde el campo superior.
  - Botón **Nueva…** para el diálogo completo (título + descripción +
    categoría + prioridad).
  - Lista de tareas con: casilla, título tachado si está hecha, franja del
    color de la categoría, chip de **prioridad XS / S / M / L / XL**.
  - Cada tarea se puede **expandir** (▼) para ver descripción y subtareas.
  - **Subtareas** con su propia casilla, prioridad, edición y eliminación.
  - **Archivar** (icono de caja) → la tarea pasa al archivo, donde es
    el único lugar desde el que se puede borrar permanentemente.
  - **Importar / Exportar JSON** por categoría (igual que en KDE: acepta
    el formato propio `{ schema, tasks: [...] }` o un array plano de tareas).
- Pestaña **Archivo**:
  - Lista de archivadas con fecha.
  - Restaurar al activo.
  - Borrar permanentemente (con confirmación opcional).
  - Botón para **vaciar archivo**.

### Configuración (todo configurable)

Pestaña **General**:
- Cantidad de categorías activas (1 – 4).
- Mostrar / ocultar insignias de prioridad.
- Confirmar antes de borrar permanentemente.
- Tamaño del popup (alto y ancho con sliders).

Pestaña **Categorías**:
- Nombre y color de las 4 ranuras de categoría (las que excedan la cantidad
  activa quedan ocultas; los datos no se pierden).
- `ColorPicker` nativo de macOS.

Pestaña **Apariencia**:
- **Barra de menús**:
  - Modo: cuadrado único con total / mini-swatches por categoría.
  - Color de fondo del cuadrado.
  - Color del número (negro / blanco).
- **Popup**:
  - Disposición del contador en las pestañas: a la derecha del cuadrado o
    dentro del cuadrado.
  - Mostrar categorías con cero pendientes.
  - Color del número por categoría (blanco / negro) con vista previa.

---

## Instalación

Ver [INSTALL.md](INSTALL.md) para instrucciones detalladas. Resumen:

```bash
cd macos
./install.sh                # instala en ~/Applications
./install.sh --launch       # además agrega a "Login Items" y abre la app
./install.sh --system       # instala en /Applications (pide sudo)
./install.sh --uninstall    # remueve la app y el LaunchAgent
```

Requisitos:
- **macOS 14** (Sonoma) o más nuevo. Probado en **macOS 26 (Tahoe)**.
- **Xcode 15+** o las **Command Line Tools** (`xcode-select --install`)
  con Swift ≥ 5.10.

Sin Xcode IDE: el build se hace 100% desde la terminal con
`swift build` empaquetado por `build.sh` en un `.app` bundle.

---

## Estructura del proyecto

```
macos/
├── Package.swift                           # Swift Package Manager (SPM)
├── build.sh                                # construye CategorizedToDo.app
├── install.sh                              # build + install + autostart
├── README.md                               # este archivo
├── INSTALL.md                              # guía paso a paso
└── Sources/
    └── CategorizedToDo/
        ├── CategorizedToDoApp.swift        # @main + AppDelegate
        ├── StatusBarController.swift       # NSStatusItem + popover + ImageRenderer
        │
        ├── Models/
        │   ├── Priority.swift              # enum XS/S/M/L/XL (+ color)
        │   ├── Task.swift                  # TodoTask y Subtask (Codable)
        │   └── TaskStore.swift             # ObservableObject + persistencia JSON
        │
        ├── Settings/
        │   └── AppSettings.swift           # ObservableObject + UserDefaults
        │
        ├── Views/
        │   ├── MenuBarIcon.swift           # cuadrado blanco con el total
        │   ├── PopupView.swift             # tabs + toolbar
        │   ├── CategoryView.swift          # lista de tareas de una categoría
        │   ├── ArchiveView.swift           # lista de archivadas
        │   ├── TaskRow.swift               # delegate de una tarea + subtareas
        │   ├── PriorityBadge.swift         # chip de prioridad y selector
        │   ├── TaskEditSheet.swift         # diálogo nuevo / editar
        │   ├── SubtaskEditSheet.swift      # diálogo editar subtarea
        │   ├── ImportExportSheet.swift     # diálogos export / import JSON
        │   └── SettingsView.swift          # General + Categorías + Apariencia
        │
        └── Resources/
            └── Info.plist                  # LSUIElement + bundle metadata
```

---

## Persistencia

- **Tareas y archivo**: `~/Library/Application Support/CategorizedToDo/data.json`
- **Configuración**: `UserDefaults` del bundle `com.categorizedtodo.app`
  (visible con `defaults read com.categorizedtodo.app`).

Borrar el archivo JSON deja la app virgen; borrar `UserDefaults` restaura la
configuración por defecto.

---

## Modelo de datos

Mismo esquema que en KDE — la versión macOS puede leer / escribir JSON
intercambiable con la versión KDE para una categoría individual:

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

Formato de exportación / importación JSON por categoría:

```json
{
  "schema": "categorizedtodo.v1",
  "exportedAt": 1745525858123,
  "category": 0,
  "tasks": [ /* objetos de tarea */ ]
}
```

El importador acepta tanto el sobre `{ schema, tasks }` como un array plano
de tareas. Los IDs se reasignan al importar para evitar colisiones.

---

## Cómo se dibuja la barra de menús

`StatusBarController` crea un `NSStatusItem` y, en cada cambio del store o de
las preferencias, vuelve a renderizar `MenuBarIcon` (una `View` de SwiftUI)
a un `NSImage` usando `ImageRenderer`. El `NSImage` se asigna al
`statusItem.button.image` con `isTemplate = false` para que el sistema **no**
lo tinte automáticamente y se vea el cuadrado realmente blanco.

```swift
let renderer = ImageRenderer(content: MenuBarIcon(store: store, settings: settings))
renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
statusItem.button?.image = renderer.nsImage
```

Al hacer clic se muestra un `NSPopover` cuyo `contentViewController` es un
`NSHostingController` envolviendo `PopupView`.

---

## Desarrollo

```bash
cd macos
swift build              # compila
swift run                # corre el binario directamente (aparecerá en la barra)
./build.sh --debug       # build de debug + .app bundle
./build.sh --universal   # build universal arm64 + x86_64
```

Logs:

```bash
log stream --predicate 'process == "CategorizedToDo"' --info
```

---

## Diferencias con la versión KDE

| Tema | KDE Plasma 5 | macOS Swift |
|------|--------------|-------------|
| Lenguaje | QML + JavaScript | Swift + SwiftUI |
| Framework UI | `org.kde.plasma.*`, Qt 5.15 | SwiftUI + AppKit |
| Persistencia | `Plasmoid.configuration` (KConfig) | `UserDefaults` + JSON file |
| Vista compacta | Mini-cuadrados por categoría en el panel | **Un solo cuadrado blanco con el total** en la menubar |
| Vista completa | Popup del plasmoide | `NSPopover` con `SwiftUI` |
| Edición de prioridad | `ComboBox` QML | `Picker` SwiftUI |
| ColorPicker | `QtQuick.Dialogs.ColorDialog` | `ColorPicker` SwiftUI |
| Empaquetado | `kpackagetool5` / `plasmapkg2` | `.app` bundle (build.sh) |
| Auto-arranque | Plasma maneja el panel | LaunchAgent (`install.sh --launch`) |

El esquema de datos se mantiene compatible — podés exportar JSON desde el
plasmoide KDE y pegarlo en el diálogo "Importar" de la versión macOS (y
viceversa).

---

## Licencia

MIT.
