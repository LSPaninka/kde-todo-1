# Sincronización con Notion (modo ToDo)

El modo **ToDo** puede sincronizarse en **dos sentidos** con una base de datos
de Notion, usando la API oficial (`https://api.notion.com/v1`) y un **token de
integración interna**.

## Puesta en marcha (Preferencias → Notion)

1. Creá una **integración interna** en
   <https://www.notion.so/my-integrations> y copiá su *Internal Integration
   Secret* (`secret_…` / `ntn_…`) en **Token de integración interna**.
2. Compartí con esa integración la **página** donde querés que viva la base
   (menú `•••` → *Connections* → tu integración) y pegá el **ID de la página
   padre**.
3. Tocá **Probar** para validar el token, y luego **Crear** para que la app cree
   la base de datos «Categorized ToDo». El **ID de la base** se completa solo.
4. (Alternativa) Si ya tenés la base creada por la app, pegá directamente su
   **ID de la base de datos**.

También podés **Sincronizar ahora**, activar **Sincronizar al abrir** y fijar un
**intervalo de auto-sync**.

## Modelo de sincronización

Cada tarea local ↔ una página de Notion. Es **el más nuevo gana, sin borrados**:

- Tareas nuevas de un lado se crean del otro.
- Si una tarea cambió en ambos lados, gana la editada más recientemente.
- Nada se borra automáticamente (una página quitada en Notion no borra la tarea
  local, y viceversa).

La detección de cambios es a prueba de desfases de reloj: usa `updated_at`
(reloj local, se toca en cada edición del usuario), `notion_synced_at` (reloj
local del último reconcile) y `notion_last_edited` (el `last_edited_time` de la
página).

### Esquema de la base creada

`Name` (title), `Description` (rich_text), `Category` (number),
`Priority` (select XS/S/M/L/XL), `Done` (checkbox), `Archived` (checkbox),
`Subtasks` (rich_text con JSON), `LocalId` (number).
