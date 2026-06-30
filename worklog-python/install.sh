#!/usr/bin/env bash
#
# install.sh - build & install the Worklog Calendar (Python/PyGObject) app on
# Ubuntu 24.04.
#
#   ./install.sh                # install into ~/.local (per-user, no root)
#   ./install.sh --system       # install into /usr (needs sudo)
#   ./install.sh --deps         # apt-install the runtime dependencies
#   ./install.sh --run          # install + launch
#   ./install.sh --uninstall    # remove a per-user install
#
# This is a pure-Python app: there is no compile step. Meson just copies the
# package, generates the launcher and registers the schema / desktop / icons.

set -euo pipefail

APP_ID="io.github.peperina.WorklogCalendarPy"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"

PREFIX="$HOME/.local"
USE_SUDO=""
DO_DEPS=0
DO_RUN=0
DO_UNINSTALL=0

for arg in "$@"; do
  case "$arg" in
    --system)    PREFIX="/usr"; USE_SUDO="sudo" ;;
    --deps)      DO_DEPS=1 ;;
    --run)       DO_RUN=1 ;;
    --uninstall) DO_UNINSTALL=1 ;;
    -h|--help)   sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "Argumento desconocido: $arg"; exit 1 ;;
  esac
done

# Runtime deps: PyGObject + the GTK4/Adwaita typelibs. No HTTP/JSON libs needed
# (the app uses the Python standard library). The appindicator extension renders
# the top-bar clock on GNOME.
PKGS=(meson ninja-build
      python3-gi python3-gi-cairo gir1.2-gtk-4.0 gir1.2-adw-1
      gnome-shell-extension-appindicator)

install_deps() {
  echo ">> Instalando dependencias con apt…"
  sudo apt-get update
  sudo apt-get install -y "${PKGS[@]}"
}

uninstall() {
  echo ">> Desinstalando de $PREFIX…"
  rm -f  "$PREFIX/bin/$APP_ID"
  rm -rf "$PREFIX/share/$APP_ID"
  rm -f  "$PREFIX/share/applications/$APP_ID.desktop"
  rm -f  "$PREFIX/share/glib-2.0/schemas/$APP_ID.gschema.xml"
  rm -f  "$PREFIX/share/icons/hicolor/scalable/apps/$APP_ID.svg"
  rm -f  "$PREFIX/share/icons/hicolor/symbolic/apps/$APP_ID-symbolic.svg"
  glib-compile-schemas "$PREFIX/share/glib-2.0/schemas" 2>/dev/null || true
  gtk4-update-icon-cache -q "$PREFIX/share/icons/hicolor" 2>/dev/null || true
  echo ">> Listo."
}

if [[ $DO_DEPS -eq 1 ]]; then install_deps; fi
if [[ $DO_UNINSTALL -eq 1 ]]; then uninstall; exit 0; fi

echo ">> Configurando (prefix: $PREFIX)…"
if [[ ! -d "$BUILD_DIR" ]]; then
  meson setup "$BUILD_DIR" --prefix "$PREFIX"
else
  meson setup --reconfigure "$BUILD_DIR" --prefix "$PREFIX"
fi

echo ">> Instalando…"
$USE_SUDO meson install -C "$BUILD_DIR"

$USE_SUDO glib-compile-schemas "$PREFIX/share/glib-2.0/schemas" 2>/dev/null || true
$USE_SUDO gtk4-update-icon-cache -q -t "$PREFIX/share/icons/hicolor" 2>/dev/null || true

echo ">> Instalado: $PREFIX/bin/$APP_ID"
echo "   Ejecutá '$APP_ID' o buscá 'Worklog Calendar (Python)' en el menú."
echo "   En GNOME/Ubuntu activá la extensión 'Ubuntu AppIndicators' para ver"
echo "   el reloj en la barra superior."

if [[ $DO_RUN -eq 1 ]]; then
  echo ">> Lanzando…"
  exec "$PREFIX/bin/$APP_ID"
fi
