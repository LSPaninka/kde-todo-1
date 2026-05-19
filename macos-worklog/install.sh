#!/usr/bin/env bash
# Compila Worklog Calendar y la copia a ~/Applications (default) o
# /Applications (con --system).  Con --uninstall remueve la app.
#
# Uso:
#   ./install.sh                 # build + instala en ~/Applications
#   ./install.sh --system        # instala en /Applications (pide sudo)
#   ./install.sh --uninstall     # borra de ambos
#   ./install.sh --no-build      # sólo copia (asume build/ ya armado)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

SYSTEM=0
UNINSTALL=0
SKIP_BUILD=0
for arg in "$@"; do
    case "$arg" in
        --system)    SYSTEM=1 ;;
        --uninstall) UNINSTALL=1 ;;
        --no-build)  SKIP_BUILD=1 ;;
        -h|--help)
            sed -n '2,8p' "$0"
            exit 0
            ;;
        *) echo "Argumento desconocido: $arg" >&2; exit 1 ;;
    esac
done

USER_APP="$HOME/Applications/WorklogCalendar.app"
SYS_APP="/Applications/WorklogCalendar.app"

if [[ $UNINSTALL -eq 1 ]]; then
    echo "==> Quitando $USER_APP"
    rm -rf "$USER_APP"
    if [[ -d "$SYS_APP" ]]; then
        echo "==> Quitando $SYS_APP (necesita sudo)"
        sudo rm -rf "$SYS_APP"
    fi
    echo "Listo."
    exit 0
fi

if [[ $SKIP_BUILD -eq 0 ]]; then
    "$ROOT/build.sh"
fi

APP="$ROOT/build/WorklogCalendar.app"
if [[ ! -d "$APP" ]]; then
    echo "No se encontró $APP — corré ./build.sh primero." >&2
    exit 1
fi

if [[ $SYSTEM -eq 1 ]]; then
    echo "==> Instalando en /Applications (necesita sudo)"
    sudo rm -rf "$SYS_APP"
    sudo cp -R "$APP" "$SYS_APP"
    DEST="$SYS_APP"
else
    echo "==> Instalando en ~/Applications"
    mkdir -p "$HOME/Applications"
    rm -rf "$USER_APP"
    cp -R "$APP" "$USER_APP"
    DEST="$USER_APP"
fi

echo
echo "Instalado en: $DEST"
echo "Abrilo con:   open '$DEST'"
