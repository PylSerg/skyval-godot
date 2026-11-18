#!/usr/bin/env bash
# Build Skyval for PortMaster from the Git checkout (Linux desktop).
# Full mode selects the LPC PNGs that Skyval ACTUALLY uses, outside the PCK.
# Later --code-only builds replace only the launcher/PCK, preserving SD assets.
# This script never alters source project files or on-console saves.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist/portmaster"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/skyval-port-XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

MODE="full"
case "${1:-}" in
    ""|--full-assets) MODE="full" ;;
    --code-only|--no-assets) MODE="code" ;;
    *)
        echo "Usage: bash tools/build_portmaster.sh [--full-assets|--code-only]"
        echo "  (default) --full-assets: ship only currently used LPC PNGs"
        echo "            --code-only: update PCK/launcher without recopying art"
        exit 2
        ;;
esac

# Never reuse the FULL install's large asset folder for code-only builds.
# This dedicated UPDATE directory contains just three small files,
# so copying its roms/ports/ tree cannot overwrite 45,000 LPC sprites.
if [ "$MODE" = "code" ]; then
    OUTPUT_PORTS="$DIST/update/roms/ports"
else
    OUTPUT_PORTS="$DIST/roms/ports"
fi

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
    echo "ERROR: Godot editor not found. Set GODOT_BIN=/full/path/to/Godot_...x86_64"
    exit 1
fi

echo "Godot editor: $GODOT"
"$GODOT" --version

# Stage code and UI art only. Selected LPC sprites are kept OUTSIDE the
# PCK so Godot does not reimport the original ~900MB library every build.
for source_file in project.godot export_presets.cfg icon.svg; do
    cp "$ROOT/$source_file" "$STAGE/"
done

# The staged build uses the same native-controller code as desktop.
# GPtoKEYB has no gamepad-to-keyboard mapping in the launcher.

for subdir in prototype characters ui localization inventory world game; do
    cp -R "$ROOT/$subdir" "$STAGE/$subdir"
done

# Include EVERY UI background/image in Git automatically. New art added
# under assets/images/ will then appear in the PCK without script edits.
if [ -d "$ROOT/assets/images" ]; then
    mkdir -p "$STAGE/assets/images"
    cp -R "$ROOT/assets/images/." "$STAGE/assets/images/"
fi
for required_image in title_bg.jpg create_hero_bg.jpg; do
    if [ ! -s "$STAGE/assets/images/$required_image" ]; then
        echo "WARNING: expected Skyval screen background missing: $required_image"
    fi
done

# Prefer the static Cascadia Mono Regular from the connected asset library.
# Copy only the font actually used by the creator, not the old Cascadia.ttf.
FONT_SOURCE="${SKYVAL_FONT_PATH:-}"
if [ -z "$FONT_SOURCE" ]; then
    for candidate in \
        "$ROOT/assets/fonts/CascadiaMono-Regular.ttf" \
        "$HOME/Downloads/Cascadia_Mono/static/CascadiaMono-Regular.ttf" \
        "$HOME/Cascadia_Mono/static/CascadiaMono-Regular.ttf" \
        "$HOME/Godot/res/assets/fonts/CascadiaMono-Regular.ttf"; do
        if [ -f "$candidate" ]; then
            FONT_SOURCE="$candidate"
            break
        fi
    done
fi
if [ -n "$FONT_SOURCE" ] && [ -f "$FONT_SOURCE" ]; then
    mkdir -p "$STAGE/assets/fonts"
    cp "$FONT_SOURCE" "$STAGE/assets/fonts/CascadiaMono-Regular.ttf"
    if [ -f "$ROOT/assets/fonts/OFL-CascadiaMono.txt" ]; then
        cp "$ROOT/assets/fonts/OFL-CascadiaMono.txt" "$STAGE/assets/fonts/OFL-CascadiaMono.txt"
    fi
    echo "Bundling Cascadia Mono Regular font: $FONT_SOURCE"
else
    echo "NOTE: CascadiaMono-Regular.ttf not found; Godot default UI font will be used."
fi

# Locate the original LPC source for the one-time SELECTED-ASSETS pack.
# Prefer the Universal LPC addon over older tiny smoke-test fragments.
LPC_SOURCE=""
if [ "$MODE" = "full" ]; then
    if [ -n "${LPC_SPRITES_ROOT:-}" ]; then
        LPC_SOURCE="${LPC_SPRITES_ROOT%/}"
        if [ ! -s "$LPC_SOURCE/body/bodies/male/light.png" ]; then
            echo "ERROR: LPC_SPRITES_ROOT must contain body/bodies/male/light.png: $LPC_SOURCE"
            exit 1
        fi
    else
        SOURCE_CANDIDATES=(
            "$HOME/Godot/res/addons/Universal_LPC/resources/spritesheets"
            "$HOME/Godot/res/addons/universal_lpc/resources/spritesheets"
            "$HOME/Godot/res/addons/Godot_LPC_Spritesheet/resources/spritesheets"
            "$HOME/Godot/res/assets/lpc_sprites/resources/spritesheets"
            "$HOME/Godot/res/assets/lpc_sprites/spritesheets"
            "$HOME/Godot/res/assets/lpc_sprites"
            "$ROOT/assets/lpc_sprites"
        )
        for candidate in "${SOURCE_CANDIDATES[@]}"; do
            if [ -s "$candidate/body/bodies/male/light.png" ]; then
                LPC_SOURCE="$candidate"
                break
            fi
        done
    fi
    if [ -z "$LPC_SOURCE" ]; then
        echo "ERROR: LPC sprite source library not found."
        echo "Set LPC_SPRITES_ROOT=/absolute/path/to/spritesheets and rerun."
        echo "No incomplete asset package will be created."
        exit 1
    fi
    for required in \
        body/bodies/male/light.png \
        body/bodies/female/light.png \
        head/heads/human/male/light.png \
        head/heads/human/female/light.png; do
        if [ ! -s "$LPC_SOURCE/$required" ]; then
            echo "ERROR: essential LPC sheet missing: $required"
            echo "Source: $LPC_SOURCE"
            exit 1
        fi
    done
    echo "Skyval LPC source: $LPC_SOURCE"
    for part in eyes hair legs feet torso/clothes torso/armour; do
        if [ ! -d "$LPC_SOURCE/$part" ]; then
            echo "WARNING: LPC category absent in source: $part"
        fi
    done
else
    echo "Code-only build: LPC resources on the SD card will NOT be replaced."
    echo "Use --full-assets once before installing code-only updates."
fi

echo "Importing the staged project..."
"$GODOT" --headless --path "$STAGE" --import

if [ "$MODE" = "code" ]; then
    # Remove *only* stale generated update files, never the full LPC tree.
    # Do this after the Godot import so a failed preflight leaves last
    # successful package intact until we're ready to export.
    rm -rf "$DIST/update/roms/ports"
fi
mkdir -p "$OUTPUT_PORTS/skyval"
PACK="$OUTPUT_PORTS/skyval/skyval.pck"
echo "Exporting data pack..."
"$GODOT" --headless --path "$STAGE" --export-pack "Skyval PCK" "$PACK"
if [ ! -s "$PACK" ]; then
    echo "ERROR: PCK missing. Check Godot export templates (Editor > Manage Export Templates)."
    exit 1
fi

# Package only the LPC paths reachable from Skyval's current avatar
# appearance options and inventory catalog, plus fallback colors for the
# three implemented armor types. The selection script reads game sources
# directly, so later items are picked up without editing this shell file.
# Keep files separate from the PCK for fast future code-only updates.
LPC_OUTPUT="$OUTPUT_PORTS/skyval/resources/lpc"
if [ "$MODE" = "full" ]; then
    echo "Collecting only currently used LPC images (one-time SD transfer)..."
    mkdir -p "$(dirname "$LPC_OUTPUT")"
    # A fresh destination is mandatory: eliminate unused PNGs left over
    # from the previous accidental all-library packaging.
    rm -rf "$LPC_OUTPUT"
    mkdir -p "$LPC_OUTPUT"
    python3 "$ROOT/tools/collect_lpc_assets.py" \
        --source "$LPC_SOURCE" \
        --destination "$LPC_OUTPUT" \
        --renderer "$ROOT/characters/lpc_body_visual.gd" \
        --inventory "$ROOT/inventory/inventory_state.gd"
    echo "Selected LPC folder size:"
    du -sh "$LPC_OUTPUT"
fi

cp "$ROOT/portmaster/Skyval.sh" "$OUTPUT_PORTS/Skyval.sh"
# Prevent leftovers from older keyboard-emulation builds.
rm -f "$OUTPUT_PORTS/skyval/skyval.gptk"
chmod +x "$OUTPUT_PORTS/Skyval.sh"

cat > "$OUTPUT_PORTS/skyval/README.txt" <<'EOF'
Skyval / PortMaster. Requires godot_4.7.1 and weston_pkg_0.2 (aarch64).
FIRST INSTALL: use Skyval_PortMaster_Full.zip with selected resources/lpc.
FUTURE UPDATES: use Skyval_PortMaster_Update.zip (launcher and PCK only).
LPC_SELECTED_ASSETS.txt lists the included images and any unavailable variants.
Unzip into roms/ports/, replacing files but NEVER deleting skyval/saves/
or skyval/conf/. Old skyval.gptk is not required.
Retain and audit original Universal LPC sprite licenses/credits before sharing.
Source: https://github.com/PylSerg/skyval-godot
Log after launching: roms/ports/skyval/log.txt
EOF

# Delete the old 14-sprite smoke-test archive so nobody installs it by
# mistake after producing the new complete/full/update packages.
rm -f "$DIST/Skyval_PortMaster_Test.zip"
if command -v zip >/dev/null 2>&1; then
    # ZIP stores already-compressed PNGs without another expensive pass.
    # Each build removes the previous named archive to avoid stale files.
    if [ "$MODE" = "full" ]; then
        ARCHIVE="$DIST/Skyval_PortMaster_Full.zip"
    else
        ARCHIVE="$DIST/Skyval_PortMaster_Update.zip"
    fi
    rm -f "$ARCHIVE"
    (
        cd "$OUTPUT_PORTS"
        if [ "$MODE" = "full" ]; then
            zip -q -r -0 "$ARCHIVE" "Skyval.sh" "skyval/skyval.pck" \
                "skyval/README.txt" "skyval/resources/lpc" \
                "skyval/resources/LPC_SELECTED_ASSETS.txt"
        else
            zip -q -r -0 "$ARCHIVE" "Skyval.sh" "skyval/skyval.pck" \
                "skyval/README.txt"
        fi
    )
    echo "READY: $ARCHIVE"
else
    echo "zip not found; files are in: $OUTPUT_PORTS/"
fi
if [ "$MODE" = "full" ]; then
    echo "FIRST INSTALL: copy Skyval.sh, skyval.pck and selected resources/lpc/ to roms/ports/."
else
    echo "UPDATE: copy the clean directory $OUTPUT_PORTS/ to the SD card's roms/ports/."
    echo "It contains only Skyval.sh, skyval.pck and README.txt. KEEP resources/lpc/ on SD."
fi
echo "NEVER delete the existing skyval/saves/ directory on the SD card."
echo "Launch via EmulationStation > Ports; diagnostics: skyval/log.txt."
