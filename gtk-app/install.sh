#!/usr/bin/env bash
#
# install.sh — build & install the GTK 4 / libadwaita Categorized ToDo app
# (Vala) on Ubuntu 24.04. Wraps meson/ninja.
#
#   ./install.sh                 # user install into ~/.local (no sudo)
#   ./install.sh --system        # system install into /usr (uses sudo)
#   ./install.sh --prefix DIR    # install into a custom prefix
#   ./install.sh --no-deps       # skip the apt dependency check
#   ./install.sh --uninstall     # uninstall (same prefix as the last build)
#   ./install.sh --run           # build, install (user) and launch
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

PREFIX="$HOME/.local"
USE_SUDO=""
CHECK_DEPS=1
DO_UNINSTALL=0
DO_RUN=0

# Build-time packages needed on Ubuntu 24.04.
REQUIRED_PKGS=(
  valac meson ninja-build build-essential pkg-config
  libgtk-4-dev libadwaita-1-dev libsoup-3.0-dev
  libjson-glib-dev libsqlite3-dev libgee-0.8-dev
)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --system)    PREFIX="/usr"; USE_SUDO="sudo"; shift ;;
    --prefix)    PREFIX="$2"; shift 2 ;;
    --no-deps)   CHECK_DEPS=0; shift ;;
    --uninstall) DO_UNINSTALL=1; shift ;;
    --run)       DO_RUN=1; shift ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -20
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# System prefixes need sudo for the install step.
if [[ "$PREFIX" == "/usr" || "$PREFIX" == "/usr/local" ]]; then
  USE_SUDO="sudo"
fi

check_deps() {
  [[ "$CHECK_DEPS" -eq 1 ]] || return 0
  local missing=()
  for p in "${REQUIRED_PKGS[@]}"; do
    dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Faltan dependencias de compilación:"
    printf '  - %s\n' "${missing[@]}"
    echo
    read -r -p "¿Instalarlas con apt ahora? [S/n] " ans
    if [[ -z "$ans" || "$ans" =~ ^[SsYy]$ ]]; then
      sudo apt-get update
      sudo apt-get install -y "${missing[@]}"
    else
      echo "Instalalas manualmente y reintentá, o usá --no-deps." >&2
      exit 1
    fi
  fi
}

if [[ "$DO_UNINSTALL" -eq 1 ]]; then
  if [[ ! -d build ]]; then
    echo "No hay un directorio build/. Nada que desinstalar." >&2
    exit 1
  fi
  $USE_SUDO ninja -C build uninstall
  echo "Desinstalado."
  exit 0
fi

check_deps

echo ">> Configurando (prefix=$PREFIX)…"
if [[ -d build ]]; then
  meson setup --reconfigure build --prefix "$PREFIX"
else
  meson setup build --prefix "$PREFIX"
fi

echo ">> Compilando…"
ninja -C build

echo ">> Instalando…"
$USE_SUDO ninja -C build install

# For a user install, make sure the GSettings schema is compiled where the
# app will look for it (meson's post-install does this, but re-run to be safe).
if [[ "$PREFIX" == "$HOME/.local" ]]; then
  glib-compile-schemas "$PREFIX/share/glib-2.0/schemas" 2>/dev/null || true
  gtk4-update-icon-cache -q -t -f "$PREFIX/share/icons/hicolor" 2>/dev/null || true
fi

echo
echo "Listo. Ejecutable: $PREFIX/bin/categorized-todo"
echo "Lanzá 'categorized-todo' (o buscá «Categorized ToDo» en tu menú de apps)."
if [[ "$PREFIX" == "$HOME/.local" ]]; then
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) : ;;
    *) echo "Nota: agregá \$HOME/.local/bin a tu PATH." ;;
  esac
fi

if [[ "$DO_RUN" -eq 1 ]]; then
  exec "$PREFIX/bin/categorized-todo"
fi
