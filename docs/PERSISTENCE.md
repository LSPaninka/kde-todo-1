# Persistencia de datos

Este documento explica **dónde** se guardan las tareas, las
credenciales de Jira y la cache, **cómo** se persisten y **cómo
depurar / respaldar / migrar**. Aplica a Kubuntu 24.04 con KDE Plasma
5.27 + Qt 5.15.

---

## TL;DR

- **Backend**: **SQLite** vía `QtQuick.LocalStorage 2.0` (parte de
  Qt 5; en Kubuntu/Debian viene en el paquete
  `qml-module-qtquick-localstorage` que **a veces no está instalado
  por defecto** — el `install.sh` lo detecta y ofrece instalarlo).
- **Archivo**:
  ```
  ~/.local/share/KDE/plasmashell/QML/OfflineStorage/Databases/<hash>.sqlite
  ```
  El nombre de archivo es un hash MD5 del nombre lógico de la base
  (`CategorizedToDo`); junto al `.sqlite` hay un `.ini` con metadatos.
- **Atomic & durable**: cada mutación es una transacción SQLite, que
  hace `fsync()` por nosotros. Persiste a través de reboots, crashes
  de plasmashell y `kquitapp5` forzados.
- **Configuración del widget** (modo, categorías, opciones del panel):
  sigue en `Plasmoid.configuration`. Las **credenciales de Jira** se
  mirroran a SQLite además de a Plasma — si Plasma las pierde, las
  recuperamos en el siguiente arranque.

---

## Por qué se cambió a SQLite

Antes intentamos dos enfoques que **no funcionaron de manera fiable**
en el setup del usuario:

1. `Plasmoid.configuration.tasksJson` con `writeConfig()` explícito.
   El `KConfigPropertyMap` debounce dejaba los cambios en memoria;
   un reboot frío los perdía.
2. Archivos JSON propios escritos vía
   `PlasmaCore.DataSource(engine: "executable")`.
   Dependía de que el data engine `executable` esté presente y
   funcional, lo cual varía entre instalaciones.

La solución es la **API canónica de QML para persistencia local**:
`QtQuick.LocalStorage`, que envuelve SQLite. Es síncrona, atómica,
durable y viene con todas las instalaciones de Qt.

---

## Esquema de la base

```sql
CREATE TABLE tasks (
    id          INTEGER PRIMARY KEY,
    title       TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    category    INTEGER NOT NULL DEFAULT 0,
    priority    TEXT NOT NULL DEFAULT 'M',
    done        INTEGER NOT NULL DEFAULT 0,    -- bool
    archived    INTEGER NOT NULL DEFAULT 0,    -- bool
    created_at  INTEGER NOT NULL DEFAULT 0,    -- ms epoch
    archived_at INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE subtasks (
    id       INTEGER PRIMARY KEY,
    task_id  INTEGER NOT NULL,
    title    TEXT NOT NULL,
    priority TEXT NOT NULL DEFAULT 'M',
    done     INTEGER NOT NULL DEFAULT 0,
    position INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE settings (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE jira_cache (
    issue_key  TEXT PRIMARY KEY,
    data       TEXT NOT NULL,        -- JSON blob de la incidencia
    fetched_at INTEGER NOT NULL
);

CREATE TABLE schema_version (v INTEGER NOT NULL);
```

`settings` guarda credenciales de Jira (`jira.site`, `jira.email`,
`jira.token`, `jira.jql`) como respaldo.

---

## Cómo encontrar el archivo

```bash
# La carpeta donde Qt LocalStorage guarda DBs por org/app:
DIR=~/.local/share/KDE/plasmashell/QML/OfflineStorage/Databases
ls -la "$DIR"

# Cuál es la nuestra (busca el .ini con nuestro nombre):
grep -l 'CategorizedToDo' "$DIR"/*.ini

# Inspeccionar la base con sqlite3:
DB=$(grep -l 'CategorizedToDo' "$DIR"/*.ini | sed 's/\.ini$/.sqlite/')
sqlite3 "$DB" '.tables'
sqlite3 "$DB" 'SELECT id, title, category, done FROM tasks WHERE archived=0;'
sqlite3 "$DB" 'SELECT key FROM settings;'
sqlite3 "$DB" 'SELECT issue_key, fetched_at FROM jira_cache;'
```

---

## Verificar que persiste

1. Agregá una tarea desde el popup.
2. Revisá la base (ver bloque anterior) — la tarea debería estar.
3. Cerrá plasmashell brutalmente:
   ```bash
   pkill -9 plasmashell && kstart5 plasmashell
   ```
4. Reabrí el popup — la tarea sigue.

Para Jira:
1. Configurá site / email / token / JQL en *Configurar → Jira* y
   pulsá Aplicar.
2. Comprobá:
   ```bash
   sqlite3 "$DB" "SELECT key, value FROM settings WHERE key LIKE 'jira.%';"
   ```
3. Reiniciá la PC. Las creds quedan en SQLite y `JiraStore.init()`
   las restaura en `Plasmoid.configuration` si Plasma las hubiera
   perdido.

---

## Backup / restore / migración

```bash
# Backup
DIR=~/.local/share/KDE/plasmashell/QML/OfflineStorage/Databases
DB=$(grep -l 'CategorizedToDo' "$DIR"/*.ini | sed 's/\.ini$/.sqlite/')
INI="${DB%.sqlite}.ini"
cp -p "$DB" "$INI" ~/categorizedtodo-bak/

# Restore (cerrá Plasma para evitar lock)
kquitapp5 plasmashell
cp -p ~/categorizedtodo-bak/*.sqlite ~/categorizedtodo-bak/*.ini "$DIR"/
kstart5 plasmashell
```

Para mover datos entre máquinas o entre instancias del plasmoide
**sin tocar la base**, seguí usando el botón **Exportar / Importar
JSON** que tiene cada categoría desde el popup.

---

## Diferencia entre lo que vive en SQLite y lo que vive en KConfig

| Cosa                         | SQLite | `Plasmoid.configuration` |
| ---------------------------- | :----: | :----------------------: |
| Tareas activas + subtareas   |   ✅   |            ❌            |
| Tareas archivadas            |   ✅   |            ❌            |
| Credenciales Jira            |   ✅   |        ✅ (mirror)        |
| Cache de incidencias Jira    |   ✅   |            ❌            |
| Modo (todo / jira)           |   ❌   |            ✅            |
| Cantidad y nombres de cat.   |   ❌   |            ✅            |
| Colores de categorías        |   ❌   |            ✅            |
| Estilo del contador (panel)  |   ❌   |            ✅            |
| Tamaño del popup             |   ❌   |            ✅            |

La idea: lo que **importa que no se pierda** vive en SQLite (que es
robusto). Lo que es preferencia visual o configuración del widget
vive en `Plasmoid.configuration`, que el diálogo *Configurar* persiste
de manera estándar (Apply/OK).

Las **credenciales de Jira** son el caso especial: se persisten en
los dos lados a la vez. Si KConfig las pierde, en el siguiente
arranque las recuperamos del settings table de SQLite y las volvemos
a inyectar en `Plasmoid.configuration`.

---

## Debug

0. **`module "QtQuick.LocalStorage" is not installed`**
   Falta el paquete del módulo QML. Instalalo con:
   ```bash
   sudo apt install qml-module-qtquick-localstorage
   kquitapp5 plasmashell && kstart5 plasmashell
   ```
   El `install.sh` chequea esto antes de instalar y ofrece hacerlo
   automáticamente.

1. **¿La DB se creó?**
   ```bash
   ls -la ~/.local/share/KDE/plasmashell/QML/OfflineStorage/Databases/
   ```
   Si no hay nada, `Database.init()` falló; mirá los logs.

2. **Logs QML**:
   ```bash
   journalctl --user -f _COMM=plasmashell | grep -iE 'database|taskstore|jirastore'
   ```
   `Database.init failed:` indica que `LocalStorage` no pudo abrir la
   base — chequeá permisos de `~/.local/share/KDE/plasmashell/`.

3. **Inspeccionar tareas**:
   ```bash
   sqlite3 "$DB" 'SELECT id, title, category, done, archived FROM tasks;'
   ```

4. **Resetear**:
   ```bash
   rm -f "$DB" "${DB%.sqlite}.ini"
   ```
   Plasma re-creará la base vacía la próxima vez.

5. **Tamaño**: SQLite escala muy bien. La DB pesa unos pocos KB para
   uso normal; podés tener miles de tareas sin notar el costo.

---

## Limitaciones conocidas

- **Concurrencia**: SQLite tolera múltiples readers pero un solo
  writer. Como el plasmoide es single-process y single-thread (QML),
  esto no afecta. Si tuvieras dos instancias del plasmoide
  funcionando a la vez, podrían chocar; en la práctica Plasma corre
  sólo una instancia QML a la vez.
- **Hash en el nombre del archivo**: el nombre `<md5>.sqlite` es feo
  pero estándar de Qt LocalStorage. El `.ini` adyacente identifica
  qué base es cuál.
- **Migración del esquema**: la tabla `schema_version` permite agregar
  migraciones cuando cambie el modelo. No hay nada que hacer hoy si
  estás en `v=1`.
