# Worklog Calendar — macOS standalone (Swift)

Port a **Swift / SwiftUI** del plasmoide `worklog-plasmoid` (KDE Plasma 5),
pero rearmado como **aplicación independiente para macOS** (Dock icon,
NSWindow, ventana principal redimensionable).  Se abre como cualquier app
desde Launchpad / Finder.

Además, deja un **ícono de reloj blanco en la barra de menús superior**:
al clickearlo aparece un **popover de 1000×700** con la misma vista de
worklog (planilla + anillos + heatmap + sync) para interactuar rápido sin
abrir la ventana grande.  El popover trae un botón **"abrir aplicación"**
(ícono `macwindow`) por si querés la ventana completa — por ejemplo para
cambiar de modo.  La app sigue viva en la barra de menús aunque cierres la
ventana.

Muestra una **vista semanal Domingo→Sábado** con los **worklogs** del
usuario y soporta tres fuentes intercambiables:

| Modo | Qué muestra |
|---|---|
| **Jira** | Worklogs propios vía Jira REST API v3, columna full-width. |
| **Jira / Clockify** | Día partido al medio: Jira (lila) a la izquierda, Clockify (verde) a la derecha. Aparece un botón **"Jira → Clockify"** en el footer para mirror automático. |
| **Clockify** | Time entries de Clockify, columna full-width, teñidas con el color del proyecto. |

Permite **drag-vertical sobre el grid** para crear una entrada nueva (en
modo combinado, el lado donde apretás decide si abre el modal Jira o
Clockify) y editar/borrar haciendo click sobre un bloque existente.

> ℹ️ Esta app **no comparte código** con `macos/` (el otro port que es
> menubar widget para la lista de tareas).  Se compila e instala aparte.

---

## Requisitos

- macOS 14 (Sonoma) o superior.
- Xcode Command Line Tools (`xcode-select --install`) o un Xcode completo.
- Swift 5.9+ (lo trae cualquier Xcode 15+ / CLT moderno).

No hay dependencias de terceros.

---

## Build & install

```bash
cd macos-worklog
./build.sh            # compila release + arma ./build/WorklogCalendar.app
./install.sh          # copia a ~/Applications/WorklogCalendar.app
./install.sh --system # copia a /Applications (sudo)
./install.sh --uninstall
```

Si querés probar sin instalar:

```bash
swift run -c release
```

(el binario directo no hace `setActivationPolicy`, así que vas a perder
el Dock icon — usá el bundle `.app` para todo lo demás).

### Ícono de la app (`.icns`)

`build.sh` genera automáticamente
`Sources/WorklogCalendar/Resources/AppIcon.icns` si no existe — un reloj
blanco sobre llamas naranjas dibujado por
`tools/make-app-icon.swift`. Si querés cambiarlo:

* **Reemplazá el ícono entero**: dropeá tu propio `.icns` como
  `Sources/WorklogCalendar/Resources/AppIcon.icns` y rebuilea con
  `./build.sh`. El script lo respeta sin tocarlo.
* **Tweakeá el diseño**: editá `tools/make-app-icon.swift` (los
  parámetros `pointSize`, `color`, `at:` para reloj y llama), borrá el
  `.icns` viejo y corré `./build.sh` o directamente
  `./tools/make-app-icon.sh`.

### Modo barra de menús vs. Dock

Por defecto la app corre como **agent app**: vive sólo en la barra de
menús, sin ícono en el Dock ni en ⌘-Tab, y arranca en silencio (sólo el
ícono de reloj). Para mostrarla también en el Dock, activá
**Preferencias → General → Aplicación → "Mostrar en el Dock"**. El
cambio se aplica en caliente (no hace falta reiniciar) y se persiste.

### Cómo cerrar la app

Cerrar la ventana grande **no termina la app** — sigue viva en la barra
de menús. Para salir del todo, **click derecho** (o ctrl-click) en el
ícono de reloj de la barra superior → **Salir**. (En modo agent app
⌘-Q no alcanza porque la app no tiene foco cuando sólo está el menubar;
el menú contextual del ícono es el camino confiable.)

---

## Configuración

Al abrir por primera vez, la ventana de **Preferencias** (`⌘,` o el ícono
de engranaje en el header) tiene tres pestañas:

### General
- **Modo horario** — `9h` (09:00 – 18:00) o `24h` (00:00 – 24:00).
- **Objetivo diario** — usado para el diff en la fila de totales.
- **JQL del picker** — JQL que se usa al crear un worklog Jira nuevo
  (default: `assignee = currentUser() AND statusCategory != Done`).
- **Mostrar título de la issue** — si está apagado, los bloques Jira
  sólo muestran el `KEY`; si está prendido, muestran `KEY: título`.
- **NSLog detallado** — logs visibles en `log stream`.

### Jira
- **Sitio Jira** — ej. `https://your-company.atlassian.net`.
- **Email** — el de tu cuenta.
- **API token** — generado en `id.atlassian.com → API tokens`.
  Se guarda en el **Keychain** (`com.worklogcalendar.app` / `jira.token`).
- Botón **Probar** — hace `GET /rest/api/3/myself` con los valores
  actuales del form.

### Clockify
- **API key** — generala en Clockify → Profile → Settings → API.
  Se guarda en el **Keychain** (`com.worklogcalendar.app` /
  `clockify.api-key`).
- **Workspace ID** — 24 chars hex (ObjectId).  Si lo dejás vacío o
  ponés algo inválido, la app lo auto-resuelve desde `/user` en la
  primera sincronización.
- **User ID** — auto-resuelto / cacheado, no editable.
- **Proyecto por defecto** — pre-selecciona en el modal "nueva entrada"
  y se usa también en el sync Jira → Clockify.
- **Facturable por defecto** — flag inicial de `billable`.

---

## Sync Jira → Clockify

En modo combinado aparece un botón **"Jira → Clockify"** en el footer.
Lógica:

1. Para cada worklog de Jira en la semana visible, mira si ya existe una
   entry Clockify con la misma `description` (`KEY: título`) y un
   `start` ±1 min + duración ±1 min.
2. Si no existe, crea una nueva con:
   - `start` / `end` = los del worklog Jira
   - `description` = `<issueKey>: <issueSummary>`
   - `billable` = el default configurado
   - `projectId` = el default configurado (si lo hay)
3. Muestra `created / skipped / failed` en el banner de status.

---

## Endpoints usados

### Jira
| Acción | Endpoint |
|--------|----------|
| Usuario actual | `GET /rest/api/3/myself` |
| Worklogs de la semana | `POST /rest/api/3/search/jql?jql=…&fields=summary,worklog` |
| Crear / editar / borrar | `POST/PUT/DELETE /rest/api/3/issue/<key>/worklog[/<id>]` |

> El endpoint legacy `/rest/api/3/search` fue removido por Atlassian en
> mayo de 2025.  Esta app usa el nuevo `/rest/api/3/search/jql`.

### Clockify
Base: `https://api.clockify.me/api/v1`.  Auth: header `X-Api-Key`.

| Acción | Endpoint |
|--------|----------|
| Usuario actual + workspace | `GET /user` |
| Proyectos | `GET /workspaces/{wid}/projects?archived=false` |
| Tags | `GET /workspaces/{wid}/tags?archived=false` |
| Time entries de la semana | `GET /workspaces/{wid}/user/{uid}/time-entries?start=…&end=…` |
| Crear / editar / borrar | `POST/PUT/DELETE /workspaces/{wid}/time-entries[/{id}]` |

---

## Persistencia local

- Tokens en el **Keychain** (`com.worklogcalendar.app`).
- Preferencias en `~/Library/Preferences/com.worklogcalendar.app.plist`
  (UserDefaults).
- No se cachea respuesta de la API en disco — siempre se re-fetch.

---

## Detalle de implementación: tipos de error

Los callbacks asíncronos del proyecto **no** usan `Result<T, String>`,
porque `String` no adopta el protocolo `Error` y Swift falla a compilar
así:

```
error: type 'String' does not conform to protocol 'Error'
error: cannot infer contextual base in reference to member 'failure'
```

(Esto es exactamente lo que rompe `macos/GhStore.swift` y
`macos/JiraStore.swift` en el otro port — se va a corregir aparte.)

Esta app define en `Sources/WorklogCalendar/Models/StringError.swift`
un wrapper minimal:

```swift
struct StringError: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}
```

Y todos los callbacks toman `Result<T, StringError>`.

---

## Limitaciones

- Sólo se trabajan worklogs / time entries del usuario autenticado.
- Comentarios Jira se envían/reciben como ADF *plain text* (1 párrafo).
- Tags de Clockify: multi-select, pero no se pueden crear desde la app
  (usá la UI web de Clockify).
- Drag dentro de un único día.  Para una entrada que cruza la
  medianoche tenés que crear dos entradas.
- Sync de la semana es manual (botón ↻ en el header).

---

## Licencia

MIT.
