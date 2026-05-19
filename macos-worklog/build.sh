#!/usr/bin/env bash
# Compila WorklogCalendar en release y arma un .app bundle ad-hoc firmado.
# Uso:
#   ./build.sh                  # build + bundle en ./build/WorklogCalendar.app
#   ./build.sh --clean          # borra ./.build y ./build antes

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

CLEAN=0
for arg in "$@"; do
    case "$arg" in
        --clean) CLEAN=1 ;;
        *) echo "Argumento desconocido: $arg" >&2; exit 1 ;;
    esac
done

if [[ $CLEAN -eq 1 ]]; then
    rm -rf .build build
fi

echo "==> swift build -c release"
swift build --configuration release

BIN_PATH="$(swift build -c release --show-bin-path)"
BIN="$BIN_PATH/WorklogCalendar"
if [[ ! -x "$BIN" ]]; then
    echo "No se encontró el binario en $BIN" >&2
    exit 1
fi

APP="$ROOT/build/WorklogCalendar.app"
echo "==> Armando bundle en $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/WorklogCalendar"
cp "$ROOT/Sources/WorklogCalendar/Resources/Info.plist" "$APP/Contents/Info.plist"

# Si en algún momento agregamos un .icns, lo metemos acá:
if [[ -f "$ROOT/Sources/WorklogCalendar/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Sources/WorklogCalendar/Resources/AppIcon.icns" \
       "$APP/Contents/Resources/AppIcon.icns"
fi

echo "==> Firma ad-hoc"
codesign --force --sign - --timestamp=none "$APP"

echo
echo "Listo:"
echo "  $APP"
echo
echo "Probalo con:  open '$APP'"
