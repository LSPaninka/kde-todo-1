# Persistencia y respaldos

## Configuración → GSettings (dconf)

Toda la configuración (modo, categorías, credenciales, tamaños de ventana,
opciones de bandeja) vive en **GSettings**, esquema
`io.github.categorizedtodo`, backend *dconf*.

Ver / editar / respaldar:

```bash
# Ver todo
gsettings list-recursively io.github.categorizedtodo

# Cambiar un valor
gsettings set io.github.categorizedtodo popup-width 1200

# Respaldar / restaurar
dconf dump /io/github/categorizedtodo/ > ct-config.ini
dconf load /io/github/categorizedtodo/ < ct-config.ini

# Volver a los valores por defecto
dconf reset -f /io/github/categorizedtodo/
```

## Datos → SQLite

Las **tareas** (y el caché de Jira/GitHub) viven en:

```
~/.local/share/categorized-todo/todo.sqlite
```

Es una base SQLite normal (modo WAL). Tablas: `tasks`, `subtasks`, `settings`,
`jira_cache`, `gh_cache`, `schema_version`.

Respaldo simple:

```bash
cp ~/.local/share/categorized-todo/todo.sqlite ~/todo-backup.sqlite
# o, en caliente:
sqlite3 ~/.local/share/categorized-todo/todo.sqlite ".backup ~/todo-backup.sqlite"
```

Las **credenciales** de Jira/GitHub/Notion se guardan en GSettings (dconf), en
texto plano bajo tu perfil de usuario — igual que cualquier config de dconf.
