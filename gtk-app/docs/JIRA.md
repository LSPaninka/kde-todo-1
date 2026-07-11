# Modo Jira

Vista de **solo lectura** de las incidencias de **Jira Cloud** que devuelve tu
consulta JQL (endpoint `/rest/api/3/search/jql`). Autenticación **HTTP Basic**
con correo + **token de API**.

## Configuración (Preferencias → Jira)

| Campo               | Ejemplo                                             |
|---------------------|-----------------------------------------------------|
| **Sitio**           | `https://tu-empresa.atlassian.net`                  |
| **Correo**          | `vos@tu-empresa.com`                                 |
| **Token de API**    | creá uno en <https://id.atlassian.com/manage-profile/security/api-tokens> |
| **JQL**             | `assignee = currentUser() AND statusCategory != Done ORDER BY priority DESC, updated DESC` |
| **Refresco (min)**  | `5` (0 = sólo manual)                               |
| **Máx. incidencias**| `50`                                                |

El botón **Probar** valida las credenciales contra `/rest/api/3/myself`.

## Categorías (tabs)

Hasta **10** categorías configurables. Cada una filtra por un **campo** y un
**valor**:

- **Campo**: `statusCategory` (new/indeterminate/done), `issuetype`
  (Story/Bug/Task/Sub-task…), `status` (nombre exacto del estado), `priority`
  (Highest/High/Medium/Low/Lowest), o vacío (todas).
- **Valor**: usá `;` para separar varios valores (OR). Ej.: `To Do;In Progress`.

Cada incidencia muestra su código (`KEY`), su resumen, una **barra de horas
consumidas** (si tiene estimación: `min(gastado, estimado) / estimado`, nunca
supera el 100%) y un chip con el estado. Al hacer clic se abre el **detalle**
(estado, tipo, prioridad, responsable, descripción y comentarios), con la misma
barra de horas y botones para **cambiar de estado** y abrirla en el navegador. El
texto de descripción/comentarios se aplana desde el formato ADF de Atlassian.

## Cambiar estado (transiciones)

**Clic derecho** en una tarjeta abre un menú contextual con *Ver detalle*, *Ver
en Jira* y **Cambiar estado** (las transiciones del flujo de trabajo, vía
`GET`/`POST /rest/api/3/issue/{key}/transitions`). El detalle también trae un
botón **Cambiar estado**. Al aplicar una transición se refresca la lista.

## Anexar tareas ToDo a Jira

Con **Preferencias → General → Anexar Jira** activado, cada tarea del modo ToDo
muestra un botón: un guion `–` si no está anexada, o el código de la incidencia
(`CP-123`) si lo está. Al hacer clic se abre el **selector de subtareas** de Jira
(busca en las incidencias cargadas por tu JQL) o, si ya está anexada, el detalle
de la incidencia con un botón **Cambiar subtarea**. El vínculo se guarda por tarea
(columna `jira_key`, esquema SQLite v4).

## Errores frecuentes

- **401** — email/token incorrectos o token revocado.
- **403** — el token no tiene permiso de *Browse Projects*.
- **410** — Atlassian removió el endpoint viejo; la app ya usa
  `/rest/api/3/search/jql`.
- **status 0** — URL del sitio mal escrita, TLS o red.

El log de cada fetch queda accesible desde el código (`JiraStore.last_debug_log`).
