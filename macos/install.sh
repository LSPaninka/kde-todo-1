#!/usr/bin/env bash
# Build & install CategorizedToDo.app
#
# Modes:
#   ./install.sh              build (release) and install to ~/Applications
#   ./install.sh --system     install to /Applications (needs sudo)
#   ./install.sh --launch     also start the app and add it to "Login Items"
#                             so it auto-starts on next login
#   ./install.sh --uninstall  remove the installed copy and the LaunchAgent
#
# Files touched:
#   ~/Applications/CategorizedToDo.app
#   ~/Library/LaunchAgents/com.categorizedtodo.app.plist  (with --launch)
#   ~/Library/Application Support/CategorizedToDo/data.json  (created on first run)

set -euo pipefail

DESTINATION="$HOME/Applications"
LAUNCH=0
UNINSTALL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --system)    DESTINATION="/Applications"; shift ;;
        --launch)    LAUNCH=1;                    shift ;;
        --uninstall) UNINSTALL=1;                 shift ;;
        -h|--help)
            grep '^# ' "$0" | sed 's/^# //'
            exit 0 ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1 ;;
    esac
done

cd "$(dirname "$0")"

APP_NAME="CategorizedToDo.app"
INSTALLED="$DESTINATION/$APP_NAME"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.categorizedtodo.app.plist"

# ---- Uninstall ---------------------------------------------------------------

if [[ $UNINSTALL -eq 1 ]]; then
    echo "Removing $INSTALLED ..."
    if [[ -d "$INSTALLED" ]]; then
        if [[ "$DESTINATION" == "/Applications" ]]; then
            sudo rm -rf "$INSTALLED"
        else
            rm -rf "$INSTALLED"
        fi
    fi

    if [[ -f "$LAUNCH_AGENT" ]]; then
        echo "Removing LaunchAgent ..."
        launchctl unload "$LAUNCH_AGENT" 2>/dev/null || true
        rm -f "$LAUNCH_AGENT"
    fi

    pkill -x CategorizedToDo 2>/dev/null || true
    echo "Done."
    exit 0
fi

# ---- Build -------------------------------------------------------------------

./build.sh --release

mkdir -p "$DESTINATION"

# ---- Install -----------------------------------------------------------------

# If the app is already running, stop it before replacing the bundle.
if pgrep -x CategorizedToDo >/dev/null 2>&1; then
    echo "Stopping existing CategorizedToDo ..."
    pkill -x CategorizedToDo || true
    sleep 1
fi

echo "Installing to $INSTALLED ..."
if [[ "$DESTINATION" == "/Applications" ]]; then
    sudo rm -rf "$INSTALLED"
    sudo cp -R "build/$APP_NAME" "$INSTALLED"
else
    rm -rf "$INSTALLED"
    cp -R "build/$APP_NAME" "$INSTALLED"
fi

echo "Installed."

# ---- Launch / autostart ------------------------------------------------------

if [[ $LAUNCH -eq 1 ]]; then
    mkdir -p "$HOME/Library/LaunchAgents"

    cat > "$LAUNCH_AGENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.categorizedtodo.app</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALLED/Contents/MacOS/CategorizedToDo</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><false/>
    <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
EOF

    launchctl unload "$LAUNCH_AGENT" 2>/dev/null || true
    launchctl load   "$LAUNCH_AGENT"

    echo "LaunchAgent installed: will auto-start on login."
    open "$INSTALLED"
fi

echo ""
echo "All done."
echo ""
echo "  Launch now:   open \"$INSTALLED\""
echo "  Auto-start:   ./install.sh --launch"
echo "  Uninstall:    ./install.sh --uninstall"
