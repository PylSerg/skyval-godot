#!/usr/bin/env bash
# Copy the locally owned Cascadia font into the Skyval project.
# No network access; does not stage or commit Git changes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${1:-${SKYVAL_FONT_PATH:-$HOME/Godot/res/assets/fonts/Cascadia.ttf}}"
TARGET="$ROOT/assets/fonts/Cascadia.ttf"

if [ ! -s "$SOURCE" ]; then
    echo "ERROR: Cascadia.ttf not found: $SOURCE"
    echo "Usage: bash tools/install_cascadia.sh [/full/path/to/Cascadia.ttf]"
    exit 1
fi

mkdir -p "$(dirname "$TARGET")"
if [ "$(realpath "$SOURCE")" != "$(realpath -m "$TARGET")" ]; then
    cp "$SOURCE" "$TARGET"
fi
echo "Project font installed: $TARGET"
echo "Godot will import it when the project opens."
echo "To track in GitHub, run: git add assets/fonts/Cascadia.ttf; git commit; git push"
