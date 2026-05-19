# Instalación — Worklog Calendar

## Pre-requisitos

1. macOS 14 (Sonoma) o superior.
2. Xcode Command Line Tools:
   ```bash
   xcode-select --install
   ```
   (o Xcode completo desde el App Store).

Verificar:
```bash
swift --version    # >= 5.9
```

---

## Compilar e instalar

```bash
cd macos-worklog
./build.sh                 # release build + bundle .app
./install.sh               # copia a ~/Applications
```

Opcionales:

| Comando | Qué hace |
|---|---|
| `./install.sh --system` | Copia a `/Applications` (necesita `sudo`). |
| `./install.sh --no-build` | Sólo copia (asume `./build/` ya armado). |
| `./install.sh --uninstall` | Borra de `~/Applications` y `/Applications`. |
| `./build.sh --clean` | Borra `.build/` y `build/` antes de compilar. |

---

## Primer arranque

1. Lanzá la app desde Launchpad o:
   ```bash
   open ~/Applications/WorklogCalendar.app
   ```
2. Abrí **Preferencias** (`⌘,` o ícono del engranaje) y configurá:
   - **Jira**: sitio + email + token (botón **Probar** para validar).
   - **Clockify** (opcional): API key (también con botón **Probar**).
3. Cerrá Preferencias y tocá ↻ en el header.  La semana corriente debería
   poblarse.

---

## Credenciales y privacidad

- Los tokens (Jira) y la API key (Clockify) se guardan en el **Keychain
  del usuario** bajo el servicio `com.worklogcalendar.app`, cuentas
  `jira.token` y `clockify.api-key`.
- Las preferencias no-secretas (sitio, email, JQL, IDs cacheados,
  defaults) viven en
  `~/Library/Preferences/com.worklogcalendar.app.plist`.
- La app no envía datos a terceros distintos de Jira y Clockify.

---

## Code signing

El bundle se firma con `codesign --sign -` (firma ad-hoc).  Esto alcanza
para que macOS te deje abrirla localmente, aunque la primera vez vas a
ver el cartel "no se puede verificar el desarrollador" → tenés dos
opciones:

- Botón derecho → **Abrir** la primera vez (luego queda aprobada).
- Comando:
  ```bash
  xattr -dr com.apple.quarantine /Applications/WorklogCalendar.app
  ```

Si querés firma "real" usá tu Developer ID:

```bash
codesign --force --sign "Developer ID Application: TU NOMBRE" \
         --timestamp --options runtime \
         ./build/WorklogCalendar.app
```

---

## Troubleshooting

### `swift build` falla con `error: type 'String' does not conform to protocol 'Error'`

No deberías ver eso en este paquete — todas las APIs internas usan
`Result<T, StringError>`.  Si te pasa, es porque algún archivo nuevo
usó `Result<T, String>`; mirá
`Sources/WorklogCalendar/Models/StringError.swift` y reemplazá el tipo
de error por `StringError`.

### `HTTP 410` u `HTTP 404` al sincronizar Jira

Atlassian removió `/rest/api/3/search` en mayo de 2025.  Esta app ya usa
`/rest/api/3/search/jql`.  Si seguís viendo el error, probá que tu sitio
sea Cloud y que la URL no tenga trailing slash.

### `HTTP 403` contra Clockify

Probablemente el `Workspace ID` configurado es el **nombre** del
workspace (ej. `PEPERINA`) en vez del **ObjectId** hex de 24 chars.  La
app valida el formato y, si es inválido, lo auto-resuelve desde `/user`.
Borrá el valor manualmente en Preferencias → Clockify si querés forzar.

### No aparece en el Dock

`Info.plist` no incluye `LSUIElement` — es una app normal con Dock icon.
Si la abriste con `swift run` directo (sin el `.app`), perdés el Dock
icon porque no hay bundle.  Usá `open ~/Applications/WorklogCalendar.app`.
