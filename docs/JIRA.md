# Integración con Jira

El plasmoide *Categorized ToDo* tiene dos modos:

- **ToDo** (por defecto): la lista de tareas local con categorías,
  prioridades, subtareas y archivado.
- **Jira**: vista de **solo lectura** de las incidencias que tenés
  asignadas en un **Jira Cloud** vía la REST API v3.

Este documento explica cómo configurar el modo Jira, qué hace cada
opción y consideraciones de seguridad.

---

## Qué se muestra

En modo Jira, el popup tiene **pestañas configurables** (1 a 4). Por
defecto vienen las tres clásicas:

- **Por hacer** (`statusCategory = "new"`)
- **En curso** (`statusCategory = "indeterminate"`)
- **Hechas** (`statusCategory = "done"`)

Pero podés editar cada una desde *Configurar → Categorías Jira*: nombre,
color, color de letra (blanco/negro) y filtro. El filtro acepta uno de
estos campos:

| Campo             | Coincide con              | Ejemplo de valores                  |
| ----------------- | ------------------------- | ----------------------------------- |
| `statusCategory`  | `status.statusCategory.key` | `new`, `indeterminate`, `done`     |
| `status`          | `status.name`             | `To Do`, `In Progress`, `Code Review` |
| `issuetype`       | `issuetype.name`          | `Story`, `Sub-task`, `Bug`, `Task` |
| `priority`        | `priority.name`           | `Highest`, `High`, `Medium`        |
| (sin filtro)      | todas                     | —                                   |

Para hacer **OR** entre varios valores, separalos con punto y coma:
`In Progress; Code Review`. Por ejemplo, una pestaña podría llamarse
*"Mis bugs urgentes"* con filtro `priority = Highest; High` (y el JQL
podría limitar a `issuetype = Bug` aparte).

La cantidad activa se ajusta en *Configurar → Jira → "Categorías Jira
(pestañas)"* (1 a 4). En el panel, los cuadrados respetan el color y
el color de letra elegidos (idéntico al modo ToDo).

Cada incidencia muestra:

- Insignia de **issuetype** (S = Story, T = Task, B = Bug, E = Epic,
  ↳ = Subtask, …).
- **Clave** (ej. `PROJ-123`) en monospace.
- **Resumen** (con elipsis si no entra).
- **Prioridad** (chip).
- **Estado** (chip con el color que devuelve la API de Jira).
- Si es subtask, debajo aparece la línea `↳ Parent: PARENT-12 — resumen del padre`.

Hacer clic en cualquier incidencia abre `https://<sitio>/browse/<KEY>`
en tu navegador por defecto.

---

## Cómo configurar

1. Abrí *Configurar widget* y andá a la pestaña **Jira**.
2. Completá los tres campos:
   - **Sitio Jira**: la URL raíz de tu Jira Cloud.
     Ejemplo: `https://your-company.atlassian.net`. Sin barra final.
   - **Email**: el email registrado en tu cuenta Atlassian (NO un
     usuario "humano", es el email).
   - **API token**: generá uno en
     <https://id.atlassian.com/manage-profile/security/api-tokens>.
     **No es tu password de Atlassian** — es un token específico que
     podés revocar individualmente.
3. (Opcional) Ajustá el **JQL** si querés ver más o menos incidencias.
   Default:
   ```
   assignee = currentUser() AND statusCategory != Done ORDER BY priority DESC, updated DESC
   ```
4. Pulsá **Probar** dentro de la pestaña Jira para validar las
   credenciales contra `/rest/api/3/myself`. Si funciona vas a ver tu
   `displayName`.
5. En la pestaña **General**, cambiá el **Modo** a *Jira*.
6. Aceptar / Aplicar.

El plasmoide hace una primera carga al entrar a modo Jira. Después
refresca cada `Auto-refresh (min)` minutos (default 5; poné 0 para
manual). Podés forzar un refresco con el botón ↻ del popup.

---

## JQL: ejemplos útiles

- Sólo Stories y Subtasks asignadas a vos, abiertas:
  ```
  assignee = currentUser() AND issuetype in ("Story", "Sub-task") AND statusCategory != Done ORDER BY updated DESC
  ```
- Lo que vence esta semana:
  ```
  assignee = currentUser() AND duedate <= endOfWeek() AND statusCategory != Done
  ```
- Bugs reportados por vos sin asignar:
  ```
  reporter = currentUser() AND issuetype = Bug AND assignee is EMPTY
  ```
- Sprint actual:
  ```
  assignee = currentUser() AND sprint in openSprints() AND statusCategory != Done
  ```

Tip: probá tus JQL primero en la UI de Jira (filtro avanzado), copiala
y pegala en el plasmoide.

---

## Cache local

La última respuesta exitosa se guarda en la **base SQLite**
(tabla `jira_cache`). Ver `docs/PERSISTENCE.md` para la ubicación
exacta del archivo `.sqlite`.

De esta forma, al abrir el popup mostramos las incidencias del último
fetch al instante mientras corre la siguiente actualización en
background.

Para limpiar el cache:

```bash
DIR=~/.local/share/KDE/plasmashell/QML/OfflineStorage/Databases
DB=$(grep -l 'CategorizedToDo' "$DIR"/*.ini | sed 's/\.ini$/.sqlite/')
sqlite3 "$DB" 'DELETE FROM jira_cache;'
```

---

## Vista compacta (panel)

En modo Jira, la vista compacta sigue el mismo formato que en modo
ToDo: un cuadrado coloreado por categoría con su contador. Los
colores y el color de letra (blanco/negro) son los que configuraste
en *Categorías Jira*. Las opciones de la pestaña *Apariencia*
(estilo del contador `right` / `inside`, mostrar labels, ocultar
ceros) también se aplican.

---

## Seguridad

- El **API token** se almacena en dos lugares (resilientes por
  separado):
  1. `~/.config/plasma-org.kde.plasma.desktop-appletsrc` (KConfig
     estándar de Plasma; lo escribe el diálogo *Configurar*).
  2. La base SQLite del plasmoide, en la tabla `settings` con clave
     `jira.token` (ver `docs/PERSISTENCE.md`).
  Ambos archivos tienen permisos `0600` por defecto (sólo tu usuario
  los lee), pero cualquier proceso corriendo con tu UID puede acceder.
- Limitá el alcance del token: si Atlassian Cloud te ofrece scopes,
  elegí solo los que necesites (lectura de issues alcanza).
- **Revocá** el token en
  <https://id.atlassian.com/manage-profile/security/api-tokens>
  cuando dejes de usar el plasmoide o si alguna vez creés otro.
- Las llamadas HTTP usan **HTTPS** (asumiendo que `jiraSite` empieza
  con `https://`). El plasmoide no fuerza el esquema; si ponés
  `http://` el tráfico va en claro. **No lo hagas.**
- El plasmoide nunca **escribe** en Jira: sólo `GET` a `/rest/api/3/search/jql`
  y `/rest/api/3/myself`. Aun así, si tu token tiene permisos amplios,
  un atacante con acceso a tu sesión podría usarlo.

### Server (no Cloud)

Si usás Jira Server / Data Center on-prem, la API v3 puede no estar
disponible — algunas instalaciones aún sólo tienen v2. Cambiá la URL
del JQL en el código (todavía no es configurable en la UI; PRs
bienvenidos). El esquema de auth Basic con email + password también
funciona pero es **mucho** menos seguro que API tokens; usá un
`Personal Access Token` si tu instancia los soporta.

---

## Debug

- **Ver el último error** en el popup: si una llamada falla, el
  encabezado de la pestaña Jira muestra el motivo (HTTP code +
  mensaje).

- **Logs detallados** (activados por defecto, toggle en *Configurar →
  Jira → "Loggear fetch/parse/filter…"*):

  ```bash
  journalctl --user -f _COMM=plasmashell | grep '\[JiraStore\]'
  ```

  Lo que vas a ver en cada fetch:

  ```
  [JiraStore] init: 0 cached issue(s); lastFetchedAt=never
  [JiraStore] auto-refresh scheduled every 5 min
  [JiraStore] fetch start: GET https://foo.atlassian.net/rest/api/3/search/jql
  [JiraStore]   JQL : assignee = currentUser() AND statusCategory != Done
  [JiraStore]   max : 50, fields: summary,status,priority,issuetype,parent,updated
  [JiraStore] fetch ok in 312 ms — 4 issue(s) (total in JQL: 4)
  [JiraStore]   - PROJ-101 [Story] (In Progress / indeterminate) {High} — Login screen
  [JiraStore]   - PROJ-102 [Sub-task] (To Do / new) {Medium} — Add tests  ↳ parent=PROJ-101
  [JiraStore]   - PROJ-103 [Bug] (Code Review / indeterminate) {High} — Fix typo
  [JiraStore]   - PROJ-104 [Task] (To Do / new) {Low} — Update docs
  [JiraStore] category #0 'Por hacer' [statusCategory = new]: 2 issue(s)
  [JiraStore] category #1 'En curso' [statusCategory = indeterminate]: 2 issue(s)
  [JiraStore] category #2 'Hechas' [statusCategory = done]: 0 issue(s)
  ```

  Si la JQL no devuelve nada vas a ver:

  ```
  [JiraStore] fetch ok in 245 ms — 0 issue(s) (total in JQL: 0)
  [JiraStore]   ⚠  JQL devolvió 0 resultados. Probalo en la UI de Jira para confirmar que la consulta es correcta.
  ```

  Errores de credenciales / red / JQL inválida los emite con
  `console.warn` (siempre se loggean, sin importar el toggle):

  ```
  [JiraStore] auth error: HTTP 401
  [JiraStore] HTTP 400: <mensaje del servidor>
  [JiraStore] (HTTP 400 suele indicar un JQL inválido — revisá la consulta)
  ```
- **Probar a mano** la misma llamada que hace el plasmoide:
  ```bash
  curl -s -u "you@example.com:YOUR_TOKEN" \
      -H "Accept: application/json" \
      "https://your-site.atlassian.net/rest/api/3/myself" | jq .
  ```
  Si esto falla con 401/403, el problema son las credenciales. Si
  falla con 404, el sitio o el path están mal.
- **JQL inválido**: la API responde 400 con un mensaje claro; el
  plasmoide lo muestra tal cual en el header.

---

## Limitaciones conocidas

- Solo **Jira Cloud** está testeado en serio. Server/DC puede
  funcionar pero los nombres de issuetype y los `statusCategory.key`
  pueden variar.
- No hay paginación: traemos hasta `jiraMaxResults` (default 50, máximo
  200). Si tenés más asignadas filtrá con un JQL más estricto.
- No hay edición ni transición de estados desde el plasmoide. Es
  intencionalmente solo lectura.
- El token se almacena en plano (no usamos KWallet por simplicidad y
  para no requerir un plugin C++). Si tu modelo de amenazas requiere
  más, considerá KWallet o variables de entorno.
