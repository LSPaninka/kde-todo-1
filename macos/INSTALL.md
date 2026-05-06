# Instalación — Categorized ToDo (macOS)

Esta guía describe paso a paso cómo compilar e instalar la app en
**macOS 14 Sonoma o más nuevo** (probada en **macOS 26 Tahoe**).

---

## 1. Requisitos

| Requisito | Versión mínima | Cómo verificar |
|-----------|----------------|----------------|
| macOS     | 14.0           | `sw_vers`      |
| Swift     | 5.10           | `swift --version` |
| Xcode CLT | 15             | `xcode-select -p` |

Si Swift no está instalado:

```bash
xcode-select --install
```

(Acepta el prompt y esperá que terminen las "Command Line Tools".)

Si querés Xcode completo (no es necesario, pero ayuda para iterar):
descargalo desde la App Store o desde
<https://developer.apple.com/xcode/>.

---

## 2. Clonar el repo

```bash
git clone https://github.com/lspaninka/kde-todo-1.git
cd kde-todo-1/macos
```

> Si ya tenés el repo, simplemente entrá al directorio `macos/`.

---

## 3. Compilar

Una sola línea:

```bash
./build.sh
```

Esto:
1. Llama a `swift build --configuration release`.
2. Empaqueta el binario en `build/CategorizedToDo.app` con un `Info.plist`
   que incluye `LSUIElement = YES` (la app no muestra ícono en el Dock).
3. Hace `codesign --sign -` (ad-hoc) para que macOS no se queje.

Para una build universal (arm64 + x86_64):

```bash
./build.sh --universal
```

Para limpiar antes de compilar:

```bash
./build.sh --clean
```

Output:

```
Built: build/CategorizedToDo.app

Run it with:    open build/CategorizedToDo.app
Install it with: ./install.sh
```

---

## 4. Probar sin instalar

```bash
open build/CategorizedToDo.app
```

Mirá la **barra de menús** (esquina superior derecha): debería aparecer un
cuadradito blanco con un `0`. Hacé click y se abre el popup. ✅

Para cerrar la app: clic en el cuadrado → **⏻ Salir**.

---

## 5. Instalar

### Para tu usuario (recomendado)

```bash
./install.sh
```

Copia `build/CategorizedToDo.app` a `~/Applications/CategorizedToDo.app`.
(macOS reconoce esta carpeta como "Applications" del usuario, sin pedir
permisos de administrador.)

Para abrirla:

```bash
open ~/Applications/CategorizedToDo.app
```

O desde Spotlight: ⌘-Space → escribir "Categorized" → Enter.

### Para todos los usuarios

```bash
./install.sh --system
```

Copia a `/Applications/CategorizedToDo.app` (te va a pedir contraseña con
`sudo`).

### Auto-arranque al iniciar sesión

```bash
./install.sh --launch
```

Esto, además de instalar:

1. Crea
   `~/Library/LaunchAgents/com.categorizedtodo.app.plist` con
   `RunAtLoad = YES`.
2. Hace `launchctl load` para que se ejecute en cada login.
3. Abre la app de inmediato.

Si preferís controlar el auto-arranque desde Ajustes del sistema, podés
hacerlo desde **Ajustes del Sistema → General → Ítems de inicio de sesión**
y activar la app desde ahí, en lugar de pasar `--launch`.

---

## 6. Actualizar

Después de un `git pull` o de modificar código:

```bash
cd macos
./install.sh        # repite build + install (también si usás --launch)
```

El script detecta si la app está corriendo y la cierra antes de reemplazarla.

---

## 7. Desinstalar

```bash
./install.sh --uninstall
```

Esto:

1. Mata el proceso (`pkill -x CategorizedToDo`).
2. Elimina la app instalada (en `~/Applications` o `/Applications`).
3. Elimina y descarga el LaunchAgent.

Los **datos del usuario quedan**:

- Tareas:
  `~/Library/Application Support/CategorizedToDo/data.json`
- Configuración:
  `defaults read com.categorizedtodo.app`

Para borrarlos también:

```bash
rm -rf "$HOME/Library/Application Support/CategorizedToDo"
defaults delete com.categorizedtodo.app
```

---

## 8. Solución de problemas

### "swift: command not found"

Falta el entorno de desarrollo:

```bash
xcode-select --install
```

### "App is damaged and can't be opened" / Gatekeeper

`build.sh` ya hace una firma ad-hoc que evita la mayoría de los warnings.
Si aún así Gatekeeper bloquea la app:

```bash
xattr -dr com.apple.quarantine ~/Applications/CategorizedToDo.app
```

### El cuadrado no aparece en la barra

Probablemente la app crasheó al arrancar. Mirá los logs:

```bash
log stream --predicate 'process == "CategorizedToDo"' --info
```

O ejecutá directamente desde Terminal para ver `stderr`:

```bash
~/Applications/CategorizedToDo.app/Contents/MacOS/CategorizedToDo
```

### Cambié los colores y siguen viejos

Los cambios se persisten en `UserDefaults` y se aplican enseguida. Si querés
restablecer todo a los valores de fábrica:

```bash
defaults delete com.categorizedtodo.app
```

Y reabrí la app.

### Configurar Jira (modo Jira)

1. Generá un API token en
   <https://id.atlassian.com/manage-profile/security/api-tokens>.
2. Abrí la configuración (icono de engranaje en el popup) → pestaña **Jira**.
3. Completá:
   - URL: `https://<tu-org>.atlassian.net` (sin `/` final).
   - Email: el de tu cuenta Atlassian.
   - API token: pegá el token generado (queda guardado en el Keychain).
   - JQL: pegá tu consulta (ver ejemplos en `README.md`).
4. Click en **Probar conexión** — debe mostrar `Conectado como <Nombre>` en verde.
5. Cambiá a la pestaña **General** → **Modo: Jira**.
6. (Opcional) En **Categorías Jira** ajustá los filtros que prefieras.

El token nunca se guarda en `UserDefaults`. Para borrarlo manualmente:

```bash
security delete-generic-password -s com.categorizedtodo.app -a jira.token
```

### Logs de Jira

Activá **Diagnóstico → Logs detallados** en la pestaña Jira y ejecutá:

```bash
log stream --predicate 'process == "CategorizedToDo"' --info
```

Vas a ver cada fetch, cuántos issues llegaron y cuántos cayeron en cada
pestaña. Útil para iterar JQL y filtros.

### Falla `swift build` con "platforms" en macOS antiguo

`Package.swift` requiere macOS 14+. En versiones anteriores hay que bajar
ese mínimo (perderás `ColorPicker`, `ImageRenderer`, `MenuBarExtra`, etc.):

```swift
platforms: [.macOS(.v13)]
```

Pero la experiencia esperada es macOS 14+.

---

## 9. Build con Xcode (opcional)

El proyecto es un **Swift Package**, así que Xcode lo abre directamente:

```bash
open Package.swift
```

Producto: scheme **CategorizedToDo** → ⌘R para correr en debug. Para
empaquetar a `.app` seguí usando `build.sh`.
