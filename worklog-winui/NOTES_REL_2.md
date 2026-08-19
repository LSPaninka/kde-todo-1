# Worklog Calendar (Windows / WinUI 3) — Notas de Release 2

Segunda tanda de features portadas desde el plasmoide KDE
(`worklog-plasmoid/`, rama `claude/github-projects-integration-7Nm8D`).
Cubre las versiones **0.8.2 → 0.12.0** del plasmoide.

Commits KDE portados en esta ronda:

| Commit | Versión | Qué trae |
|---|---|---|
| `ed54f48` | 0.9.0 | Dedup Jira→Clockify por solapamiento + contornos de solape |
| `1d9b112` | 0.9.1 | Rango horario en vivo al arrastrar + totales del mes en el heatmap |
| `750539f` | 0.10.0 | Integración de Google Calendar (solo lectura) |
| `d15edab` | 0.11.0 | Hasta 3 calendarios de Google con color propio |
| `4b4046c` | 0.11.1 | Fix de parseo de color (bug específico de QML — N/A acá) |
| `0017339` | 0.12.0 | Segunda instancia de Jira: color, pestañas, sync por proyecto |

---

## 1. Google Calendar (solo lectura)

Muestra tus reuniones como bloques de fondo translúcidos **detrás** de los
worklogs, para poder cargar horas "encima" de un evento sin perderlo de
vista.

**Nuevo:** `Services/GoogleCalendarStore.cs`, `Models.GoogleEvent`,
`Models.GoogleCalendarInfo`.

### Autenticación — OAuth 2.0 device flow

Se usa el tipo de cliente **"TV y dispositivos de entrada limitada"**, que
no necesita redirect URI ni servidor local (imposible en una app de
escritorio desempaquetada). El flujo, todo desde **⚙ → Google**:

1. Pegás Client ID + Client secret (cliente gratuito de Google Cloud
   Console, con la Calendar API habilitada).
2. **Autorizar…** → `POST /device/code` devuelve un código de usuario;
   la app abre `google.com/device` en el navegador y muestra el código
   en pantalla.
3. La app hace polling contra `POST /oauth2/token` respetando el
   back-off `slow_down` del servidor hasta que aprobás, y guarda el
   **refresh token**.
4. En runtime el refresh token se canjea por access tokens de vida
   corta, cacheados y renovados 60 s antes de expirar.

Único scope pedido: `calendar.readonly`. **Nunca se escribe nada** a
Google.

### Multi-calendario con color propio

- Hasta **3 calendarios** (`GoogleCalendarIds` + `GoogleCalendarColors`,
  listas paralelas). El botón **Cargar calendarios** llena los combos
  desde `/users/me/calendarList`.
- Cada calendario tiene su color hex; el bloque se dibuja siempre
  translúcido (relleno α≈0.18, borde α≈0.45) para no tapar el worklog
  que va encima.
- Los tres calendarios se piden en paralelo (`Task.WhenAll`) y se
  acumulan ordenados por hora de inicio.

### Comportamiento en el calendario

- Los bloques se insertan **primero** en cada columna y con
  `Canvas.ZIndex = -1`, así quedan detrás de todo.
- `IsHitTestVisible = false`: **inmóviles y no seleccionables**. El
  drag-to-create funciona normalmente justo encima de una reunión.
- En modo combinado ocupan **todo el ancho** de la columna (las dos
  mitades) — son contexto, no una entrada cargada.
- **Sin texto pisado**: si un worklog de Jira/Clockify se solapa en
  tiempo con el evento, el título del evento se oculta (el bloque
  translúcido queda). Es `IsGoogleCovered()`.
- Solo eventos con horario. Los de día completo se descartan porque no
  mapean a la grilla horaria.

### UI

- **Botón toggle** en el header (ícono de calendario) para prender y
  apagar la capa sin abrir configuración. Se persiste.
- El diálogo de Diagnóstico ganó una sección **GOOGLE**.

---

## 2. Segunda instancia de Jira

Dos sitios de Jira distintos en el mismo calendario, distinguidos por
color, con la posibilidad de solaparse.

### Store parametrizado

`JiraWorklogStore` ahora recibe un `instanceId` (1 o 2) y lee sus
credenciales del set correspondiente: `JiraSite/Email/Token` o
`Jira2Site/Email/Token`. Todo lo demás (fetch, create, update, delete,
subtareas, sprint) es idéntico. Los logs se etiquetan `jira` / `jira2`.

`App` construye ambas instancias siempre; la segunda solo se usa cuando
`Jira2Enabled` está activo.

### Color por instancia

`Jira1BlockColor` (`#9b91e6`) y `Jira2BlockColor` (`#26a69a`),
configurables en **⚙ → Jira**. El bloque se dibuja translúcido (α≈0.55)
con el borde en una versión oscurecida del mismo color, así dos bloques
superpuestos de instancias distintas siguen siendo legibles.

### Routing por "kind"

`BlockTag.IsJira` (bool) pasó a ser `BlockTag.Kind` (string:
`"jira"` / `"jira2"` / `"clockify"`). Todo el pipeline de gestos
—click-to-edit, drag-to-move, edge-resize, duplicar— rutea por kind a
eventos separados: `EditJira2Requested`, `MoveJira2Requested`,
`DuplicateJira2Requested`. Los handlers de `MainWindow` toman el store
como primer parámetro, así una sola implementación sirve a las dos
instancias.

### Modal de nuevo worklog

- Cuando la instancia 2 está activa y estás **creando**, aparece un
  selector **Jira 1 / Jira 2** arriba. Cambiar de instancia recarga el
  picker contra el store correspondiente.
- **Editando**, queda bloqueado a la instancia del bloque — la API de
  Jira no permite mover un worklog entre issues, mucho menos entre
  sitios.
- Nuevo **combo de orden** del picker: *Horas (desc)* (default), *Código*
  o *Estado*.

### Sync Jira → Clockify por proyecto

- Se eliminó el selector de proyecto del footer.
- Cada instancia mapea a **su propio proyecto de Clockify**
  (`Jira1ClockifyProjectId` / `Jira2ClockifyProjectId`), configurado en
  **⚙ → Clockify** con un botón **Cargar proyectos** que llena los
  combos por nombre.
- El dedup y la creación quedan **acotados a ese proyecto**, así las dos
  instancias nunca se pisan entre sí.
- El sync corre las dos instancias en secuencia y reporta los totales
  combinados.

El panel inferior (anillos / subtareas / heatmap) sigue atado a la
**primera** instancia, igual que en KDE.

---

## 3. Dedup de sync por solapamiento

El problema original: subir 10 minutos un bloque de Jira y darle
**Jira → Clockify** creaba una segunda entrada *encima* de la anterior
(quedaban una de 9:00–9:30 y otra de 9:00–9:40).

El match de "ya existe" ahora es, dentro del proyecto mapeado y con la
misma descripción, en dos pasadas:

1. **Solapamiento de rangos** — intervalos semiabiertos, así que rangos
   que apenas se tocan (uno termina justo donde arranca el otro) **no**
   cuentan como match. Esto es lo que hace que un bloque redimensionado
   actualice su gemelo en vez de duplicarlo.
2. **Mismo día calendario** — respaldo para cuando el bloque se movió lo
   suficiente como para dejar de solaparse.

Resultado por worklog:

- Match con start y duración ya coincidentes (±60 s) → **skip**.
- Match con tiempos distintos → **update in place** de la ventana
  horaria (se preservan proyecto, tags y billable).
- Sin match → **create**.

La barra de estado ahora informa las cuatro cifras: *creadas /
actualizadas / ya existían / fallaron*.

---

## 4. Aviso visual de solapes

Después de cada layout, el calendario recorre los bloques de cada día y
marca con **borde de 2 px** los pares que se solapan en tiempo:

| Fuente | Color |
|---|---|
| Jira ↔ Jira (misma instancia) | naranja oscuro `#FF8C00` |
| Clockify ↔ Clockify | dorado `#FFD700` |

Solo se marcan solapes de la **misma fuente**. Jira 1 contra Jira 2 es
esperable (comparten región), y Jira contra Clockify es la vista
combinada normal. Rangos que apenas se tocan no cuentan. Los colores
quedaron igualados a los del plasmoide para que ambas builds señalen lo
mismo de la misma forma.

---

## 5. Totales del mes en el heatmap

Pie de tabla que suma las horas consumidas del mes visible, separadas
por Clockify y Jira. Está protegido por los mismos sellos de mes
(`clockifyKey` / `jiraKey`) que usan las celdas, así una respuesta
tardía de otro mes no puede filtrarse al total.

---

## Configuración nueva

Todo vive en `%LOCALAPPDATA%\WorklogCalendar\settings.json`.

| Clave | Default | Qué hace |
|---|---|---|
| `jira2Enabled` | `false` | Habilita la segunda instancia de Jira |
| `jira2Site` / `jira2Email` / `jira2Token` | `""` | Credenciales de la instancia 2 |
| `jira1BlockColor` | `#9b91e6` | Color de bloque de la instancia 1 |
| `jira2BlockColor` | `#26a69a` | Color de bloque de la instancia 2 |
| `jira1ClockifyProjectId` | `""` | Proyecto Clockify destino del sync de la instancia 1 |
| `jira2ClockifyProjectId` | `""` | Proyecto Clockify destino del sync de la instancia 2 |
| `googleCalEnabled` | `false` | Muestra la capa de Google Calendar |
| `googleClientId` / `googleClientSecret` | `""` | Cliente OAuth (device flow) |
| `googleRefreshToken` | `""` | Se completa solo tras autorizar |
| `googleCalendarIds` | `[]` | Hasta 3 ids de calendario |
| `googleCalendarColors` | `[]` | Colores, en paralelo a los ids |
| `googleCalDebug` | `true` | Loguea cada request de Google a `worklog.log` |

---

## Endpoints nuevos

### Google Calendar API v3

| Acción | Endpoint |
|---|---|
| Iniciar autorización | `POST https://oauth2.googleapis.com/device/code` |
| Polling / refresh de token | `POST https://oauth2.googleapis.com/token` |
| Listar calendarios | `GET /calendar/v3/users/me/calendarList` |
| Eventos de la semana | `GET /calendar/v3/calendars/{id}/events?timeMin=…&timeMax=…&singleEvents=true&orderBy=startTime` |

La instancia 2 de Jira usa exactamente los mismos endpoints que la 1,
contra otro `site`.

---

## Diferencias intencionales con el plasmoide

- **Dedup más agresivo**: KDE, ante un match por solapamiento, saltea y
  deja la entrada de Clockify desalineada. Acá se **actualiza in place**
  para que Clockify quede reflejando lo que dice Jira, que era el pedido
  original. Se agregó además la pasada de "mismo día" que KDE no tiene.
- **Selector de instancia**: KDE usa pestañas QML; acá son dos
  `ToggleButton` mutuamente excluyentes (mismo comportamiento, sin
  depender de controles nuevos del SDK).
- **Colores por combo de paleta**: KDE tiene un popup de paleta; acá el
  color se escribe como hex en un `TextBox`, con validación y fallback
  si el texto no es un `#rrggbb` válido.
- **Fix `4b4046c` no aplica**: era el bug de `Qt.color()` que no existe
  en QML. En C# el parseo de hex ya era manual desde el primer port.

---

## Cómo probarlo

```powershell
git pull
.\install.ps1
```

Después, en la app:

1. **⚙ → Jira** → activá "Habilitar la segunda instancia", cargá site,
   email y token, y elegí los dos colores.
2. **⚙ → Clockify** → **Cargar proyectos** y mapeá un proyecto a cada
   instancia.
3. **⚙ → Google** → pegá Client ID/secret, **Autorizar…**, aprobá en el
   navegador, **Cargar calendarios**, elegí hasta 3 y sus colores.
4. Cerrá el diálogo y usá el **toggle de calendario** del header para
   prender y apagar la capa de Google.

Si algo falla, el log completo está en **ⓘ → Abrir worklog.log**
(las requests de Google salen con el tag `google`, las de la segunda
instancia con `jira2`).
