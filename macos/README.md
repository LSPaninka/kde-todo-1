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

La app tiene cuatro modos, intercambiables desde **Configuración → General**
o haciendo **clic-derecho** (o **Ctrl-clic**) en el cuadrado de la barra de
menús:

| Modo   | Fuente de datos                                       | Persistencia                         |
|--------|-------------------------------------------------------|--------------------------------------|
| ToDo   | Lista local con hasta **7 categorías** + pestaña Global | JSON local                          |
| Jira   | Issues que devuelve una JQL contra Jira Cloud          | Cache JSON + Keychain (token)        |
| GitHub | Items de un Project v2 (GraphQL API)                   | Cache JSON + Keychain (token)        |
| Notion | Páginas vía el CLI oficial `ntn`                       | Sin cache (siempre fresco); sin token (lo maneja `ntn`) |

Al cambiar de modo por primera vez la app dispara un fetch automático si
todavía no hay datos en cache; después se respeta el intervalo de
auto-refresh configurado por modo.

**Atajo de teclado en el menú contextual**: cada modo está bindeado a `1`,
`2`, `3`, `4` cuando el menú está abierto.

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

### Popup en modo ToDo — tab Global

Además de la pestaña por cada categoría y la pestaña **Archivo**, hay una
pestaña **Global** que muestra **todas las tareas activas mezcladas**,
ordenadas por:

1. Pendientes primero (las hechas al fondo).
2. Prioridad descendente (XL > L > M > S > XS).
3. Más recientes primero.

Cada tarea conserva la franja del color de su categoría. La cabecera muestra
la leyenda de colores y el contador `pendientes / totales`.

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

### Popup en modo GitHub

- Header con icono GitHub, estado y botón **refrescar**.
- Pestañas configurables (1 – 4) que filtran los items por una dimensión:
  - `status` — valor del campo Single-select configurado (default "Status")
  - `type` — Issue / PullRequest / DraftIssue
  - `state` — OPEN / CLOSED / MERGED / DRAFT
  - `repo` — `owner/name`
  - `label` — nombres de label
- Cada item muestra: **badge de tipo** (I/P/D coloreado), número `#NN`,
  título, repo en pequeñito, hasta 6 labels de colores y el chip de status.
- **Click** en un item abre la URL del Issue / PR en el navegador.
- Auto-refresh configurable (0 = manual).
- Cache: `~/Library/Application Support/CategorizedToDo/gh-cache.json`.

### Popup en modo Notion

- Header con icono Notion, estado y botón **refrescar**.
- Barra de búsqueda con campo de query y selector **Páginas / Bases de datos**.
- Cada item muestra el icono de Notion (emoji o ícono SF de fallback),
  título, padre (`workspace` / `page_id` / `database_id`), fecha de última
  edición, y dos botones:
  - ✎ — abre un diálogo de edición que **carga el contenido en Markdown**
    vía `ntn pages get <id>`, permite editar título y cuerpo, y graba con
    `ntn api v1/pages/<id> -X PATCH` + `ntn pages update <id> --content …`.
  - ↗ — abre la página en Notion (browser o app oficial si está asociada).
- **Auth y refresh van por la CLI**: la app nunca toca el token de Notion.

### Configuración (todo configurable)

Pestaña **General**:
- **Modo**: ToDo / Jira / GitHub / Notion.
- Cantidad de categorías locales activas (**1 – 7**).
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

Pestaña **GitHub**:
- Personal Access Token (Keychain, cuenta `gh.token`).
- Tipo de owner (Usuario / Organización) y login.
- Número de project v2 (`github.com/<owner>/projects/<N>`).
- Nombre del campo de Status (default `Status`, case-insensitive).
- Incluir items cerrados / mergeados.
- Auto-refresh (0 – 1440 min), máximo de items (10 – 300).
- Logs detallados + botón **Probar token** (GET `/user`).

Pestaña **Categorías GitHub**:
- 1 – 4 pestañas con nombre, color, dimensión de filtro y valores.
- Dimensiones: `status`, `type`, `state`, `repo`, `label` o sin filtro.

Pestaña **Notion**:
- Ruta absoluta a `ntn` (opcional; default = `$PATH`, incluye
  `/opt/homebrew/bin`, `/usr/local/bin` y `~/.local/bin`).
- Query y selector Página / Base de datos.
- Máximo de resultados (10 – 200).
- Auto-refresh (0 – 1440 min).
- Logs detallados + botón **Verificar CLI** (corre `ntn --version`).

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
        ├── StatusBarController.swift                  # NSStatusItem + popover + NSMenu + ImageRenderer
        │
        ├── Models/
        │   ├── Priority.swift                         # enum XS/S/M/L/XL
        │   ├── Task.swift                             # TodoTask y Subtask
        │   ├── TaskStore.swift                        # store local (JSON)
        │   ├── JiraIssue.swift                        # modelo issue + filtro
        │   ├── JiraStore.swift                        # cliente Jira (/search/jql)
        │   ├── GhItem.swift                           # modelo GitHub Project item
        │   ├── GhStore.swift                          # cliente GraphQL GitHub
        │   ├── NotionPage.swift                       # modelo página Notion
        │   └── NotionStore.swift                      # wrapper del CLI `ntn`
        │
        ├── Settings/
        │   ├── AppSettings.swift                      # mode + todos los settings
        │   └── Keychain.swift                         # wrapper SecItem* (jira.token, gh.token)
        │
        ├── Views/
        │   ├── MenuBarIcon.swift                      # cuadrado con total (4 modos)
        │   ├── PopupView.swift                        # switch ToDo / Jira / GH / Notion
        │   ├── CategoryView.swift                     # tareas de una categoría
        │   ├── ArchiveView.swift                      # archivadas
        │   ├── GlobalView.swift                       # tab Global (todas las tareas)
        │   ├── TaskRow.swift                          # delegate tarea + subtareas
        │   ├── PriorityBadge.swift                    # chip de prioridad
        │   ├── TaskEditSheet.swift                    # diálogo nueva / editar
        │   ├── SubtaskEditSheet.swift                 # diálogo subtarea
        │   ├── ImportExportSheet.swift                # JSON export / import
        │   ├── JiraView.swift                         # popup Jira
        │   ├── JiraIssueRow.swift                     # delegate issue Jira
        │   ├── GhView.swift                           # popup GitHub
        │   ├── GhItemRow.swift                        # delegate item GitHub
        │   ├── NotionView.swift                       # popup Notion
        │   ├── NotionPageRow.swift                    # delegate página Notion
        │   ├── NotionEditSheet.swift                  # editor de página Notion
        │   ├── SettingsView.swift                     # tabs unificados
        │   ├── SettingsJiraView.swift                 # config Jira
        │   ├── SettingsJiraCategoriesView.swift       # filtros pestañas Jira
        │   ├── SettingsGhView.swift                   # config GitHub
        │   ├── SettingsGhCategoriesView.swift         # filtros pestañas GitHub
        │   └── SettingsNotionView.swift               # config Notion / CLI
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
- **Cache de items GitHub**:
  `~/Library/Application Support/CategorizedToDo/gh-cache.json`
- **Notion**: sin cache (siempre consulta a la CLI).
- **Configuración**: `UserDefaults` del bundle `com.categorizedtodo.app`
  (visible con `defaults read com.categorizedtodo.app`).
- **Tokens en Keychain**:
  - Jira: `security find-generic-password -s com.categorizedtodo.app -a jira.token`
  - GitHub: `security find-generic-password -s com.categorizedtodo.app -a gh.token`
- **Notion**: el token lo maneja `ntn` por separado (en su propio config).

Para empezar de cero borrá todo:

```bash
rm -rf "$HOME/Library/Application Support/CategorizedToDo"
defaults delete com.categorizedtodo.app
security delete-generic-password -s com.categorizedtodo.app -a jira.token 2>/dev/null
security delete-generic-password -s com.categorizedtodo.app -a gh.token   2>/dev/null
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
GET {site}/rest/api/3/search/jql?jql=…&maxResults=…&fields=summary,status,priority,issuetype,parent,updated
```

con header `Authorization: Basic base64(email:token)`. Parsea la respuesta a
una lista de `JiraIssue` (Codable) y la guarda en cache JSON.
La función `testConnection(site:email:token:completion:)` hace `GET
/rest/api/3/myself` y devuelve el `displayName` para validar credenciales.

> **Nota**: hasta mediados de 2025 el endpoint era `/rest/api/3/search`,
> pero Atlassian lo removió. La versión actual usa `/search/jql`
> (respuesta sin campo `total`, con `isLast` y `nextPageToken`; no se sigue
> la paginación, se trae sólo la primera página de `maxResults` items).

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

## Integración con GitHub Projects

`GhStore` (en `Models/GhStore.swift`) hace **una sola** consulta GraphQL
contra `POST https://api.github.com/graphql` con un Bearer token. Pide la
`projectV2(number: $number)` bajo `user(login: …)` o `organization(login: …)`
según `ghOwnerType` y trae hasta `ghMaxResults` items.

Por cada item se extraen:

- `content.__typename` → `Issue` / `PullRequest` / `DraftIssue`
- `number`, `title`, `url`, `state`, `isDraft`, `repository.nameWithOwner`
- Labels (nombre + color hex)
- `fieldValues.nodes[]` (hasta 20) — campos custom del project. Se extrae
  el valor de cada uno por nombre y se busca el que coincide
  (case-insensitive) con `ghStatusField` como "Status".

Los items se cachean en `gh-cache.json` y se filtran client-side por
pestaña (dimensiones: `status`, `type`, `state`, `repo`, `label`).

### Configurar el token

1. <https://github.com/settings/tokens> → **Generate new token (classic)**.
2. Scopes mínimos: `project`, `read:org`, `repo`.
3. Pegalo en *Configuración → GitHub*.
4. Click **Probar token** → debería decir `Autenticado como <tu-login>`.

Para fine-grained tokens: permisos de lectura en *Projects*, *Issues* y
*Pull requests* en los repos relevantes.

---

## Integración con Notion (`ntn` CLI)

`NotionStore` (en `Models/NotionStore.swift`) **no implementa HTTP** —
delega todo en el binario [`ntn`](https://npm.im/ntn). La app nunca toca
el token de Notion.

Acciones que ejecuta:

| Acción | Comando equivalente |
|--------|--------------------|
| Listar | `ntn api v1/search -X POST -d '<json>'` |
| Leer contenido | `ntn pages get <id>` |
| Update título | `ntn api v1/pages/<id> -X PATCH -d '<json>'` |
| Update contenido | `ntn pages update <id> --content '<md>'` |
| Verificar | `ntn --version` |

Todo se ejecuta vía `/bin/sh -c '…'` con el PATH augmentado con
`/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin`. Si `ntn` no está
en el PATH, configurá la ruta absoluta en *Preferencias → Notion*.

### Setup de Notion

```bash
npm install -g ntn        # o brew install ntn (si existe el formula)
ntn login                 # abre el browser de Notion para autorizar
ntn api v1/search -d '{}' # smoke test, debería devolver JSON
```

Luego cambiá el modo en la app a **Notion** y deberías ver tus páginas.

---

## Logs

Con `Logs detallados` activado en la pestaña correspondiente:

```bash
log stream --predicate 'process == "CategorizedToDo"' --info
```

Verás líneas tipo:

```
[JiraStore]  fetch start: GET https://acme.atlassian.net/rest/api/3/search/jql?jql=…
[JiraStore]  fetch ok in 312ms — 17 issue(s) (total in JQL: 17)
[GhStore]    fetch ok in 480ms — 23 item(s)
[NotionStore] $ ntn api v1/search -X POST -d '{...}'
[NotionStore] fetch ok: 7 page(s)
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
