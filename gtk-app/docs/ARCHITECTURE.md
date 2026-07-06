# Arquitectura

Port en **Vala + GTK 4 + libadwaita** del plasmoide QML. Mantiene el mismo
modelo de datos y la misma lógica de red; sólo cambia la capa de UI y la de
configuración/persistencia (GSettings + SQLite en vez de KConfig +
QtQuick.LocalStorage).

## Capas

```
Application (Adw.Application)
 ├── Config            → GLib.Settings (esquema io.github.categorizedtodo)
 ├── Database          → SQLite (sqlite3) en ~/.local/share/categorized-todo/
 ├── TaskStore         → lista ToDo en memoria; cada mutación escribe a SQLite
 ├── JiraStore         → REST v3 (libsoup3 + json-glib), cache en jira_cache
 ├── GhStore           → GraphQL v4 (libsoup3 + json-glib), cache en gh_cache
 ├── NotionSyncStore   → sync bidireccional con Notion (api.notion.com/v1)
 ├── Tray              → StatusNotifierItem + com.canonical.dbusmenu (GDBus)
 ├── MainWindow        → ventana completa
 └── PopupWindow       → ventanita de la bandeja (tamaño/escala configurables)
```

### Las *stores* son la fuente de verdad; las vistas son tontas

Cada store expone `changed()` (con un `version` que se incrementa) y las vistas
(`TodoView`, `JiraView`, `GhView`) se reconstruyen al recibir la señal. Los
objetos `Task`/`Subtask`/`JiraIssue`/`GhItem` (ver `Models.vala`) son planos.
`MainWindow` y `PopupWindow` comparten los mismos stores pero cada una crea su
propio árbol de widgets (`ModeContent`), porque un widget GTK no puede estar en
dos contenedores a la vez.

### Persistencia

- **SQLite** (`Database.vala`): tablas `tasks`, `subtasks`, `settings`,
  `jira_cache`, `gh_cache`, `schema_version`. Cada mutación va dentro de su
  propia transacción; no hay debounce.
- **GSettings** (`Config.vala`): toda la configuración del widget (modo,
  categorías, credenciales, tamaños de ventana, opciones de bandeja). Al ser
  *dconf*, es durable por usuario, así que —a diferencia del plasmoide— no hace
  falta espejar las credenciales a SQLite.

### La bandeja (`tray/Tray.vala`)

Implementa el estándar **StatusNotifierItem** (KStatusNotifierItem) y su menú
**com.canonical.dbusmenu** enteramente sobre **GDBus** (sin depender de
libappindicator/GTK3, que no convive con GTK 4 en el mismo proceso). Las firmas
D-Bus exactas del dbusmenu (`(ia{sv}av)`, etc.) se exponen con
`[DBus (signature = …)] Variant`.

- Clic izquierdo → `Activate()` → abre/cierra la ventanita.
- Clic derecho → dbusmenu → *Abrir aplicación / modos / Salir*.

### Segundo plano

`Application` llama a `hold()` al arrancar, así el proceso sobrevive aunque se
cierren todas las ventanas. Cerrar la ventana principal la **oculta** (si
`run-in-background` y la bandeja están activas); el único camino para terminar
es **Salir** (menú del icono o `app.quit`) o `categorized-todo --quit`.

## Build

**Meson + Ninja**. `data/` instala el esquema GSettings, el `.desktop`, el
`.metainfo.xml` y los iconos; `src/` compila el ejecutable `categorized-todo`.
Las constantes de compilación (`APP_ID`, `VERSION`) se generan en `config.h` y
se exponen a Vala con `src/config.vapi`.
