#!/usr/bin/env bash
# install.sh - install / update / uninstall the Categorized ToDo plasmoid
# for the current user on Kubuntu 24.04 (KDE Plasma 5.27 + Qt 5.15).
#
# Usage:
#   ./install.sh             # install (or upgrade if already installed)
#   ./install.sh --uninstall # remove the plasmoid
#   ./install.sh --dev       # symlink the package (for live development)
#   ./install.sh --no-deps   # skip the apt dependency check
#
# Requires `plasmapkg2` (or `kpackagetool5`), provided by plasma-framework.
# Also depends on the Qt QML module `QtQuick.LocalStorage`, which on
# Debian/Ubuntu is the package `qml-module-qtquick-localstorage`. The
# script offers to install it if missing.

set -euo pipefail

PLUGIN_ID="org.kde.plasma.categorizedtodo"
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/package" && pwd)"

# Required QML modules. Map: <import URI> -> <Debian/Ubuntu package>.
# These are checked by looking for the qmldir file inside Qt's QML import
# paths, which is more reliable than dpkg (works with non-Debian systems
# too, where we just print a warning).
declare -A REQUIRED_QML_MODULES=(
    ["QtQuick/LocalStorage"]="qml-module-qtquick-localstorage"
    ["QtQuick/Controls.2"]="qml-module-qtquick-controls2"
    ["Qt/labs/platform"]="qml-module-qt-labs-platform"
)

MODE="install"
SKIP_DEPS=0
for arg in "$@"; do
    case "$arg" in
        --uninstall) MODE="uninstall" ;;
        --dev)       MODE="dev" ;;
        --no-deps)   SKIP_DEPS=1 ;;
        -h|--help)
            grep '^#' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "Unknown arg: $arg" >&2; exit 1 ;;
    esac
done

have_cmd() { command -v "$1" >/dev/null 2>&1; }

# Print the standard QML import paths for Qt 5 across distros.
qml_import_paths() {
    local p
    for p in \
        /usr/lib/x86_64-linux-gnu/qt5/qml \
        /usr/lib/aarch64-linux-gnu/qt5/qml \
        /usr/lib/qt5/qml \
        /usr/lib64/qt5/qml \
        /usr/lib/qt/qml \
    ; do
        [ -d "$p" ] && echo "$p"
    done
}

# Returns 0 if the QML module is present, 1 otherwise.
qml_module_present() {
    local mod="$1"
    for base in $(qml_import_paths); do
        if [ -f "$base/$mod/qmldir" ]; then
            return 0
        fi
    done
    return 1
}

check_qml_dependencies() {
    local missing_pkgs=()
    local missing_mods=()
    for mod in "${!REQUIRED_QML_MODULES[@]}"; do
        if ! qml_module_present "$mod"; then
            missing_mods+=("$mod")
            missing_pkgs+=("${REQUIRED_QML_MODULES[$mod]}")
        fi
    done

    if [ "${#missing_mods[@]}" -eq 0 ]; then
        echo "All required QML modules are present."
        return 0
    fi

    echo "Missing QML modules:"
    for m in "${missing_mods[@]}"; do echo "  - $m"; done

    if have_cmd apt-get; then
        echo
        echo "On Debian/Ubuntu these are provided by:"
        for p in "${missing_pkgs[@]}"; do echo "  - $p"; done
        echo
        read -r -p "Install them now with sudo apt install? [Y/n] " yn
        case "${yn:-Y}" in
            [Nn]*)
                echo "Skipping. The plasmoid will fail to load until they are installed."
                ;;
            *)
                sudo apt-get update
                sudo apt-get install -y "${missing_pkgs[@]}"
                ;;
        esac
    elif have_cmd dnf; then
        echo
        echo "On Fedora try: sudo dnf install qt5-qtdeclarative qt5-qtquickcontrols2"
    elif have_cmd pacman; then
        echo
        echo "On Arch try: sudo pacman -S qt5-declarative qt5-quickcontrols2"
    else
        echo
        echo "Install the equivalent packages for your distribution before continuing."
    fi
}

# Prefer `kpackagetool5`; fall back to `plasmapkg2` if only that is installed.
if have_cmd kpackagetool5; then
    TOOL=(kpackagetool5 -t Plasma/Applet)
elif have_cmd plasmapkg2; then
    TOOL=(plasmapkg2 -t Plasma/Applet)
else
    echo "Neither kpackagetool5 nor plasmapkg2 is available." >&2
    echo "Install 'plasma-framework' or make sure you're on KDE Plasma." >&2
    exit 1
fi

echo "Using: ${TOOL[*]}"
echo "Package directory: $PKG_DIR"
echo "Plugin id: $PLUGIN_ID"

# Dependency check (skip on uninstall and when --no-deps was passed).
if [ "$MODE" != "uninstall" ] && [ "$SKIP_DEPS" -ne 1 ]; then
    echo
    echo "--- Checking QML dependencies ---"
    check_qml_dependencies
    echo
fi

case "$MODE" in
    install)
        if "${TOOL[@]}" --list 2>/dev/null | grep -q "^$PLUGIN_ID$"; then
            echo "Upgrading existing installation…"
            "${TOOL[@]}" --upgrade "$PKG_DIR"
        else
            echo "Installing…"
            "${TOOL[@]}" --install "$PKG_DIR"
        fi
        ;;
    uninstall)
        echo "Uninstalling…"
        "${TOOL[@]}" --remove "$PLUGIN_ID"
        ;;
    dev)
        TARGET="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/$PLUGIN_ID"
        mkdir -p "$(dirname "$TARGET")"
        rm -rf "$TARGET"
        ln -s "$PKG_DIR" "$TARGET"
        echo "Symlinked: $TARGET -> $PKG_DIR"
        ;;
esac

echo
echo "Done. To apply changes in a running Plasma session:"
echo "  kquitapp5 plasmashell && kstart5 plasmashell"
echo
echo "Add the widget with: right-click desktop -> Add Widgets -> search \"ToDo\"."
