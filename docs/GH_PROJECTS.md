# Modo GitHub Projects

Vista de **solo lectura** de los ítems (Issues, Pull Requests, Draft
Issues) de un **Project V2** de GitHub.

Igual que el modo Jira:

- Las credenciales (token + owner) se mirran en SQLite, así un reset de
  KConfig no las pierde.
- El último resultado exitoso se cachea en `gh_cache` (mismo
  `Database.qml`); el popup se ve poblado de entrada en el siguiente
  arranque mientras se hace fetch en background.
- Hasta 4 **categorías** configurables (pestañas en el popup, cuadrados
  en el panel). Cada categoría filtra los ítems por un campo del
  proyecto y un valor (o lista de valores, separados por `;`).

---

## Pasos rápidos

1. Generá un Personal Access Token en
   <https://github.com/settings/tokens>:
   - **Classic**: marcá los scopes `project`, `read:org`, `repo`.
   - **Fine-grained** (beta): permitile leer **Projects** (Organization
     permissions → Projects: Read) y, para que se vean los títulos de
     issues / PRs, también **Issues / Pull requests: Read** de los repos
     que querés ver.
2. Anotá tu **owner** (login del usuario u organización dueña del
   proyecto) y el **número de proyecto** (lo que aparece en
   `.../projects/<N>` en la URL).
3. En el plasmoide → **Configurar… → GitHub**:
   - Pegá el token.
   - Owner: `tu-usuario` o `tu-org`.
   - Tipo: Usuario u Organización.
   - Número de proyecto: `<N>`.
   - Opcional: cambiá el nombre del campo *Status* si tu proyecto usa
     otro (por defecto `Status`).
   - **Probar token** para validar autenticación.
4. Cambiá el modo a **GitHub Projects** en la pestaña General (o usá
   la rueda del mouse sobre la vista compacta del panel).

---

## Categorías GH

Pestaña **Categorías GH** de la configuración. Para cada slot:

- **Nombre** y **color** (con `QtQuick.Dialogs.ColorDialog` nativo).
- **Color del texto** del contador del panel (blanco / negro).
- **Filtro**: campo + valor.

Campos disponibles:

| Campo    | Qué matchea                                                          |
| -------- | -------------------------------------------------------------------- |
| `status` | El valor del campo single-select **Status** del proyecto.            |
| `type`   | `Issue`, `PullRequest`, `DraftIssue`.                                |
| `state`  | `OPEN`, `CLOSED`, `MERGED`, `DRAFT`.                                 |
| `repo`   | `owner/name` exacto.                                                 |

Para hacer match con varios valores, separá con `;`. Ejemplo:
`In Progress ; In review`.

---

## Endpoint

Se usa la GraphQL v4 de GitHub:

```
POST https://api.github.com/graphql
Authorization: Bearer <PAT>
```

con una query que pide los primeros `ghMaxResults` ítems del
`projectV2(number:)` del owner (`user` u `organization`). Por cada ítem
se traen el contenido (Issue / PR / Draft), los labels y los valores de
los campos personalizados (single-select, text, number, iteration).

El campo *Status* se resuelve buscando, dentro de los `fieldValues`, un
single-select cuyo nombre coincida (case-insensitive) con
`ghStatusField` (configurable, por defecto `Status`).

---

## Seguridad

- El token se guarda en **texto plano** en
  `~/.config/plasma-org.kde.plasma.desktop-appletsrc` (permisos del
  usuario, no del grupo) y también en SQLite local. No se sube a
  ningún servicio externo.
- Sólo se hacen requests `GET https://api.github.com/user` (test) y
  `POST https://api.github.com/graphql` (fetch). No se hacen escrituras
  contra GitHub.
- Revocá el token cuando dejes de usar el plasmoide:
  <https://github.com/settings/tokens>.

---

## Debug

Habilitado por defecto (`ghDebug = true`). Cada fetch loggea URL,
status HTTP, tamaño de cuerpo y un resumen por categoría. Lo ves con:

```bash
journalctl --user -f _COMM=plasmashell | grep -i ghstore
```

Y dentro del popup hay un botón `ⓘ` que muestra el log de la última
consulta (mismo overlay que Jira).
