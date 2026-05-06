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

## Modos

La app tiene dos modos, intercambiables desde **Configuración → General**:

| Modo  | Fuente de datos                                  | Persistencia |
|-------|--------------------------------------------------|--------------|
| ToDo  | Lista local (lo que vos escribís en el popup)    | JSON local   |
| Jira  | Issues que devuelve una JQL contra Jira Cloud    | Cache JSON + Keychain (token) |

Al cambiar a `Jira` por primera vez, la app intenta un fetch automático
si todavía no hay datos en cache. Después se respeta el intervalo de
auto-refresh configurado.

---

## Características

### Barra de menús (compacta)

- **Cuadrado blanco** con el **total de tareas pendientes** centrado
  (en modo ToDo) o el **total de issues** cacheados (en modo Jira).
- Tipografía rounded y monoespaciada para que el número quede prolijo.
- Color del cuadrado y color del número son **configurables** (por defecto
  cuadrado blanco con número negro, según pediste).
- Modo alternativo opcional: una franja de mini-cuadrados de colores como en
  KDE (un swatch por categoría con su número). En modo Jira los swatches
  reflejan las pestañas Jira configuradas.

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

### Popup en modo Jira

- Header con icono Jira, estado (cargando / actualizado hace X / error) y
  botón **refrescar**.
- **Pestañas configurables** (1 – 4): cada una filtra los issues por una
  dimensión (`statusCategory`, `status`, `issuetype`, `priority` o ninguna)
  y un valor (o lista separada por `;` para OR).
- Cada item de issue muestra:
  - **Badge de tipo** coloreado (S/B/T/E/↳ para Story / Bug / Task / Epic /
    Sub-task).
  - **Clave** (PROJ-123) en monoespaciada.
  - **Resumen**.
  - **Chip de prioridad**.
  - **Chip de estado** coloreado según `statusCategory` (gris / amarillo /
    verde para new / indeterminate / done).
  - Si es subtask, una línea adicional `↳ Parent: KEY — …`.
- **Click en un issue** → se abre la URL del issue en el navegador
  predeterminado.
- Auto-refresh configurable (0 desactiva).
- Cache local: `~/Library/Application Support/CategorizedToDo/jira-cache.json`.

### Configuración (todo configurable)

Pestaña **General**:
- **Modo**: ToDo (lista local) / Jira.
- Cantidad de categorías locales activas (1 – 4).
- Mostrar / ocultar insignias de prioridad.
- Confirmar antes de borrar permanentemente.
- Tamaño del popup (alto y ancho con sliders).

Pestaña **Jira**:
- URL del Jira (ej: `https://acme.atlassian.net`).
- Email de la cuenta.
- API token (campo enmascarado, con toggle para mostrarlo). Se guarda en
  el **Keychain** (servicio `com.categorizedtodo.app`, cuenta `jira.token`).
- JQL multi-línea, fuente monoespaciada.
- Auto-refresh en minutos (0 – 1440; 0 = sólo manual).
- Máximo de issues por consulta (10 – 200).
- Toggle para logs detallados (NSLog).
- Botón **Probar conexión** que llama `GET /rest/api/3/myself` con los
  valores actuales y muestra el `displayName` o el código de error.

Pestaña **Categorías Jira**:
- Cantidad de pestañas activas (1 – 4).
- Por cada pestaña: nombre, color, color del número, dimensión de filtro
  y valores (con placeholder de ejemplos según la dimensión elegida).

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
        ├── CategorizedToDoApp.swift                   # @main + AppDelegate
        ├── StatusBarController.swift                  # NSStatusItem + popover + ImageRenderer
        │
        ├── Models/
        │   ├── Priority.swift                         # enum XS/S/M/L/XL
        │   ├── Task.swift                             # TodoTask y Subtask (Codable)
        │   ├── TaskStore.swift                        # ObservableObject + persistencia JSON
        │   ├── JiraIssue.swift                        # modelo de issue + filtro
        │   └── JiraStore.swift                        # URLSession + cache + auto-refresh
        │
        ├── Settings/
        │   ├── AppSettings.swift                      # ObservableObject + UserDefaults
        │   └── Keychain.swift                         # wrapper SecItem* para el token
        │
        ├── Views/
        │   ├── MenuBarIcon.swift                      # cuadrado blanco con total
        │   ├── PopupView.swift                        # switch ToDo / Jira
        │   ├── CategoryView.swift                     # tareas de una categoría
        │   ├── ArchiveView.swift                      # archivadas
        │   ├── TaskRow.swift                          # delegate de tarea + subtareas
        │   ├── PriorityBadge.swift                    # chip de prioridad
        │   ├── TaskEditSheet.swift                    # diálogo nueva / editar
        │   ├── SubtaskEditSheet.swift                 # diálogo subtarea
        │   ├── ImportExportSheet.swift                # JSON export / import
        │   ├── JiraView.swift                         # popup en modo Jira
        │   ├── JiraIssueRow.swift                     # delegate de issue Jira
        │   ├── SettingsView.swift                     # tabs: Gen / Cat / Apar / Jira / CatJira
        │   ├── SettingsJiraView.swift                 # config conexión + JQL
        │   └── SettingsJiraCategoriesView.swift       # filtros por pestaña Jira
        │
        └── Resources/
            └── Info.plist                             # LSUIElement + bundle metadata
```

---

## Persistencia

- **Tareas y archivo (modo ToDo)**:
  `~/Library/Application Support/CategorizedToDo/data.json`
- **Cache de issues Jira**:
  `~/Library/Application Support/CategorizedToDo/jira-cache.json`
- **Configuración**: `UserDefaults` del bundle `com.categorizedtodo.app`
  (visible con `defaults read com.categorizedtodo.app`).
- **Token Jira**: macOS Keychain
  (`security find-generic-password -s com.categorizedtodo.app -a jira.token`).

Para empezar de cero borrá los tres:

```bash
rm -rf "$HOME/Library/Application Support/CategorizedToDo"
defaults delete com.categorizedtodo.app
security delete-generic-password -s com.categorizedtodo.app -a jira.token
```

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

## Integración con Jira

`JiraStore` (en `Models/JiraStore.swift`) es el cliente HTTP. Llama a:

```
GET {site}/rest/api/3/search?jql=…&maxResults=…&fields=summary,status,priority,issuetype,parent,updated
```

con header `Authorization: Basic base64(email:token)`. Parsea la respuesta a
una lista de `JiraIssue` (Codable) y la guarda en cache JSON.
La función `testConnection(site:email:token:completion:)` hace `GET
/rest/api/3/myself` y devuelve el `displayName` para validar credenciales.

### JQL: ejemplos útiles

| Caso | JQL |
|------|-----|
| Asignados a mí, sin completar | `assignee = currentUser() AND statusCategory != Done ORDER BY priority DESC, updated DESC` |
| Esta semana | `assignee = currentUser() AND duedate <= endOfWeek() AND statusCategory != Done` |
| Bugs sin asignar que reporté | `reporter = currentUser() AND issuetype = Bug AND assignee is EMPTY` |
| Sprint actual | `assignee = currentUser() AND sprint in openSprints() AND statusCategory != Done` |

### Filtros por pestaña

Cada pestaña Jira tiene un par `(field, value)`:

- `field` ∈ { *(sin filtro)*, `statusCategory`, `status`, `issuetype`, `priority` }
- `value` admite varios valores separados por `;` para OR

La comparación es **case-insensitive** y **exacta** contra el campo del issue.
Defaults: 3 pestañas ("Por hacer" / "En curso" / "Hechas") filtrando por
`statusCategory` con valores `new`, `indeterminate`, `done`.

### Logs

Con `Logs detallados` activado en la pestaña Jira de la configuración:

```bash
log stream --predicate 'process == "CategorizedToDo"' --info
```

Verás líneas tipo:

```
[JiraStore] fetch start: GET https://acme.atlassian.net/rest/api/3/search?jql=…
[JiraStore] fetch ok in 312ms — 17 issue(s) (total in JQL: 42)
- PROJ-12 [Story] (In Progress / indeterminate) {High} — Refactor login flow
- PROJ-13 [Bug]   (To Do / new)                 {Medium} — Crash on logout
[JiraStore] category #0 'Por hacer' [statusCategory = new]: 5 issue(s)
[JiraStore] category #1 'En curso'  [statusCategory = indeterminate]: 9 issue(s)
[JiraStore] category #2 'Hechas'    [statusCategory = done]: 3 issue(s)
```

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
| Persistencia tareas | SQLite (LocalStorage) | JSON atomic write |
| Persistencia config | KConfig (kcfg) | `UserDefaults` |
| Token Jira | KConfig en texto plano + tabla `settings` en SQLite | macOS **Keychain** (`SecItem*`) |
| Cache Jira | tabla `jira_cache` SQLite | JSON file (`jira-cache.json`) |
| Vista compacta | Mini-cuadrados por categoría en el panel | **Un solo cuadrado blanco con el total** en la menubar |
| Vista completa | Popup del plasmoide | `NSPopover` con SwiftUI |
| HTTP client Jira | `XMLHttpRequest` Qt | `URLSession` |
| ColorPicker | `QtQuick.Dialogs.ColorDialog` | `ColorPicker` SwiftUI |
| Empaquetado | `kpackagetool5` / `plasmapkg2` | `.app` bundle (build.sh) |
| Auto-arranque | Plasma maneja el panel | LaunchAgent (`install.sh --launch`) |

El esquema de datos se mantiene compatible — podés exportar JSON desde el
plasmoide KDE y pegarlo en el diálogo "Importar" de la versión macOS (y
viceversa). Las claves de configuración tienen los mismos nombres y valores
por defecto que en el `main.xml` del plasmoide.

---

## Licencia

MIT.
