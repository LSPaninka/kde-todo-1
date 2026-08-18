# NOTES_REL_2 — Segunda tanda de features portadas a Swift

Notas de la segunda ronda de port del plasmoide KDE `worklog-plasmoid`
(rama `claude/github-projects-integration-7Nm8D`) a la app Swift/SwiftUI
de `macos-worklog/`.

Cubre los commits upstream **0.9.0 → 0.12.0**:

| Upstream | Qué trae |
|---|---|
| `ed54f48` | Dedup Jira→Clockify por solapamiento + outlines de overlap |
| `1d9b112` | Lectura de horas en vivo al arrastrar + totales del mes en el heatmap |
| `750539f` | Google Calendar read-only (OAuth device-code) |
| `d15edab` | Hasta 3 calendarios de Google con color por calendario |
| `4b4046c` | Fix de render translúcido de los bloques de calendario |
| `0017339` | Segunda instancia de Jira: color, tabs, sync por proyecto |

---

## 1. Segunda instancia de Jira

Se puede conectar **dos cuentas / sitios de Jira a la vez**. Ambas
comparten la misma región del calendario (los bloques pueden solaparse)
y se distinguen por color.

**Configuración** — *Preferencias → Jira → Segunda instancia de Jira*:
habilitar, sitio, email y API token (Keychain, cuenta `jira2.token`),
con su propio botón **Probar Jira 2**.

**Color por instancia** — *Preferencias → Jira → Color de los bloques*:
una paleta por instancia (`jira1BlockColor` / `jira2BlockColor`). El
color se dibuja translúcido, igual que en el plasmoide.

**Modal de nuevo worklog**: cuando la instancia 2 está activa, el modal
de creación muestra **tabs "Jira 1 / Jira 2"**. Cada tab lista y
loguea contra su propio store; cambiar de tab recarga el picker y
limpia la selección (una issue de Jira 1 no existe en Jira 2). Al
**editar** un bloque, el modal queda fijo en la instancia a la que
pertenece.

**Orden del picker**: combo nuevo con `Horas ↓` (default), `Código` y
`Estado`.

**Sync Jira → Clockify por proyecto**: se sacó el selector de proyecto
del footer. Ahora cada instancia mapea a su propio proyecto de Clockify
en *Preferencias → Clockify → Sync Jira → Clockify*
(`jira1ClockifyProjectId` / `jira2ClockifyProjectId`). El chequeo de
duplicados **y** la creación quedan acotados a ese proyecto, así las dos
instancias no se contaminan entre sí. El sync corre las dos en
secuencia y reporta los totales combinados.

**Alcance**: el panel inferior (anillos / subtareas / heatmap) sigue
atado a la **primera** instancia, igual que upstream. La línea de estado
y el overlay de diagnóstico ganaron su sección de Jira 2.

### Nota de implementación (diferencia con el plasmoide)

El QML rutea con un parámetro `kind` (`"jira" | "jira2" | "clockify"`)
que se pasa a mano por cada handler. Acá el ruteo sale del **`kind` del
propio `CalendarBlock`**: `emitChange` y los helpers `routeEdit` /
`routeDuplicate` / `routeDelete` hacen `switch block.kind`. Eso permitió
colapsar los callbacks duplicados de `DayColumnView`
(`onMoveJira` / `onMoveClockify` / …) en un único set genérico
(`onMove`, `onEdit`, `onDuplicate`, `onDelete`, `onResizeTop`,
`onResizeBottom`), y agregar la instancia 2 sin sumar parámetros.

---

## 2. Google Calendar (read-only)

Los eventos del calendario se dibujan como **bloques translúcidos de
fondo**, detrás de los worklogs, para poder cargar horas "encima" de una
reunión.

- **Inmóviles y no seleccionables**: `allowsHitTesting(false)`, así el
  drag-to-create sigue funcionando sobre ellos.
- **Sólo eventos con hora**: los all-day se saltean (no mapean a un
  bloque del grid).
- **Hasta 3 calendarios**, cada uno con su color desde una paleta. El
  color siempre se pinta translúcido (fill ~0.18, borde ~0.45).
- **Sin choque de texto**: si un bloque de Jira/Clockify pisa al evento,
  el título del evento se oculta y queda sólo el bloque translúcido.
- **Toggle en el header**: un botón de calendario prende/apaga la capa
  (aparece sólo cuando ya autorizaste).

**Auth — OAuth 2.0 device-code** (client type *TV and Limited Input
devices*): no hay redirect URI ni servidor local. Desde
*Preferencias → Google*:

1. Pegás **Client ID** y **Client Secret** (creados gratis en Google
   Cloud Console, con la Calendar API habilitada).
2. **Autorizar** → se abre `google.com/device` con un código; la app
   poll-ea respetando `interval` y hace back-off si Google responde
   `slow_down`.
3. Al aprobar se guarda el **refresh token**; en runtime se canjea por
   access tokens de corta duración (se renuevan solos 60 s antes de
   vencer).
4. **Cargar mis calendarios** llena los 3 pickers.

Sólo se pide el scope `calendar.readonly` — la app nunca escribe en
Google. El Client Secret y el refresh token viven en el **Keychain**
(`google.client-secret`, `google.refresh-token`); el resto en
`UserDefaults`.

El overlay de diagnóstico ganó una sección **GOOGLE**.

---

## 3. Dedup por solapamiento + avisos visuales de overlap

**El bug**: si alargabas 10 min un worklog en Jira y volvías a
sincronizar, el chequeo viejo (misma descripción + inicio ±60 s +
duración ±60 s) fallaba por la duración y creaba una **segunda** entrada
de Clockify encima de la anterior.

**El fix**: el dedup ahora es por **solapamiento temporal**. Si ya
existe una entrada de Clockify con la misma descripción cuyo rango pisa
al del worklog de Jira, se saltea. (Y además queda acotado al proyecto
mapeado — ver punto 1.)

**Aviso visual**: los bloques que se pisan con otro **del mismo origen**
se marcan con un borde de 2 px:

- **Jira ↔ Jira** → dark orange `#FF8C00`
- **Clockify ↔ Clockify** → gold `#FFD700`

Los rangos que apenas se tocan (uno termina justo cuando arranca el
otro) **no** cuentan como solapamiento.

---

## 4. Heatmap: totales del mes

Pie nuevo abajo del heatmap con las horas consumidas del mes visible,
por origen (Clockify y Jira). Va **guardado por mes**: si llega una
respuesta tardía de otro mes, no se suma (misma protección
`clockifyKey` / `jiraKey` que ya tenían los lookups por día).

---

## Archivos nuevos

```
Sources/WorklogCalendar/Models/GoogleCalendarEvent.swift   modelos de evento + calendario
Sources/WorklogCalendar/Models/GoogleCalendarStore.swift   cliente API v3 + device flow
Sources/WorklogCalendar/Views/SettingsGoogleView.swift     pestaña Google en Preferencias
```

## Configuración nueva

| Clave | Default | Dónde se guarda |
|---|---|---|
| `jira2Enabled` | `false` | UserDefaults |
| `jira2Site` / `jira2Email` | `""` | UserDefaults |
| `jira2Token` | `""` | Keychain (`jira2.token`) |
| `jira1BlockColor` | `#9b91e6` | UserDefaults |
| `jira2BlockColor` | `#e69b91` | UserDefaults |
| `jira1ClockifyProjectId` / `jira2ClockifyProjectId` | `""` | UserDefaults |
| `googleCalEnabled` | `false` | UserDefaults |
| `googleClientId` | `""` | UserDefaults |
| `googleClientSecret` | `""` | Keychain (`google.client-secret`) |
| `googleRefreshToken` | `""` | Keychain (`google.refresh-token`) |
| `googleCalendarIds` / `googleCalendarColors` | `[]` | UserDefaults (arrays paralelos, máx. 3) |
| `googleCalendarId` | `primary` | UserDefaults (legacy, fallback) |
| `googleCalDebug` | `true` | UserDefaults |

---

## Pendiente / no portado

- **`4b4046c`** era un bug específico de QML (`Qt.color()` no existe y
  el binding roto dejaba los bloques en blanco opaco). En Swift el color
  se parsea con `Color(hex:)`, así que no aplica — pero el
  comportamiento final (fill/borde translúcidos) sí quedó replicado.
- Los **anillos de Sprint** siguen deshabilitados por default (consumo
  de CPU); sin cambios en esta tanda.
- Nada de esto se compiló acá (no hay toolchain Swift en el entorno de
  desarrollo). Falta un `./build.sh` en macOS para validar.
