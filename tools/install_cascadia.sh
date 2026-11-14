#!/usr/bin/env bash
# Install the user-selected static Cascadia Mono Regular into the project.
# Requires the local font file; never downloads or replaces it with another build.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${1:-${SKYVAL_FONT_PATH:-}}"
TARGET="$ROOT/assets/fonts/CascadiaMono-Regular.ttf"

if [ -z "$SOURCE" ]; then
    for candidate in \
        "$HOME/Downloads/Cascadia_Mono/static/CascadiaMono-Regular.ttf" \
        "$HOME/Cascadia_Mono/static/CascadiaMono-Regular.ttf" \
        "$HOME/Godot/res/assets/fonts/CascadiaMono-Regular.ttf"; do
        if [ -s "$candidate" ]; then
            SOURCE="$candidate"
            break
        fi
    done
fi

if [ -z "$SOURCE" ] || [ ! -s "$SOURCE" ]; then
    echo "ERROR: CascadiaMono-Regular.ttf not found."
    echo "Usage: bash tools/install_cascadia.sh /full/path/Cascadia_Mono/static/CascadiaMono-Regular.ttf"
    exit 1
fi

mkdir -p "$(dirname "$TARGET")"
if [ "$(realpath "$SOURCE")" != "$(realpath -m "$TARGET")" ]; then
    cp "$SOURCE" "$TARGET"
fi

# Keep the OFL license alongside the font when installing from the download.
LICENSE="$(dirname "$(dirname "$SOURCE")")/OFL.txt"
if [ -f "$LICENSE" ]; then
    cp "$LICENSE" "$ROOT/assets/fonts/OFL-CascadiaMono.txt"
    echo "Copied SIL OFL license."
fi
echo "Installed Cascadia Mono Regular: $TARGET"
echo "Next: git add assets/fonts/CascadiaMono-Regular.ttf assets/fonts/OFL-CascadiaMono.txt"
echo "Then commit and push the new font from your local Git checkout."
