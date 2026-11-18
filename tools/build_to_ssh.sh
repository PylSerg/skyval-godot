#!/usr/bin/env bash
# Build Skyval on the laptop and deploy over SSH to an already installed ArkOS/PortMaster.
# Normal mode sends only Skyval.sh and skyval.pck. --sword-assets
# additionally ships the two real LPC iron sword sheets ONCE, if needed.
#
# Examples:
#   bash tools/build_to_ssh.sh 192.168.1.42
#   bash tools/build_to_ssh.sh --sword-assets  # first iron sword install
#   bash tools/build_to_ssh.sh --onehand-assets  # install 1H attack artwork once
#   bash tools/build_to_ssh.sh ark@192.168.0.162
#   SKYVAL_SSH_TARGET=ark@192.168.0.162 bash tools/build_to_ssh.sh
#
# The user must quit Skyval on the console before running this update.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_PORTS="$ROOT/dist/portmaster/update/roms/ports"

TARGET="${SKYVAL_SSH_TARGET:-ark@192.168.0.162}"
SWORD_ASSETS=false
SLASH_ASSETS=false
ONEHAND_ASSETS=false
HOST_SET=false
for option in "$@"; do
    case "$option" in
        --sword-assets) SWORD_ASSETS=true ;;
        --slash-assets) SLASH_ASSETS=true ;;
        --onehand-assets) ONEHAND_ASSETS=true ;;
        -*)
            echo "Usage: bash tools/build_to_ssh.sh [host-or-ark@host] [--sword-assets] [--slash-assets] [--onehand-assets]" >&2
            exit 2
            ;;
        *)
            if [ "$HOST_SET" = "true" ]; then
                echo "ERROR: supply only one SSH target." >&2
                exit 2
            fi
            HOST_SET=true
            case "$option" in
                *@*) TARGET="$option" ;;
                *) TARGET="ark@$option" ;;
            esac
            ;;
    esac
done
case "$TARGET" in
    ""|-*|*@-*)
        echo "ERROR: invalid SSH target. Use a hostname, IP or ark@hostname." >&2
        exit 2
        ;;
esac

for required in ssh tar; do
    if ! command -v "$required" >/dev/null 2>&1; then
        echo "ERROR: missing local command: $required" >&2
        exit 1
    fi
done

echo "Skyval over SSH -> $TARGET"
echo "Make sure Skyval is closed on the R36H before continuing."
echo "Building code-only PCK on laptop; no ZIP and no LPC copy..."
bash "$ROOT/tools/build_portmaster.sh" --code-only --no-zip

if [ ! -s "$BUILD_PORTS/skyval/skyval.pck" ] || [ ! -s "$BUILD_PORTS/Skyval.sh" ]; then
    echo "ERROR: build did not produce Skyval.sh and skyval.pck." >&2
    exit 1
fi

PACKAGE_FILES=(Skyval.sh skyval/skyval.pck)
if [ "$SWORD_ASSETS" = "true" ]; then
    # Only these TWO authentic Universal LPC atlas PNGs are required;
    # do not send the entire 45,000-file artwork library via SSH.
    LPC_ROOT="${LPC_SPRITES_ROOT:-}"
    if [ -z "$LPC_ROOT" ]; then
        for candidate in \
            "$HOME/Godot/res/addons/Universal_LPC/resources/spritesheets" \
            "$HOME/Godot/res/addons/universal_lpc/resources/spritesheets" \
            "$HOME/Godot/res/assets/lpc_sprites/resources/spritesheets" \
            "$HOME/Godot/res/assets/lpc_sprites"; do
            if [ -s "$candidate/weapon/sword/arming/universal/fg/iron.png" ]; then
                LPC_ROOT="$candidate"
                break
            fi
        done
    fi
    for part in bg fg; do
        rel="weapon/sword/arming/universal/$part/iron.png"
        src="$LPC_ROOT/$rel"
        if [ ! -s "$src" ]; then
            echo "ERROR: missing LPC sword sprite: $src" >&2
            echo "Set LPC_SPRITES_ROOT to your full Universal LPC spritesheets directory." >&2
            exit 1
        fi
        dest="skyval/resources/lpc/$rel"
        mkdir -p "$BUILD_PORTS/$(dirname "$dest")"
        cp -- "$src" "$BUILD_PORTS/$dest"
        PACKAGE_FILES+=("$dest")
    done
    echo "First-install sword assets: 2 iron sword PNGs added to SSH transfer."
fi


# Optional, authentic 128px sword-slash sprites (not the idle/walk sprites).
# Installed console library has only universal/{bg,fg}, no attack_slash.
if [ "$SLASH_ASSETS" = "true" ]; then
    UPSTREAM="https://raw.githubusercontent.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator/master/spritesheets/weapon/sword/arming/attack_slash"
    for part in bg fg; do
        rel="weapon/sword/arming/attack_slash/$part/iron.png"
        dest="$BUILD_PORTS/skyval/resources/lpc/$rel"
        mkdir -p "$(dirname "$dest")"
        if ! command -v curl >/dev/null 2>&1; then
            echo "ERROR: curl is required to download the two slash PNGs." >&2
            exit 1
        fi
        echo "Fetching official LPC sword slash: $part"
        curl --fail --location --silent --show-error --retry 2 --connect-timeout 10 \
            "$UPSTREAM/$part/iron.png" --output "$dest"
        python3 - "$dest" <<'CHECK_PNG'
from pathlib import Path
import struct
import sys
data = Path(sys.argv[1]).read_bytes()
valid = len(data) >= 24 and data[:8] == bytes((137,80,78,71,13,10,26,10)) and data[12:16] == b"IHDR"
if valid:
    width, height = struct.unpack(">II", data[16:24])
    valid = width >= 768 and height >= 512 and width % 128 == 0 and height % 128 == 0
if not valid:
    sys.exit("ERROR: invalid 128px LPC slash sheet: " + sys.argv[1])
CHECK_PNG
        PACKAGE_FILES+=("skyval/resources/lpc/$rel")
    done
    echo "Two authentic slash PNGs staged for the SSH transfer."
fi


# Revised LPC 1-Handed Slash uses the first seven backslash frames.
# Its two 128px sword sheets must be installed once, separately from slash.
if [ "$ONEHAND_ASSETS" = "true" ]; then
    UPSTREAM="https://raw.githubusercontent.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator/master/spritesheets/weapon/sword/arming/attack_backslash"
    for part in bg fg; do
        rel="weapon/sword/arming/attack_backslash/$part/iron.png"
        dest="$BUILD_PORTS/skyval/resources/lpc/$rel"
        mkdir -p "$(dirname "$dest")"
        if ! command -v curl >/dev/null 2>&1; then
            echo "ERROR: curl is required for the two one-handed LPC sword PNGs." >&2
            exit 1
        fi
        echo "Fetching original LPC one-handed sword attack: $part"
        curl --fail --location --silent --show-error --retry 2 --connect-timeout 10 \
            "$UPSTREAM/$part/iron.png" --output "$dest"
        python3 - "$dest" <<'CHECK_ONEHAND_PNG'
from pathlib import Path
import struct
import sys
data = Path(sys.argv[1]).read_bytes()
valid = len(data) >= 24 and data[:8] == bytes((137,80,78,71,13,10,26,10)) and data[12:16] == b"IHDR"
if valid:
    width, height = struct.unpack(">II", data[16:24])
    valid = width == 1664 and height == 512
if not valid:
    sys.exit("ERROR: invalid 128px LPC backslash sword sheet: " + sys.argv[1])
CHECK_ONEHAND_PNG
        PACKAGE_FILES+=("skyval/resources/lpc/$rel")
    done
    echo "Two original one-handed sword PNGs staged for SSH transfer."
fi

# The remote script is passed as an SSH command. Standard input remains
# available for the binary tar stream: ONE password prompt / SSH session.
# Do not put the password in this script or store it in the repository.
REMOTE_INSTALL="$(cat <<'REMOTE_SH'
set -eu
ports=""
for candidate in /roms/ports /roms2/ports; do
    # Never create a new game folder or guess which SD partition is active.
    if [ -s "$candidate/skyval/skyval.pck" ] && [ -f "$candidate/Skyval.sh" ]; then
        ports="$candidate"
        break
    fi
done
if [ -z "$ports" ]; then
    echo "ERROR: installed Skyval not found under /roms/ports or /roms2/ports." >&2
    exit 1
fi
if [ ! -s "$ports/skyval/resources/lpc/body/bodies/male/light.png" ]; then
    echo "ERROR: existing Skyval LPC assets are missing; refusing code-only update." >&2
    exit 1
fi
if [ ! -w "$ports" ] || [ ! -w "$ports/skyval" ]; then
    echo "ERROR: ark user cannot write to $ports; check mount permissions." >&2
    exit 1
fi
if ! command -v tar >/dev/null 2>&1 || ! command -v mktemp >/dev/null 2>&1; then
    echo "ERROR: console requires tar and mktemp for safe staging." >&2
    exit 1
fi

stage=""
cleanup() {
    if [ -n "$stage" ] && [ -d "$stage" ]; then
        rm -rf -- "$stage"
    fi
}
trap cleanup EXIT
stage="$(mktemp -d "$ports/skyval/.ssh-update.XXXXXXXX")"
# Extract the locally constructed tar stream. Only paths from the
# fixed PACKAGE_FILES array can enter it (two files, or four with sword).
tar -xf - -C "$stage"
if [ ! -s "$stage/Skyval.sh" ] || [ ! -s "$stage/skyval/skyval.pck" ]; then
    echo "ERROR: incomplete transfer; installed game was not modified." >&2
    exit 1
fi
chmod 755 "$stage/Skyval.sh" 2>/dev/null || true

# Optional first-install weapon assets: install both BEFORE switching
# to the newly built PCK. If the transfer was incomplete, keep old game.
if [ -d "$stage/skyval/resources/lpc/weapon/sword/arming/universal" ]; then
    for part in bg fg; do
        rel="weapon/sword/arming/universal/$part/iron.png"
        if [ ! -s "$stage/skyval/resources/lpc/$rel" ]; then
            echo "ERROR: sword asset transfer missing $rel; game not updated." >&2
            exit 1
        fi
    done
    for part in bg fg; do
        rel="weapon/sword/arming/universal/$part/iron.png"
        src="$stage/skyval/resources/lpc/$rel"
        dest="$ports/skyval/resources/lpc/$rel"
        mkdir -p "$(dirname "$dest")"
        if cmp -s "$src" "$dest"; then
            echo "Sword $part unchanged."
        else
            mv -f -- "$src" "$dest"
            echo "Installed sword sheet: $rel"
        fi
    done
fi


# Install optional 128px slash frames before replacing the PCK.
if [ -d "$stage/skyval/resources/lpc/weapon/sword/arming/attack_slash" ]; then
    for part in bg fg; do
        rel="weapon/sword/arming/attack_slash/$part/iron.png"
        if [ ! -s "$stage/skyval/resources/lpc/$rel" ]; then
            echo "ERROR: incomplete slash transfer; PCK not updated." >&2
            exit 1
        fi
    done
    for part in bg fg; do
        rel="weapon/sword/arming/attack_slash/$part/iron.png"
        src="$stage/skyval/resources/lpc/$rel"
        dest="$ports/skyval/resources/lpc/$rel"
        mkdir -p "$(dirname "$dest")"
        if ! cmp -s "$src" "$dest"; then
            mv -f "$src" "$dest"
            echo "Installed LPC slash sprite: $rel"
        fi
    done
fi


# Install both authentic one-handed sword layers before replacing the PCK.
if [ -d "$stage/skyval/resources/lpc/weapon/sword/arming/attack_backslash" ]; then
    for part in bg fg; do
        rel="weapon/sword/arming/attack_backslash/$part/iron.png"
        if [ ! -s "$stage/skyval/resources/lpc/$rel" ]; then
            echo "ERROR: incomplete one-handed sword transfer; PCK not updated." >&2
            exit 1
        fi
    done
    for part in bg fg; do
        rel="weapon/sword/arming/attack_backslash/$part/iron.png"
        src="$stage/skyval/resources/lpc/$rel"
        dest="$ports/skyval/resources/lpc/$rel"
        mkdir -p "$(dirname "$dest")"
        if ! cmp -s "$src" "$dest"; then
            mv -f -- "$src" "$dest"
            echo "Installed LPC one-handed attack: $rel"
        fi
    done
fi

# Rename from staging ON THE SAME SD FILESYSTEM: no partial PCK ever
# replaces the known-good game. Skip identical files when possible.
if cmp -s "$stage/Skyval.sh" "$ports/Skyval.sh"; then
    echo "Launcher unchanged."
else
    mv -f -- "$stage/Skyval.sh" "$ports/Skyval.sh"
    echo "Updated: $ports/Skyval.sh"
fi
if cmp -s "$stage/skyval/skyval.pck" "$ports/skyval/skyval.pck"; then
    echo "PCK unchanged."
else
    mv -f -- "$stage/skyval/skyval.pck" "$ports/skyval/skyval.pck"
    echo "Updated: $ports/skyval/skyval.pck"
fi
sync
echo "READY: Skyval deployed via SSH. Existing resources/lpc, saves and conf preserved."
REMOTE_SH
)"

if [ "$ONEHAND_ASSETS" = "true" ]; then
    echo "Uploading launcher, PCK and authentic one-handed attack sprites..."
elif [ "$SLASH_ASSETS" = "true" ]; then
    echo "Uploading launcher, PCK and authentic slash sprites..."
elif [ "$SWORD_ASSETS" = "true" ]; then
    echo "Uploading launcher, PCK and only the two required sword sheets..."
else
    echo "Uploading only the launcher and PCK in a single SSH connection..."
fi
# Do not allocate a PTY: SSH stdin is a binary tar stream.
# Pipeline failure propagates (pipefail), and a failed transfer leaves the
# original game installed; temporary partial uploads are removed remotely.
tar -C "$BUILD_PORTS" -cf - "${PACKAGE_FILES[@]}" |
    ssh -T -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3 "$TARGET" "$REMOTE_INSTALL"

echo "Done. No SD card removal needed."
