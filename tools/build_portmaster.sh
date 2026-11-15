#!/usr/bin/env bash
# Build Skyval for PortMaster from the Git checkout (Linux desktop).
# Full mode ships the entire external LPC PNG library once, OUTSIDE the PCK.
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
        echo "  (default) --full-assets: ship all LPC PNG resources once"
        echo "            --code-only: update PCK/launcher without recopying art"
        exit 2
        ;;
esac

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

# Stage code and UI art only. The LPC tree is kept OUTSIDE the PCK,
# so Godot never imports a ~900MB library and runtime loads PNGs on demand.
for source_file in project.godot export_presets.cfg icon.svg; do
    cp "$ROOT/$source_file" "$STAGE/"
done

# The staged build uses the same native-controller code as desktop.
# GPtoKEYB has no gamepad-to-keyboard mapping in the launcher.

for subdir in prototype characters ui localization inventory world game; do
    cp -R "$ROOT/$subdir" "$STAGE/$subdir"
done

# Include the dedicated title illustration. Keep it bundled with the PCK
# even in --no-assets smoke tests (that option only skips LPC sheets).
TITLE_ART="$ROOT/assets/images/title_bg.jpg"
if [ -f "$TITLE_ART" ]; then
    mkdir -p "$STAGE/assets/images"
    cp "$TITLE_ART" "$STAGE/assets/images/title_bg.jpg"
else
    echo "NOTE: title art missing from assets/images; title falls back to dark menu."
fi

# Character creation has its own illustrated backdrop. Unlike optional LPC
# sprite sheets, this small UI asset is always included in test builds.
CREATION_ART="$ROOT/assets/images/create_hero_bg.jpg"
if [ -f "$CREATION_ART" ]; then
    mkdir -p "$STAGE/assets/images"
    cp "$CREATION_ART" "$STAGE/assets/images/create_hero_bg.jpg"
else
    echo "NOTE: creation art missing; character editor will use a plain backdrop."
fi

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

# Validate the one-time full LPC distribution source before compiling.
# Prefer the full Universal LPC addon over a partial local smoke-test set.
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
        echo "ERROR: full LPC sprite library not found."
        echo "Set LPC_SPRITES_ROOT=/absolute/path/to/spritesheets and rerun."
        echo "No incomplete full package will be created."
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
    echo "Full LPC source: $LPC_SOURCE"
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

mkdir -p "$DIST/roms/ports/skyval"
PACK="$DIST/roms/ports/skyval/skyval.pck"
echo "Exporting data pack..."
"$GODOT" --headless --path "$STAGE" --export-pack "Skyval PCK" "$PACK"
if [ ! -s "$PACK" ]; then
    echo "ERROR: PCK missing. Check Godot export templates (Editor > Manage Export Templates)."
    exit 1
fi

# Keep the complete source sprite tree in its original LPC directory layout.
# The handheld loads these PNGs directly using SKYVAL_LPC_ROOT: no
# compression into Godot's PCK, no import overhead, no RAM preloading.
# Only this output folder may be replaced; never touch any saves/ folder.
LPC_OUTPUT="$DIST/roms/ports/skyval/resources/lpc"
if [ "$MODE" = "full" ]; then
    echo "Copying complete LPC resource library (one-time SD transfer)..."
    mkdir -p "$(dirname "$LPC_OUTPUT")"
    rm -rf "$LPC_OUTPUT"
    mkdir -p "$LPC_OUTPUT"
    cp -a "$LPC_SOURCE/." "$LPC_OUTPUT/"
    for required in \
        body/bodies/male/light.png \
        body/bodies/female/light.png \
        head/heads/human/male/light.png \
        head/heads/human/female/light.png; do
        if [ ! -s "$LPC_OUTPUT/$required" ]; then
            echo "ERROR: copied LPC resources are incomplete: $required"
            exit 1
        fi
    done
    IMAGE_COUNT="$(find "$LPC_OUTPUT" -type f -iname '*.png' | wc -l)"
    if [ "$IMAGE_COUNT" -lt 14 ]; then
        echo "ERROR: only $IMAGE_COUNT PNG files found in LPC output"
        exit 1
    fi
    echo "Packed external LPC library: $IMAGE_COUNT PNGs"
    du -sh "$LPC_OUTPUT"
fi

cp "$ROOT/portmaster/Skyval.sh" "$DIST/roms/ports/Skyval.sh"
# Prevent leftovers from older keyboard-emulation builds.
rm -f "$DIST/roms/ports/skyval/skyval.gptk"
chmod +x "$DIST/roms/ports/Skyval.sh"

cat > "$DIST/roms/ports/skyval/README.txt" <<'EOF'
Skyval / PortMaster. Requires godot_4.7.1 and weston_pkg_0.2 (aarch64).
FIRST INSTALL: use Skyval_PortMaster_Full.zip, including resources/lpc.
FUTURE UPDATES: use Skyval_PortMaster_Update.zip (launcher and PCK only).
Unzip into roms/ports/, replacing files but NEVER deleting skyval/saves/
or skyval/conf/. Old skyval.gptk is not required.
Retain and audit original Universal LPC sprite licenses/credits before sharing.
Source: https://github.com/PylSerg/skyval-godot
Log after launching: roms/ports/skyval/log.txt
EOF

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
        cd "$DIST/roms/ports"
        if [ "$MODE" = "full" ]; then
            zip -q -r -0 "$ARCHIVE" "Skyval.sh" "skyval/skyval.pck" \
                "skyval/README.txt" "skyval/resources/lpc"
        else
            zip -q -r -0 "$ARCHIVE" "Skyval.sh" "skyval/skyval.pck" \
                "skyval/README.txt"
        fi
    )
    echo "READY: $ARCHIVE"
else
    echo "zip not found; files are in: $DIST/roms/ports/"
fi
if [ "$MODE" = "full" ]; then
    echo "FIRST INSTALL: copy Skyval.sh, skyval.pck and resources/lpc/ to roms/ports/."
else
    echo "UPDATE: copy only Skyval.sh and skyval.pck; KEEP resources/lpc/ on SD."
fi
echo "NEVER delete the existing skyval/saves/ directory on the SD card."
echo "Launch via EmulationStation > Ports; diagnostics: skyval/log.txt."
