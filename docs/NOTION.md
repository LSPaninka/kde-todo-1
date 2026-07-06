# Integración con Notion

> **Novedad (v1.3):** ahora el **modo ToDo** puede sincronizarse de ida y
> vuelta con una base de datos de Notion vía la **API HTTP oficial** (ver la
> sección siguiente). El **modo Notion por CLI** (`ntn`) descrito más abajo
> queda **deshabilitado momentáneamente** — el código sigue en el repo pero no
> es seleccionable como modo.

## Sincronización ToDo ↔ Notion (API HTTP)

El modo ToDo local (tareas en SQLite) puede espejarse contra una base de datos
de Notion. La sincronización es **de doble vía con «gana el más reciente»**:

- Lo nuevo en cualquier lado se crea en el otro.
- Si una tarea cambió en ambos lados desde la última sincronización, gana la
  edición más reciente.
- **No se borran tareas automáticamente** (una tarea borrada de un lado no se
  borra del otro). El estado *archivado* sí viaja (checkbox `Archived`).
- Las subtareas viajan como JSON en una propiedad `Subtasks` (rich_text).

### Puesta en marcha

1. Creá una **integración interna** en
   <https://www.notion.so/my-integrations> y copiá su *Internal Integration
   Secret* (`secret_…` / `ntn_…`).
2. Creá (o elegí) una página en Notion y **compartila con la integración**
   (menú `•••` → *Connections* → tu integración). Copiá su URL o ID.
3. En el plasmoide → *Configurar… → Notion*:
   - Pegá el **token** y la **página padre** (URL o ID).
   - Pulsá **«Probar token»** y luego **«Crear base de datos»** una sola vez.
     Se crea la base *Categorized ToDo* con el esquema: `Name (title)`,
     `Description`, `Category (number)`, `Priority (select)`, `Done`,
     `Archived`, `Subtasks (JSON)`, `LocalId (number)`.
   - **Aplicá** para guardar el `notionDatabaseId` resultante.
4. A partir de ahí la lista se sincroniza **al abrir el plasmoide** (si está
   activado *Sincronizar al abrir*), con el botón **«Notion»** del pie del
   popup, y automáticamente cada *Auto-sync (min)*.

### Notas de seguridad

- El token se guarda en texto plano en
  `~/.config/plasma-org.kde.plasma.desktop-appletsrc` y, como respaldo, en la
  base SQLite local. No se sube a ningún servicio salvo `api.notion.com`.
- La integración sólo ve las páginas/bases que le compartas explícitamente.

---

## (Deshabilitado) Modo Notion por CLI

El modo **Notion** por CLI del plasmoide consulta y edita páginas en
[Notion](https://www.notion.com/) usando el CLI oficial
[`ntn`](https://developers.notion.com/cli/get-started/overview) (presentado el
13 de mayo de 2026 como parte de la *Notion Developer Platform*). Toda la
autenticación queda **fuera** del plasmoide: el CLI se encarga. Este modo está
deshabilitado por ahora; se documenta por completitud.

---

## Qué hace

- Lista las páginas que devuelve `POST /v1/search`, con un campo de búsqueda
  opcional configurable.
- Muestra para cada página: ícono (emoji), título, fecha de última edición e
  ID acortado.
- Botón **↻** para sincronizar (también hay auto-refresh configurable, default
  10 min).
- Click en una página → diálogo de edición con:
  - **Título** (input simple).
  - **Contenido** en Markdown (área multilínea; se baja por `ntn pages get`
    y se sube por `ntn pages update --content`).
- Botón para **abrir la página en Notion** (navegador, vía `xdg-open`).
- Botón para **copiar el ID** de la página al portapapeles.
- Modal de **Diagnóstico** (ícono ⓘ) que muestra cada comando ejecutado, su
  exit code, stdout y stderr.

El modo es de lectura/escritura sobre **páginas individuales**. No
intenta replicar el editor de Notion — para edición compleja, el botón
"Abrir en Notion" te lleva al navegador.

---

## Requisitos

### 1) Instalar `ntn`

```bash
curl -fsSL https://ntn.dev | bash
# o vía npm:
npm i -g ntn
```

Verificá que esté disponible:

```bash
ntn --help
```

### 2) Autenticarse

```bash
ntn login
```

Esto abre tu navegador y te pide aprobar el acceso. La sesión queda guardada
en `~/.config/notion/` (o equivalente, ver `ntn --help`). El plasmoide **no**
guarda tokens.

Alternativamente, exportá `NOTION_API_TOKEN` en tu sesión (en `~/.profile` o
similar) y `ntn` lo usará automáticamente. **No** seteés esta variable solo
dentro de la terminal — Plasma necesita verla. Si ya corriste `ntn login`, no
hace falta tocar nada.

### 3) (Opcional) Path manual

Si `ntn` no está en `PATH` que ve plasmashell (puede pasar si lo instalaste
en `~/.local/bin` y tu PATH no incluye eso para sesiones gráficas), poné la
ruta absoluta en la pestaña **Notion** del diálogo de configuración del
plasmoide:

```
/home/usuario/.local/bin/ntn
```

---

## Configuración (pestaña *Notion*)

| Campo                | Qué hace                                                                                  |
| -------------------- | ----------------------------------------------------------------------------------------- |
| Búsqueda (opcional)  | Texto que se manda como `query` en `/v1/search`. Vacío trae todas las páginas accesibles. |
| Filtrar por          | Páginas o bases de datos (`filter.property=object`, `value=page|database`).               |
| Máx. resultados      | `page_size` (10–200, default 50).                                                         |
| Auto-refresh (min)   | Cada cuánto resincronizar. 0 = solo manual.                                               |
| Ruta de `ntn`        | Opcional. Vacío = usa el binario del PATH.                                                |
| Logs                 | Si está marcado, cada comando ejecutado se escribe a `journalctl --user`.                 |

---

## Comandos ejecutados (para auditar)

El plasmoide envuelve cada comando en `sh -c '<cmd>'` con los argumentos
**escapados con single-quote POSIX**, así que no hay forma de que un título
malicioso ejecute comandos arbitrarios.

| Acción                    | Comando equivalente                                                       |
| ------------------------- | ------------------------------------------------------------------------- |
| Listar páginas            | `ntn api v1/search -X POST -d '<json body>'`                              |
| Leer contenido (Markdown) | `ntn pages get <id>`                                                      |
| Actualizar título         | `ntn api v1/pages/<id> -X PATCH -d '{"properties":{"title":{"title":…}}}` |
| Actualizar contenido      | `ntn pages update <id> --content '<markdown>'`                            |

Para reproducirlos a mano y debuggear, abrí el diagnóstico (ⓘ) en el popup y
copiá el comando — pega tal cual en una terminal.

---

## Vista compacta (panel)

Notion no tiene categorías nativas como Jira/GH, así que la representación
compacta es **un único cuadrado** (color de marca de Notion, `#37352f`) con
el conteo total de páginas sincronizadas. Hover muestra el detalle.

La rueda del mouse en cualquier modo cicla por: ToDo → Jira → GitHub →
Notion → ToDo.

---

## Seguridad

- El plasmoide **no almacena tu token de Notion**. Toda la auth queda en lo
  que `ntn` haya guardado (que vos podés revocar con `ntn logout` o desde
  `notion.com/profile/settings/integrations`).
- Los comandos se pasan por `sh -c` con escape de single-quote, así que ni
  títulos ni contenidos pueden inyectar shell.
- `ntn` por sí mismo accede a Notion vía HTTPS. La conexión está fuera de
  control del plasmoide.

---

## Debugging

Activá el toggle **Logs** en la pestaña Notion y mirá:

```bash
journalctl --user -f _COMM=plasmashell | grep '\[NotionStore\]'
```

O, sin tocar el toggle, abrí el botón ⓘ en el popup de Notion: el log se
acumula ahí incluso si el toggle de consola está apagado.

Lo que vas a ver en cada fetch:

```
[NotionStore] === Notion fetch 2026-05-15 11:23:01 ===
[NotionStore] fetch() invocado.
[NotionStore] Parámetros:
[NotionStore]   query  = (vacío)
[NotionStore]   filter = page
[NotionStore]   max    = 50
[NotionStore] Comando: ntn api v1/search -X POST -d '{"page_size":50,…}'
[NotionStore] Completado en 412 ms (exit=0).
[NotionStore] stdout (2841 bytes):
[NotionStore]   { "object": "list", "results": [...], "has_more": false }
[NotionStore] Resumen: 7 página(s) recibida(s). has_more=false.
[NotionStore]   - My research notes  [a1b2c3d4…] (edit: 2026-05-14)
[NotionStore]   - Meeting 2026-05-13 [b5c6d7e8…] (edit: 2026-05-13)
```

Errores comunes:

| Síntoma en el log              | Probable causa                                                  |
| ------------------------------ | --------------------------------------------------------------- |
| `exit=127` + `not found`       | `ntn` no está en el PATH. Configurá la ruta en la pestaña.      |
| `exit=1` + `Not logged in`     | No corriste `ntn login`. Hacelo y volvé a sincronizar.          |
| `exit=1` + `401`               | Tu token expiró. Re-loggeate con `ntn login`.                   |
| `exit=0`, 0 results            | El filtro/búsqueda no matchea nada. Probá vaciar el campo.      |

---

## Limitaciones

- Sin paginación. Si tu workspace tiene más de `notionMaxResults` (máx. 200),
  el plasmoide solo muestra la primera tanda. Ajustá la búsqueda para acotar.
- `ntn pages update --content` reemplaza el cuerpo completo de la página.
  No hay *patch* parcial de bloques desde el CLI.
- Las propiedades custom de páginas (multi-select, fechas, relations) no se
  editan desde el plasmoide — usá Notion para eso.
- El refresh hace shell out por cada actualización. Si lo bajás a < 1 min y
  tenés mucho movimiento, podés ver `ntn` corriendo cada N segundos en `htop`.
