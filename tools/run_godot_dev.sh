#!/usr/bin/env bash
# Launch Skyval in the Godot editor without importing PortMaster/LPC build outputs.
# Usage: bash tools/run_godot_dev.sh
# Set SKYVAL_LPC_ROOT=/absolute/path/to/spritesheets for a custom LPC library.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/dist"
touch "$ROOT/dist/.gdignore"

GODOT="${GODOT_BIN:-}"
if [ -z "$GODOT" ]; then
    for candidate in \
        "$HOME/Godot/res/Godot_v4.7.2-stable_linux.x86_64" \
        "$HOME/Godot/Godot_v4.7.2-stable_linux.x86_64" \
        "$(command -v godot 2>/dev/null || true)" \
        "$(command -v godot4 2>/dev/null || true)"; do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            GODOT="$candidate"
            break
        fi
    done
fi
if [ -z "$GODOT" ] || [ ! -x "$GODOT" ]; then
    echo "ERROR: Godot not found; set GODOT_BIN to your executable." >&2
    exit 1
fi

if [ -n "${SKYVAL_LPC_ROOT:-}" ]; then
    LPC_ROOT="$SKYVAL_LPC_ROOT"
    if [ ! -s "$LPC_ROOT/body/bodies/male/light.png" ]; then
        echo "ERROR: SKYVAL_LPC_ROOT is not a spritesheets directory: $LPC_ROOT" >&2
        exit 1
    fi
else
    LPC_ROOT=""
    for candidate in \
        "$ROOT/dist/portmaster/roms/ports/skyval/resources/lpc" \
        "$ROOT/dist/portmaster/update/roms/ports/skyval/resources/lpc" \
        "$HOME/Godot/res/assets/lpc_sprites" \
        "$HOME/Godot/res/assets/lpc_sprites/spritesheets" \
        "$HOME/Godot/res/assets/lpc_sprites/resources/spritesheets" \
        "$HOME/Godot/res/addons/Universal_LPC/resources/spritesheets" \
        "$HOME/Godot/res/addons/universal_lpc/resources/spritesheets"; do
        if [ -s "$candidate/body/bodies/male/light.png" ]; then
            LPC_ROOT="$candidate"
            break
        fi
    done
fi

if [ -z "$LPC_ROOT" ]; then
    echo "ERROR: LPC spritesheets could not be located." >&2
    echo "Set SKYVAL_LPC_ROOT=/absolute/path/to/spritesheets and rerun." >&2
    exit 1
fi

LPC_ROOT="$(realpath "$LPC_ROOT")"
# Two original right-hand sword attack PNGs from the published LPC library.
# Only fetch when missing, and validate BEFORE moving into the source tree.
UPSTREAM="https://raw.githubusercontent.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator/master/spritesheets/weapon/sword/arming/attack_backslash"
for part in bg fg; do
    target="$LPC_ROOT/weapon/sword/arming/attack_backslash/$part/iron.png"
    if [ -s "$target" ]; then
        continue
    fi
    if ! command -v curl >/dev/null 2>&1; then
        echo "ERROR: missing 1-Handed Slash PNG and curl is unavailable: $target" >&2
        exit 1
    fi
    echo "Installing missing original LPC right-hand sword animation: $part"
    mkdir -p "$(dirname "$target")"
    temporary="$(mktemp)"
    if ! curl --fail --location --silent --show-error --retry 2 --connect-timeout 10 \
        "$UPSTREAM/$part/iron.png" -o "$temporary"; then
        rm -f "$temporary"
        exit 1
    fi
    if ! python3 - "$temporary" <<'CHECK_PNG'
from pathlib import Path
import struct
import sys
data = Path(sys.argv[1]).read_bytes()
valid = len(data) >= 24 and data[:8] == bytes((137,80,78,71,13,10,26,10)) and data[12:16] == b"IHDR"
if valid:
    width, height = struct.unpack(">II", data[16:24])
    valid = width == 1664 and height == 512
if not valid:
    sys.exit("ERROR: invalid LPC one-handed sword PNG")
CHECK_PNG
    then
        rm -f "$temporary"
        exit 1
    fi
    mv -f -- "$temporary" "$target"
done

echo "Skyval LPC: $LPC_ROOT"
echo "Godot build output ignored: $ROOT/dist/.gdignore"
echo "Launching editor. The LPC library is read from disk, not imported."
export SKYVAL_LPC_ROOT="$LPC_ROOT"
exec "$GODOT" --editor --path "$ROOT" "$@"
