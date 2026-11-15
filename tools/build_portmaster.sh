#!/usr/bin/env bash
# Build a first-launch PortMaster smoke-test pack from Skyval's Git checkout.
# Run on the developer's Linux laptop. This does NOT alter the source project.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist/portmaster"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/skyval-port-XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

if [ "${1:-}" = "--no-assets" ]; then
    NO_ASSETS=1
else
    NO_ASSETS=0
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

# Copy only the code and small resources required by the smoke test.
# Never import a 900 MB external library into the main Godot project.
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
TITLE_ART="$ROOT/assets/ui/title_background.webp"
if [ -f "$TITLE_ART" ]; then
    mkdir -p "$STAGE/assets/ui"
    cp "$TITLE_ART" "$STAGE/assets/ui/title_background.webp"
else
    echo "NOTE: title art missing from assets/ui; title falls back to dark menu."
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

# Only the current default outfit, both body types, and basic face/hair.
# Missing non-default variants remain intentionally unavailable in this test.
SHEETS=(
    body/bodies/male/light.png
    head/heads/human/male/light.png
    head/faces/male/neutral/light.png
    torso/clothes/shortsleeve/shortsleeve/male/blue.png
    legs/pants/male/charcoal.png
    feet/boots/basic/male/brown.png

    body/bodies/female/light.png
    head/heads/human/female/light.png
    head/faces/female/neutral/light.png
    torso/clothes/shortsleeve/shortsleeve/female/blue.png
    legs/pants/thin/charcoal.png
    feet/boots/basic/thin/brown.png

    eyes/human/adult/default/blue.png
    hair/buzzcut/adult/black.png
)

if [ "$NO_ASSETS" -eq 0 ]; then
    # Accept an explicit LPC_SPRITES_ROOT; otherwise try known local layouts.
    ROOTS=(
        "${LPC_SPRITES_ROOT:-}"
        "$HOME/Godot/res/assets/lpc_sprites"
        "$HOME/Godot/res/assets/lpc_sprites/spritesheets"
        "$HOME/Godot/res/assets/lpc_sprites/resources/spritesheets"
        "$HOME/Godot/res/addons/Universal_LPC/resources/spritesheets"
        "$HOME/Godot/res/addons/universal_lpc/resources/spritesheets"
        "$HOME/Godot/res/addons/Godot_LPC_Spritesheet/resources/spritesheets"
    )
    FOUND=""
    for candidate in "${ROOTS[@]}"; do
        if [ -n "$candidate" ] && [ -f "$candidate/body/bodies/male/light.png" ]; then
            FOUND="$candidate"
            break
        fi
    done
    if [ -z "$FOUND" ]; then
        echo "NOTE: LPC art directory not found; packing procedural fallback only."
    else
        missing=0
        for image in "${SHEETS[@]}"; do
            if [ ! -f "$FOUND/$image" ]; then
                echo "NOTE: missing LPC test sprite: $image"
                missing=1
            fi
        done
        if [ "$missing" -eq 0 ]; then
            echo "Packing ${#SHEETS[@]} selected LPC sprites from $FOUND"
            for image in "${SHEETS[@]}"; do
                dest="$STAGE/assets/characters/lpc/$image"
                mkdir -p "$(dirname "$dest")"
                cp "$FOUND/$image" "$dest"
            done
        else
            echo "NOTE: incomplete test art set, using procedural fallback instead."
        fi
    fi
else
    echo "Explicit --no-assets mode: engine-only smoke test."
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

cp "$ROOT/portmaster/Skyval.sh" "$DIST/roms/ports/Skyval.sh"
# Prevent leftovers from older keyboard-emulation builds.
rm -f "$DIST/roms/ports/skyval/skyval.gptk"
chmod +x "$DIST/roms/ports/Skyval.sh"

cat > "$DIST/roms/ports/skyval/README.txt" <<'EOF'
Skyval / PortMaster first-run test, not a public release.
Requires PortMaster runtimes godot_4.7.1 and weston_pkg_0.2 (aarch64).
For correct LPC redistributions, retain and audit all individual LPC credits.
Source: https://github.com/PylSerg/skyval-godot
Log after launching: ports/skyval/log.txt
EOF

if command -v zip >/dev/null 2>&1; then
    # zip -r normally updates an existing ZIP; remove it to avoid stale .gptk.
    rm -f "$DIST/Skyval_PortMaster_Test.zip"
    (
        cd "$DIST/roms/ports"
        zip -q -r "$DIST/Skyval_PortMaster_Test.zip" "Skyval.sh" "skyval"
    )
    echo "READY: $DIST/Skyval_PortMaster_Test.zip"
else
    echo "zip not found. Ready-to-copy files are at: $DIST/roms/ports/"
fi
echo "Copy Skyval.sh and skyval/ into the SD card's roms/ports/ directory."
echo "Launch Skyval in EmulationStation > Ports. Check skyval/log.txt on failure."
