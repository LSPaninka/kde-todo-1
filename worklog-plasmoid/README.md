# Jira / Clockify Worklog Calendar — KDE Plasma 5 plasmoid

Plasmoide independiente que muestra **una vista semanal** (Domingo a Sábado)
con los **worklogs** del usuario, permitiendo trabajar con tres fuentes
intercambiables:

- **Jira** (default): worklogs vía la REST API v3.
- **Clockify**: time entries vía la API v1 con `X-Api-Key`.
- **Jira / Clockify** (combinado): cada día se parte en dos columnas
  verticales — Jira a la izquierda (lila) y Clockify a la derecha
  (verde claro / color del proyecto en modo Clockify puro). Útil para
  ver dónde te falta cargar y para mirror Jira → Clockify con un click.

Permite **arrastrar sobre el grid** para crear una entrada y abre el modal
correspondiente (Jira: issue picker + comment; Clockify: project + tags +
billable + description). Las credenciales de Jira se comparten con el
plasmoide *Categorized ToDo* (mismo `categorizedtodorc`).

Compatible con Kubuntu 24.04 / Plasma 5.27 / Qt 5.15. QML puro, sin
librerías nativas.

---

## Modos

Cambiá entre fuentes desde el menú **hamburguesa** del footer (a la
izquierda de **Configurar…**):

| Modo | Qué muestra |
|---|---|
| **Jira** | Solo worklogs de Jira en la columna del día (full width). |
| **Jira / Clockify** | Día partido al medio: Jira (lila) a la izquierda, Clockify (verde claro) a la derecha. Aparece un botón extra **"Jira → Clockify"** en el footer para copiar worklogs de Jira como entradas Clockify con `description = CP-XXX: título`. |
| **Clockify** | Solo entradas Clockify, full width, coloreadas con el color del proyecto (si el proyecto tiene uno en Clockify). |

El **botón pin** en la esquina superior derecha del header mantiene el
popup abierto hasta que se vuelva a tocar (toggle de
`plasmoid.hideOnWindowDeactivate`).

---

## Vista compacta

Un solo ícono de calendario en el panel. Clic abre el popup.

---

## Configuración

### Pestaña *General*

| Campo | Default | Notas |
|---|---|---|
| Modo de vista | `9h` | `9h` = 09:00–18:00 ; `24h` = 00:00–24:00 |
| Ancho/alto popup | 1100 × 650 | en píxeles |
| Objetivo diario (h) | 8 | usado para el diff de la fila de totales |
| JQL del picker | `assignee = currentUser() AND statusCategory != Done` | para el modal de crear worklog de Jira |
| Máx. issues picker | 50 | |
| Mostrar título Jira | off | si está on, los bloques Jira muestran `CP-XXXX: título`; off muestra solo `CP-XXXX` |
| Logs | on | activa `console.log` para los stores Jira y Clockify |

### Pestaña *Jira*

Site URL + email + API token + botón de prueba. **Compartido** con el
plasmoide *Categorized ToDo* via `~/.config/categorizedtodorc`.

### Pestaña *Clockify*

| Campo | Notas |
|---|---|
| API key | Generala en Clockify → Perfil → Settings → API. Botón **Probar** dispara `GET /user` para validar. |
| Workspace ID | Opcional. Vacío = se autoresuelve a tu workspace por defecto en la primera sync. |
| Proyecto por defecto (ID) | Usado por el modal cuando creás una entrada nueva, y por el sync Jira → Clockify. Vacío = sin proyecto. |
| Billable por defecto | Marca como facturable las nuevas entradas. |

---

## Endpoints usados

### Jira

| Acción | Endpoint |
|--------|----------|
| Usuario actual | `GET /rest/api/3/myself` |
| Worklogs de la semana | `POST /rest/api/3/search/jql` con `worklogAuthor = currentUser() AND worklogDate >= …` + `fields=summary,worklog` |
| Crear / editar / borrar | `POST/PUT/DELETE /rest/api/3/issue/<key>/worklog[/<id>]` |

### Clockify

Auth: header `X-Api-Key`. Base: `https://api.clockify.me/api/v1`.

| Acción | Endpoint |
|--------|----------|
| Usuario actual + workspace | `GET /user` |
| Proyectos (con colores) | `GET /workspaces/{wid}/projects?archived=false` |
| Tags | `GET /workspaces/{wid}/tags?archived=false` |
| Time entries de la semana | `GET /workspaces/{wid}/user/{uid}/time-entries?start=…&end=…` |
| Crear | `POST /workspaces/{wid}/time-entries` |
| Editar | `PUT /workspaces/{wid}/time-entries/{id}` |
| Borrar | `DELETE /workspaces/{wid}/time-entries/{id}` |

Los **colores por proyecto** se leen desde el campo `color` de cada
proyecto y se usan como tinte del bloque en modo Clockify puro. En modo
combinado todos los bloques Clockify son verde claro para distinguirlos
visualmente de Jira.

---

## Sync Jira → Clockify

En modo combinado aparece un botón **"Jira → Clockify"** en el footer.
Lógica:

1. Para cada worklog de Jira en la semana visible, mira si ya existe una
   entrada Clockify con la misma `description` y un `start` ±1 min.
2. Si no existe, crea una nueva con:
   - `start`/`end` = los del worklog Jira
   - `description` = `<issueKey>: <issueSummary>` (ej. `CP-1234: Tarea`)
   - `billable` = el default configurado
   - `projectId` = el default configurado (si lo hay)
3. Muestra `created / skipped / failed` en la barra de estado.

Después del sync se refresca automáticamente la semana.

---

## Drag-to-create

- En modos puros (Jira o Clockify): drag vertical → modal de la fuente
  correspondiente.
- En modo combinado: la **mitad izquierda** del día abre el modal de
  Jira, la **mitad derecha** abre el modal de Clockify. El rectángulo
  semi-transparente del drag se ajusta al ancho de la mitad presionada.

Cada paso del drag snapea a slots de 30 min.

---

## Instalación

```bash
cd worklog-plasmoid
./install.sh             # instala / upgradea
./install.sh --dev       # symlink para desarrollo
./install.sh --uninstall # remover

# Recargar Plasma:
kquitapp5 plasmashell && kstart5 plasmashell
```

---

## Limitaciones conocidas

- Solo se trabajan worklogs/entries propios del usuario autenticado.
- Comentarios Jira se envían/reciben como ADF *plain text* (1 párrafo).
- Tags de Clockify: multi-select, pero no se pueden crear desde el
  plasmoide (usá la UI de Clockify para eso).
- Drag dentro de un único día. Span multi-día → crear dos entradas.
- Sync de la semana es **manual** (botón ↻).
- En modo Clockify puro, los bloques se colorean con el color del
  proyecto solo si el proyecto tiene uno seteado en Clockify; si no, se
  usa un verde claro por defecto.

---

## Debugging

Toggle de logs en cada pestaña (Jira / Clockify). El botón **ⓘ** del
popup muestra el log combinado de los dos stores incluso si los toggles
de consola están off.

Para mirar por journalctl:

```bash
journalctl --user -f _COMM=plasmashell | grep -E '\[JiraWorklog\]|\[Clockify\]'
```

---

## Licencia

MIT.
