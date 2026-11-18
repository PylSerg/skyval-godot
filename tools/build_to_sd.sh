#!/usr/bin/env bash
# One-command Skyval build + safe direct deployment to the R36H EASYROMS SD.
# Default updates ONLY skyval.pck and Skyval.sh. No ZIPs and no LPC recopy.
#
# Usage:
#   bash tools/build_to_sd.sh
#   bash tools/build_to_sd.sh --full-assets  # ONLY when new LPC art is needed
#
# Override the mountpoint only when the card is deliberately mounted elsewhere:
#   SKYVAL_SD_MOUNT=/run/media/$USER/EASYROMS bash tools/build_to_sd.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SD_MOUNT="${SKYVAL_SD_MOUNT:-/run/media/serhii/EASYROMS}"
SD_PORTS="$SD_MOUNT/ports"
MODE="code"

case "${1:---code-only}" in
    --code-only) MODE="code" ;;
    --full-assets) MODE="full" ;;
    *)
        echo "Usage: bash tools/build_to_sd.sh [--code-only|--full-assets]" >&2
        exit 2
        ;;
esac
if [ "$#" -gt 1 ]; then
    echo "ERROR: pass at most one mode option." >&2
    exit 2
fi

# Never silently create an EASYROMS-looking folder on the system drive.
# A wrong/unmounted target must fail BEFORE compiling or writing anything.
if ! command -v mountpoint >/dev/null 2>&1; then
    echo "ERROR: mountpoint (util-linux) is required to verify the SD card." >&2
    exit 1
fi
if [ ! -d "$SD_MOUNT" ] || ! mountpoint -q "$SD_MOUNT"; then
    echo "ERROR: the EASYROMS SD card is not mounted at $SD_MOUNT" >&2
    echo "Insert/mount the card in Dolphin, then rerun. No files were written." >&2
    exit 1
fi
if [ ! -d "$SD_PORTS" ] || [ ! -w "$SD_PORTS" ]; then
    echo "ERROR: missing or non-writable PortMaster directory: $SD_PORTS" >&2
    exit 1
fi
if [ "$MODE" = "code" ] && [ ! -d "$SD_PORTS/skyval" ]; then
    echo "ERROR: Skyval is not yet installed on the card." >&2
    echo "Run bash tools/build_to_sd.sh --full-assets for a first install." >&2
    exit 1
fi
if [ "$MODE" = "code" ] && [ ! -s "$SD_PORTS/skyval/resources/lpc/body/bodies/male/light.png" ]; then
    echo "ERROR: installed Skyval LPC body is missing on the card." >&2
    echo "Use --full-assets to transfer missing current-game sprites." >&2
    exit 1
fi
if [ "$MODE" = "full" ] && ! command -v rsync >/dev/null 2>&1; then
    echo "ERROR: rsync is needed for --full-assets to copy only changed sprites." >&2
    exit 1
fi

echo "SD card: $SD_PORTS"
if [ "$MODE" = "code" ]; then
    echo "Mode: code-only (two files; NO LPC copies, NO ZIPs)"
    BUILD_MODE="--code-only"
    BUILT_PORTS="$ROOT/dist/portmaster/update/roms/ports"
else
    echo "Mode: full assets (only Skyval-used LPC sprites; incremental rsync)"
    BUILD_MODE="--full-assets"
    BUILT_PORTS="$ROOT/dist/portmaster/roms/ports"
fi

# Reuse the existing PortMaster build staging instead of maintaining a
# second Godot export implementation. No ZIPs are created.
bash "$ROOT/tools/build_portmaster.sh" "$BUILD_MODE" --no-zip

SOURCE_PACK="$BUILT_PORTS/skyval/skyval.pck"
SOURCE_LAUNCHER="$BUILT_PORTS/Skyval.sh"
if [ ! -s "$SOURCE_PACK" ] || [ ! -s "$SOURCE_LAUNCHER" ]; then
    echo "ERROR: Godot build did not produce the required game files." >&2
    exit 1
fi

mkdir -p "$SD_PORTS/skyval"
TEMP_PACK=""
TEMP_LAUNCHER=""
cleanup() {
    if [ -n "$TEMP_PACK" ]; then rm -f -- "$TEMP_PACK"; fi
    if [ -n "$TEMP_LAUNCHER" ]; then rm -f -- "$TEMP_LAUNCHER"; fi
}
trap cleanup EXIT

# Copy to temporary filenames on the SAME SD filesystem. This keeps
# the previous playable PCK intact if a copy runs out of card space.
TEMP_PACK="$(mktemp "$SD_PORTS/skyval/.skyval.pck.new.XXXXXXXX")"
TEMP_LAUNCHER="$(mktemp "$SD_PORTS/.Skyval.sh.new.XXXXXXXX")"
cp -- "$SOURCE_PACK" "$TEMP_PACK"
cp -- "$SOURCE_LAUNCHER" "$TEMP_LAUNCHER"
# On VFAT/exFAT, executable bits may be controlled by mount options.
chmod 644 "$TEMP_PACK" 2>/dev/null || true
chmod 755 "$TEMP_LAUNCHER" 2>/dev/null || true

if [ "$MODE" = "full" ]; then
    SOURCE_LPC="$BUILT_PORTS/skyval/resources/lpc"
    TARGET_LPC="$SD_PORTS/skyval/resources/lpc"
    if [ ! -s "$SOURCE_LPC/body/bodies/male/light.png" ]; then
        echo "ERROR: full build did not produce the expected LPC assets." >&2
        exit 1
    fi
    mkdir -p "$TARGET_LPC"
    echo "Syncing ONLY new/changed game sprites (no deletion of existing assets)..."
    # Checksums prevent an SD filesystem's low timestamp precision from
    # causing unnecessary rewrites. No --delete: leave all existing art,
    # save files and console configuration untouched.
    rsync --recursive --checksum --human-readable --stats \
        "$SOURCE_LPC/" "$TARGET_LPC/"
    if [ -s "$BUILT_PORTS/skyval/resources/LPC_SELECTED_ASSETS.txt" ]; then
        cp -- "$BUILT_PORTS/skyval/resources/LPC_SELECTED_ASSETS.txt" \
            "$SD_PORTS/skyval/resources/LPC_SELECTED_ASSETS.txt"
    fi
fi

# Activate only after the complete build (and optional art sync) succeeded.
# Each rename is atomic on the mounted SD filesystem.
mv -f -- "$TEMP_LAUNCHER" "$SD_PORTS/Skyval.sh"
TEMP_LAUNCHER=""
mv -f -- "$TEMP_PACK" "$SD_PORTS/skyval/skyval.pck"
TEMP_PACK=""
sync -f "$SD_PORTS/skyval/skyval.pck"
echo
echo "READY ON SD: $SD_PORTS/skyval/skyval.pck"
echo "Launcher:    $SD_PORTS/Skyval.sh"
echo "Existing skyval/resources/lpc/, saves/ and conf/ were not deleted."
echo "You can safely unmount/eject EASYROMS before inserting it into the R36H."
