#!/usr/bin/env bash
# install.sh - install / update / uninstall the Jira Worklog Calendar
# plasmoid for the current user on Kubuntu 24.04 (KDE Plasma 5.27 + Qt 5.15).
#
# Usage:
#   ./install.sh             # install (or upgrade if already installed)
#   ./install.sh --uninstall # remove the plasmoid
#   ./install.sh --dev       # symlink the package (for live development)

set -euo pipefail

PLUGIN_ID="org.kde.plasma.jiraworklog"
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/package" && pwd)"

MODE="install"
for arg in "$@"; do
    case "$arg" in
        --uninstall) MODE="uninstall" ;;
        --dev)       MODE="dev" ;;
        -h|--help)
            grep '^#' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            exit 1
            ;;
    esac
done

if command -v kpackagetool5 >/dev/null 2>&1; then
    PKG_TOOL=kpackagetool5
    PKG_TYPE_ARG="--type Plasma/Applet"
elif command -v plasmapkg2 >/dev/null 2>&1; then
    PKG_TOOL=plasmapkg2
    PKG_TYPE_ARG="--type Plasma/Applet"
else
    echo "Error: neither kpackagetool5 nor plasmapkg2 found." >&2
    echo "Install plasma-framework / plasma-workspace and try again." >&2
    exit 1
fi

INSTALL_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids"
TARGET="$INSTALL_ROOT/$PLUGIN_ID"

case "$MODE" in
    install)
        if [[ -e "$TARGET" ]]; then
            echo ">> Upgrading existing $PLUGIN_ID"
            "$PKG_TOOL" $PKG_TYPE_ARG --upgrade "$PKG_DIR" || \
                "$PKG_TOOL" $PKG_TYPE_ARG -u "$PKG_DIR"
        else
            echo ">> Installing $PLUGIN_ID"
            "$PKG_TOOL" $PKG_TYPE_ARG --install "$PKG_DIR" || \
                "$PKG_TOOL" $PKG_TYPE_ARG -i "$PKG_DIR"
        fi
        ;;
    dev)
        mkdir -p "$INSTALL_ROOT"
        if [[ -e "$TARGET" && ! -L "$TARGET" ]]; then
            echo ">> A regular install exists; removing it before symlinking."
            "$PKG_TOOL" $PKG_TYPE_ARG --remove "$PLUGIN_ID" || \
                "$PKG_TOOL" $PKG_TYPE_ARG -r "$PLUGIN_ID" || true
            rm -rf "$TARGET"
        fi
        if [[ -L "$TARGET" ]]; then
            rm "$TARGET"
        fi
        ln -s "$PKG_DIR" "$TARGET"
        echo ">> Symlinked $TARGET -> $PKG_DIR"
        ;;
    uninstall)
        echo ">> Uninstalling $PLUGIN_ID"
        "$PKG_TOOL" $PKG_TYPE_ARG --remove "$PLUGIN_ID" || \
            "$PKG_TOOL" $PKG_TYPE_ARG -r "$PLUGIN_ID" || true
        rm -rf "$TARGET"
        ;;
esac

echo
echo "Done. Reload Plasma to pick up the change:"
echo "    kquitapp5 plasmashell && kstart5 plasmashell"
