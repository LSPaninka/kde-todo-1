# Icono de la barra superior y segundo plano

La app publica un icono de bandeja usando el estándar **StatusNotifierItem
(SNI / KStatusNotifierItem)** sobre D-Bus, con su menú **com.canonical.dbusmenu**.
No usa `libappindicator` (GTK 3), así que convive sin problemas con GTK 4.

## Interacción

| Acción                         | Resultado                                  |
|--------------------------------|--------------------------------------------|
| **Clic izquierdo** en el icono | Abre / cierra la **ventanita** (1000×700). |
| **Clic derecho** en el icono   | Menú: *Abrir aplicación · Ventanita · ToDo · Jira · GitHub Projects · **Salir***. |

Dentro de la ventanita, el botón **⛶** abre la aplicación completa.

## Segundo plano

- Cerrar la ventana desde el dock **no** cierra la app: se oculta y sigue
  corriendo en la bandeja (con `run-in-background` activo, por defecto).
- Para **terminar** la app: **clic derecho en el icono → Salir**, o `☰ → Salir`
  dentro de la app, o `categorized-todo --quit` desde una terminal.

## ¿No ves el icono?

El icono lo dibuja el *shell*, que debe implementar un **StatusNotifierWatcher**:

- **Ubuntu (sesión GNOME/Ubuntu)**: viene la extensión **«Ubuntu
  AppIndicators»** activada de fábrica. Si la desactivaste, reactivala en
  *Extensiones*.
- **GNOME puro**: instalá y activá *AppIndicator and KStatusNotifierItem
  Support* (`gnome-shell-extension-appindicator`).
- **KDE Plasma**: funciona sin nada extra.

Si no hay ningún *watcher*, la app lo registra igual (y lo avisa por consola con
`WARNING: no StatusNotifierWatcher available`), pero el icono no aparece. La app
sigue siendo usable por ventana; podés abrir la ventanita con
`categorized-todo --popup`.

## Opciones (Preferencias → Ventana)

- **Mostrar icono en la barra superior** (`show-tray-icon`).
- **Seguir en segundo plano al cerrar la ventana** (`run-in-background`).
- **Arrancar oculto** (`start-hidden`) — útil para autostart.
- **Tamaño** y **escala** de la ventanita (`popup-width`, `popup-height`,
  `popup-scale`).

### Autostart en segundo plano

Para que arranque con la sesión, minimizado en la bandeja:

```bash
mkdir -p ~/.config/autostart
cat > ~/.config/autostart/categorized-todo.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Categorized ToDo
Exec=categorized-todo --background
X-GNOME-Autostart-enabled=true
EOF
```
