#!/usr/bin/env bash
# tools/make-app-icon.sh
#
# Genera Sources/WorklogCalendar/Resources/AppIcon.icns a partir de un
# PNG 1024×1024 (lo dibuja `make-app-icon.swift`) y lo empaqueta con
# `iconutil`.  Si querés usar tu propio ícono, dropealo directamente
# como AppIcon.icns en esa ruta y `build.sh` lo va a respetar.

set -euo pipefail
TOOLS="$(cd "$(dirname "$0")" && pwd)"
ROOT="$TOOLS/.."

RES="$ROOT/Sources/WorklogCalendar/Resources"
ICNS="$RES/AppIcon.icns"
SRC_PNG="$TOOLS/AppIcon-1024.png"
ICONSET="$TOOLS/AppIcon.iconset"

mkdir -p "$RES"

echo "==> Renderizando 1024×1024 (clock + flame)"
swift "$TOOLS/make-app-icon.swift" "$SRC_PNG"

echo "==> Armando iconset con todos los tamaños"
rm -rf "$ICONSET"
mkdir "$ICONSET"
sips -z   16   16  "$SRC_PNG" --out "$ICONSET/icon_16x16.png"        > /dev/null
sips -z   32   32  "$SRC_PNG" --out "$ICONSET/icon_16x16@2x.png"     > /dev/null
sips -z   32   32  "$SRC_PNG" --out "$ICONSET/icon_32x32.png"        > /dev/null
sips -z   64   64  "$SRC_PNG" --out "$ICONSET/icon_32x32@2x.png"     > /dev/null
sips -z  128  128  "$SRC_PNG" --out "$ICONSET/icon_128x128.png"      > /dev/null
sips -z  256  256  "$SRC_PNG" --out "$ICONSET/icon_128x128@2x.png"   > /dev/null
sips -z  256  256  "$SRC_PNG" --out "$ICONSET/icon_256x256.png"      > /dev/null
sips -z  512  512  "$SRC_PNG" --out "$ICONSET/icon_256x256@2x.png"   > /dev/null
sips -z  512  512  "$SRC_PNG" --out "$ICONSET/icon_512x512.png"      > /dev/null
cp                  "$SRC_PNG"       "$ICONSET/icon_512x512@2x.png"

echo "==> iconutil → .icns"
iconutil --convert icns "$ICONSET" --output "$ICNS"

rm -rf "$ICONSET" "$SRC_PNG"
echo "==> Listo: $ICNS"
