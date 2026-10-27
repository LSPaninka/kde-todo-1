# Modo Trello

Muestra las tarjetas de **un tablero** de Trello: **una pestaña por lista
abierta** (en el mismo orden que el tablero) y **un cuadrado por lista** en
el panel. Usa la API REST de Trello (`https://api.trello.com/1`) con una
**API key + token** de usuario.

## Configuración

Pestaña **Trello** del diálogo de configuración:

1. **API key** — en <https://trello.com/power-ups/admin> creá un Power-Up
   (cualquier nombre/workspace) y copiá su *API key* (botón «Obtener…»).
2. **Token** — con la key ya escrita, «Generar token…» abre la página de
   autorización de Trello (`scope=read,write`, `expiration=never`).
   Autorizá y pegá el token que muestra.
3. **Tablero** — pegá su URL (`https://trello.com/b/AbCd1234/nombre`), su
   *short link* o su id; o usá «Cargar mis tableros» y elegilo del combo.
4. **Solo tarjetas asignadas a mí** (por defecto **sí**) — filtra por las
   tarjetas donde sos miembro.
5. **Auto-refresh** en minutos (0 = solo manual) y **logs de depuración**.

«Probar» verifica la key y el token contra `/members/me`.

Pestaña **Listas Trello**: carga las listas del tablero (con la config ya
aplicada) y para cada una elegís si **se muestra** (pestaña + cuadrado del
panel), su **color** y el color del **número** en el panel. Se guardan por
**id de lista**, así que renombrar o reordenar listas en Trello no los pierde.

> La key y el token quedan en texto plano en
> `~/.config/plasma-org.kde.plasma.desktop-appletsrc` y espejados en la base
> SQLite del plasmoide (tabla `settings`, claves `trello.key`,
> `trello.token`, `trello.board`), igual que las credenciales de Jira/GitHub.

## Uso

- **Pestañas**: una por lista visible, con su color y la cantidad de tarjetas.
- **Caja bajo las pestañas**: por defecto **crea una tarjeta rápida** en la
  lista actual (Enter o «Agregar»), asignada a vos. La **lupa** del encabezado
  la convierte en **buscador** (título, descripción y nombres de etiquetas).
- **«Nueva…»** abre el modal completo de creación.
- **Tarjeta**: etiquetas con color, título, íconos de descripción /
  comentarios, checklist `hechos/total`, vencimiento (rojo = vencida,
  amarillo = vence en < 24 h, verde = completada), iniciales de los
  miembros y una **barra de progreso del checklist**.
  - **Click**: modal de detalle / edición.
  - **Click central**: abre la tarjeta en trello.com.
  - **Click derecho**: *Ver / editar*, **Mover a** otra lista, *Abrir en Trello*.
- **Modal**:
  - Con **Guardar** se aplican juntos: título, lista, etiquetas, miembros,
    vencimiento (`dd/MM/aaaa HH:mm`; sin hora = 12:00) + *Completada*, y
    descripción. Solo se envían los campos que cambiaron.
  - Al instante (como en Trello): tildar/destildar, agregar y borrar ítems
    de **checklists**, crear una checklist nueva, y **comentar**.
- **Panel**: click en un cuadrado abre el popup en esa lista; hover muestra
  los títulos de sus tarjetas.

## Detalles técnicos

- `TrelloStore.qml`: autenticación por header
  `Authorization: OAuth oauth_consumer_key="…", oauth_token="…"` (no van en la
  URL). El fetch hace en paralelo `GET /members/me`, `/boards/{id}`,
  `/boards/{id}/lists?filter=open`, `/boards/{id}/cards/open`,
  `/boards/{id}/labels` y `/boards/{id}/members`.
- Escrituras: `POST /cards`, `PUT /cards/{id}` (mover = cambiar `idList`),
  `PUT /cards/{id}/checkItem/{idCheckItem}`, `POST|DELETE
  /checklists/{id}/checkItems`, `POST /checklists`,
  `POST /cards/{id}/actions/comments`. Cuerpos JSON; `idLabels`/`idMembers`
  como lista separada por comas; `due: null` borra el vencimiento.
- Caché: la última foto del tablero se guarda como JSON en la tabla
  `settings` (`trello.cache`), así el popup se llena al instante al iniciar.
- Logs: `journalctl --user -f _COMM=plasmashell | grep -i trellostore`.
