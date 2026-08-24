# Ícono en la barra (System Tray / AppIndicator)

La app publica un **reloj blanco** en la barra superior. Desde ahí:

| Acción | Resultado |
|---|---|
| **Clic izquierdo** | Abre la **ventanita** (popup) del worklog, chica y usable ahí mismo. |
| **Clic derecho** | Menú: *Mostrar reloj* · *Abrir aplicación* · **Salir**. |
| **Clic del medio** | Abre la ventanita (igual que el izquierdo). |
| **Escape / clic afuera** | Cierra la ventanita (la app sigue viva en la barra). |
| **Salir** | Cierra la aplicación de verdad. |

La ventanita es **frameless** (sin barra de título) y su **tamaño es
configurable** en *Preferencias → General* (`Ancho`/`Alto de la ventanita`).

---

## Cómo funciona por dentro

GNOME **no tiene bandeja propia**: el área de notificación clásica (XEmbed)
se eliminó en GNOME 3.26. El estándar actual es
**StatusNotifierItem (SNI)** sobre D-Bus, y hace falta una **extensión** que
haga de *host* y dibuje los íconos en la barra.

Esta app implementa el protocolo **directamente sobre GDBus**:

- Expone `org.kde.StatusNotifierItem` en `/StatusNotifierItem`
- Expone `com.canonical.dbusmenu` en `/MenuBar` (el menú del clic derecho)
- Se registra contra `org.kde.StatusNotifierWatcher`

> No usamos `libayatana-appindicator` **a propósito**: esa librería es GTK3 y
> no puede convivir con GTK4 en el mismo proceso. Por eso el SNI está escrito
> a mano (ver `src/TrayIcon.vala`).

Detalle relevante: publicamos `ItemIsMenu = false`, que es lo que hace que el
**clic izquierdo dispare `Activate`** (abrir la ventanita) en vez de abrir el
menú. El clic derecho siempre abre el menú del `dbusmenu`.

---

## Qué extensión hace falta (GNOME)

### Ubuntu 22.04 / 24.04 (GNOME) — recomendado

Ubuntu ya trae la extensión **"Ubuntu AppIndicators"**. Solo hay que
asegurarse de que esté **instalada y activada**:

```bash
# 1) Instalar (en Ubuntu suele venir preinstalada)
sudo apt install gnome-shell-extension-appindicator

# 2) Activarla
gnome-extensions enable ubuntu-appindicators@ubuntu.com

# 3) Verificar que quedó activa
gnome-extensions list --enabled | grep -i appindicator
```

Si `gnome-extensions enable` dice que no existe, fijate el ID real:

```bash
gnome-extensions list | grep -i indicator
```

Suele ser `ubuntu-appindicators@ubuntu.com` (Ubuntu) o
`appindicatorsupport@rgcjonas.gmail.com` (la versión upstream).

**Después de instalarla hay que reiniciar GNOME Shell:**

- En **X11**: `Alt+F2` → escribí `r` → Enter.
- En **Wayland**: hay que **cerrar sesión y volver a entrar** (no se puede
  reiniciar el shell en caliente).

### GNOME "puro" (Fedora, Arch, Debian con GNOME upstream)

Instalá **AppIndicator and KStatusNotifierItem Support** desde
<https://extensions.gnome.org/extension/615/appindicator-support/>
(o el paquete `gnome-shell-extension-appindicator` de tu distro) y activala
igual que arriba.

### KDE Plasma / XFCE / MATE / Cinnamon

No hace falta nada extra:

- **KDE Plasma**: soporta SNI de forma nativa.
- **XFCE**: agregá al panel el plugin *Status Notifier* (`xfce4-panel` 4.18
  suele traerlo integrado; si no, `sudo apt install xfce4-statusnotifier-plugin`).
  Ver la sección *Xfce / Xubuntu* del README.
- **MATE / Cinnamon**: soportan SNI vía sus applets de área de notificación.

---

## Posición de la ventanita: X11 vs Wayland

Esto es una **limitación real de GNOME/Wayland**, no un bug de la app:

| Sesión | Comportamiento |
|---|---|
| **X11** | La ventanita se **ancla arriba a la derecha**, debajo de la barra, al lado del ícono. |
| **Wayland** | La **posición la decide el compositor** (Mutter). Suele aparecer centrada. |

En **GTK4 no existe API para mover una ventana** (se eliminó respecto de GTK3),
y en **Wayland un cliente no puede posicionarse a sí mismo** por diseño del
protocolo. En X11 lo hacemos igual usando el `xid` de la superficie
(`Gdk.X11.Surface.get_xid()` + `XMoveWindow`).

Ajustes en *Preferencias → General*:

- **Anclar la ventanita arriba a la derecha** (`popup-anchor-top-right`)
- **Margen superior del anclaje** (`popup-anchor-margin`, por defecto `44 px`,
  pensado para despejar la barra de GNOME)

Si querés la posición anclada, usá una **sesión X11**: en la pantalla de login
tocá el engranaje ⚙ y elegí *"Ubuntu on Xorg"*.

---

## Verificar que el ícono está publicado

Con la app corriendo:

```bash
# ¿Se registró el StatusNotifierItem?
gdbus call --session --dest org.freedesktop.DBus \
  --object-path /org/freedesktop/DBus \
  --method org.freedesktop.DBus.ListNames | tr ',' '\n' | grep StatusNotifierItem
```

Debería aparecer algo como `org.kde.StatusNotifierItem-123456-1`. Con ese
nombre podés inspeccionarlo:

```bash
BN=org.kde.StatusNotifierItem-123456-1   # usá el que te haya salido

# Ícono que estamos publicando
gdbus call --session --dest $BN -o /StatusNotifierItem \
  -m org.freedesktop.DBus.Properties.Get org.kde.StatusNotifierItem IconName

# Menú del clic derecho
gdbus call --session --dest $BN -o /MenuBar \
  -m com.canonical.dbusmenu.GetLayout -- 0 1 '[]'

# Simular el clic izquierdo (abre la ventanita)
gdbus call --session --dest $BN -o /StatusNotifierItem \
  -m org.kde.StatusNotifierItem.Activate -- 0 0
```

---

## Problemas comunes

**No veo el ícono en la barra.**
Casi siempre es la extensión: no está activada, o GNOME Shell no se reinició
después de instalarla. Verificá con
`gnome-extensions list --enabled | grep -i appindicator` y reiniciá la sesión.
También podés confirmar que el problema es del *host* y no de la app corriendo
el `ListNames` de arriba: si el nombre aparece, la app está publicando bien y
lo que falta es la extensión.

**El ícono aparece pero está vacío / roto.**
La app le pasa al host un `IconThemePath` apuntando a la carpeta donde está el
SVG, así que funciona incluso ejecutándola sin instalar (desde `build/`). Si
igual falla, instalá de verdad (`./install.sh`) para que el ícono quede en el
tema (`~/.local/share/icons/hicolor/symbolic/apps/`) y refrescá la caché:

```bash
gtk4-update-icon-cache -f -t ~/.local/share/icons/hicolor
```

**El clic izquierdo me abre el menú en vez de la ventanita.**
Algunas versiones viejas de la extensión ignoran `ItemIsMenu` y abren siempre
el menú. En ese caso usá la primera entrada del menú, *Mostrar reloj*, que hace
exactamente lo mismo.

**Cerré la ventana y la app desapareció.**
Si el ícono está **desactivado** (`show-tray-icon = false`), la app se comporta
como un programa normal y cerrar la última ventana la termina. Con el ícono
activo, cerrar solo la oculta y seguís teniéndola en la barra.

**Quiero que NO quede en segundo plano.**
*Preferencias → General → "Seguir en segundo plano al cerrar"* (off), o
directamente apagá el ícono de la barra.
