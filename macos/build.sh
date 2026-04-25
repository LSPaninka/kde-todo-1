#!/usr/bin/env bash
# Build CategorizedToDo.app from sources using Swift Package Manager.
#
# Output: ./build/CategorizedToDo.app
#
# Requirements:
#   - macOS 14 or newer (designed and tested on macOS 26 "Tahoe").
#   - Xcode 15+ command line tools (swift >= 5.10).
#
# Flags:
#   --release      build in release mode (default)
#   --debug        build in debug mode
#   --arch <arch>  arm64 | x86_64 (default: native)
#   --universal    build a universal arm64 + x86_64 binary
#   --clean        wipe ./build and .build before building

set -euo pipefail

CONFIG="release"
ARCH=""
UNIVERSAL=0
CLEAN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --release)   CONFIG="release"; shift ;;
        --debug)     CONFIG="debug";   shift ;;
        --arch)      ARCH="$2";        shift 2 ;;
        --universal) UNIVERSAL=1;      shift ;;
        --clean)     CLEAN=1;          shift ;;
        -h|--help)
            grep '^# ' "$0" | sed 's/^# //'
            exit 0 ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1 ;;
    esac
done

cd "$(dirname "$0")"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Error: this script must be run on macOS." >&2
    exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
    echo "Error: swift not found. Install Xcode or the command line tools." >&2
    exit 1
fi

if [[ $CLEAN -eq 1 ]]; then
    rm -rf build .build
fi

mkdir -p build

# ---- Build the executable ----------------------------------------------------

SWIFT_BUILD_FLAGS=( --configuration "$CONFIG" )

if [[ $UNIVERSAL -eq 1 ]]; then
    SWIFT_BUILD_FLAGS+=( --arch arm64 --arch x86_64 )
elif [[ -n "$ARCH" ]]; then
    SWIFT_BUILD_FLAGS+=( --arch "$ARCH" )
fi

echo ">> swift build ${SWIFT_BUILD_FLAGS[*]}"
swift build "${SWIFT_BUILD_FLAGS[@]}"

BIN_PATH="$(swift build "${SWIFT_BUILD_FLAGS[@]}" --show-bin-path)"
EXEC="$BIN_PATH/CategorizedToDo"

if [[ ! -x "$EXEC" ]]; then
    echo "Error: built executable not found at $EXEC" >&2
    exit 1
fi

# ---- Assemble the .app bundle ------------------------------------------------

APP="build/CategorizedToDo.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$EXEC"                              "$APP/Contents/MacOS/CategorizedToDo"
cp "Sources/CategorizedToDo/Resources/Info.plist" "$APP/Contents/Info.plist"

chmod +x "$APP/Contents/MacOS/CategorizedToDo"

# Ad-hoc sign so Gatekeeper doesn't complain about an unsigned binary on
# the local machine. Replace with your developer identity if you have one.
if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
fi

echo ""
echo "Built: $APP"
echo ""
echo "Run it with:    open $APP"
echo "Install it with: ./install.sh"
