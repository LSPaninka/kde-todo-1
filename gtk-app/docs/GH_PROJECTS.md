# Modo GitHub Projects

Vista de **solo lectura** de un **GitHub Projects (V2)** vía la API **GraphQL
v4** (`https://api.github.com/graphql`). Autenticación **Bearer** con un
Personal Access Token.

## Token

- **PAT clásico**: scopes `project`, `read:org`, `repo`.
- **PAT fine-grained**: acceso de lectura a *Projects* (e *Issues* / *Pull
  requests* de los repos vinculados).

## Configuración (Preferencias → GitHub)

| Campo                | Ejemplo                          |
|----------------------|----------------------------------|
| **Token**            | `github_pat_…` / `ghp_…`         |
| **Owner**            | `mi-usuario` o `mi-org`          |
| **Tipo de owner**    | `user` u `organization`          |
| **Número de proyecto** | el `N` de `.../projects/N`     |
| **Campo de estado**  | `Status` (single-select usado como estado) |
| **Incluir cerrados** | incluir issues cerrados / PRs merged |
| **Refresco / Máx.**  | `5` min / `100` ítems            |

El botón **Probar** valida el token contra `/user`.

## Categorías (tabs)

Hasta **4** categorías. Cada una filtra por:

- **Campo**: `status` (valor del single-select configurado), `type`
  (`Issue`/`PullRequest`/`DraftIssue`), `state` (`OPEN`/`CLOSED`/`MERGED`/`DRAFT`),
  `repo` (`owner/name`), o vacío (todos).
- **Valor**: `;` como separador OR. Ej.: `Todo;In Progress`.

Cada ítem muestra su número, título, repo y estado; al hacer clic se abre en el
navegador.
