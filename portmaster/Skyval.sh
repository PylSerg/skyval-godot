#!/bin/bash
# Skyval / PortMaster: Godot 4.7.1 aarch64 Weston smoke test.

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
if [ -d "/opt/system/Tools/PortMaster/" ]; then
    controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
    controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
    controlfolder="$XDG_DATA_HOME/PortMaster"
else
    controlfolder="/roms/ports/PortMaster"
fi
if [ ! -f "$controlfolder/control.txt" ]; then
    echo "Skyval: PortMaster control.txt not found: $controlfolder"
    exit 1
fi
source "$controlfolder/control.txt"
[ -f "$controlfolder/mod_${CFW_NAME}.txt" ] && source "$controlfolder/mod_${CFW_NAME}.txt"
get_controls

GAMEDIR="/$directory/ports/skyval"
CONFDIR="$GAMEDIR/conf"
PCK="$GAMEDIR/skyval.pck"
LPC_ROOT="$GAMEDIR/resources/lpc"
GODOT_RUNTIME="godot_4.7.1"
GODOT_EXEC="godot471.$DEVICE_ARCH"
WESTON_RUNTIME="weston_pkg_0.2"
WESTON_DIR="/tmp/weston"
GODOT_DIR="/tmp/godot"

mkdir -p "$GAMEDIR" "$CONFDIR"
exec > >(tee "$GAMEDIR/log.txt") 2>&1
echo "Skyval: PortMaster smoke test"
echo "CFW: ${CFW_NAME:-unknown}; Arch: ${DEVICE_ARCH:-unknown}"
if [ ! -s "$PCK" ]; then
    echo "ERROR: missing $PCK"
    pm_finish
    exit 1
fi
if [ ! -s "$LPC_ROOT/body/bodies/male/light.png" ]; then
    echo "ERROR: complete LPC resource pack missing: $LPC_ROOT"
    echo "Copy resources/lpc/ from the FULL Skyval package onto the SD card."
    pm_finish
    exit 1
fi
echo "Skyval LPC resources: $LPC_ROOT"
if [ "$DEVICE_ARCH" != "aarch64" ]; then
    echo "ERROR: Godot 4.7.1 runtime needs aarch64"
    pm_finish
    exit 1
fi

for runtime in "$WESTON_RUNTIME" "$GODOT_RUNTIME"; do
    if [ ! -f "$controlfolder/libs/${runtime}.squashfs" ]; then
        if [ ! -f "$controlfolder/harbourmaster" ]; then
            echo "ERROR: install ${runtime}.squashfs via PortMaster Runtime Manager"
            pm_finish
            exit 1
        fi
        $ESUDO "$controlfolder/harbourmaster" --quiet --no-check runtime_check "${runtime}.squashfs"
        if [ ! -f "$controlfolder/libs/${runtime}.squashfs" ]; then
            echo "ERROR: could not obtain runtime $runtime"
            pm_finish
            exit 1
        fi
    fi
done

$ESUDO mkdir -p "$WESTON_DIR" "$GODOT_DIR"
if [ "${PM_CAN_MOUNT:-Y}" != "N" ]; then
    $ESUDO umount "$WESTON_DIR" 2>/dev/null || true
    $ESUDO umount "$GODOT_DIR" 2>/dev/null || true
fi

if ! $ESUDO mount "$controlfolder/libs/${WESTON_RUNTIME}.squashfs" "$WESTON_DIR"; then
    echo "ERROR: failed to mount Weston runtime"
    pm_finish
    exit 1
fi
if ! $ESUDO mount "$controlfolder/libs/${GODOT_RUNTIME}.squashfs" "$GODOT_DIR"; then
    echo "ERROR: failed to mount Godot runtime"
    $ESUDO umount "$WESTON_DIR" 2>/dev/null || true
    pm_finish
    exit 1
fi

if [ ! -x "$GODOT_DIR/$GODOT_EXEC" ]; then
    echo "ERROR: Godot runtime executable missing: $GODOT_EXEC"
    ls -lah "$GODOT_DIR"
else
    cd "$GAMEDIR" || exit 1
    # Export for the host/SDL environment, never pass this as an inline
    # argument to westonwrap: its shell command assembly splits values
    # containing spaces (for example, "GO-Super Gamepad"), causing exit 127.
    export SDL_GAMECONTROLLERCONFIG="${sdl_controllerconfig:-}"
    export SKYVAL_LPC_ROOT="$LPC_ROOT"
    # Native Godot joypad input; GPtoKEYB supplies only the PortMaster exit hotkey.
    $GPTOKEYB "$GODOT_EXEC" &

    echo "Starting Godot from PCK..."
    $ESUDO env "$WESTON_DIR/westonwrap.sh" headless noop kiosk crusty_x11egl \
        XDG_DATA_HOME="$CONFDIR" \
        SKYVAL_SAVES_DIR="$GAMEDIR/saves" \
        SKYVAL_LPC_ROOT="$LPC_ROOT" \
        "$GODOT_DIR/$GODOT_EXEC" \
        --resolution "${DISPLAY_WIDTH:-640}x${DISPLAY_HEIGHT:-480}" -f \
        --disable-cursor \
        --rendering-driver opengl3_es --audio-driver ALSA \
        --main-pack "$PCK"
    echo "Godot exit code: $?"
fi

$ESUDO "$WESTON_DIR/westonwrap.sh" cleanup 2>/dev/null || true
if [ "${PM_CAN_MOUNT:-Y}" != "N" ]; then
    $ESUDO umount "$WESTON_DIR" 2>/dev/null || true
    $ESUDO umount "$GODOT_DIR" 2>/dev/null || true
fi
pm_finish
