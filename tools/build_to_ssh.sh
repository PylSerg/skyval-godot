#!/usr/bin/env bash
# Build Skyval on the laptop and deploy over SSH to an already installed ArkOS/PortMaster.
# One SSH session carries ONLY Skyval.sh and skyval.pck; no archive files or LPC sprites.
#
# Examples:
#   bash tools/build_to_ssh.sh 192.168.1.42
#   bash tools/build_to_ssh.sh ark@192.168.1.42
#   SKYVAL_SSH_TARGET=ark@192.168.0.162 bash tools/build_to_ssh.sh
#
# The user must quit Skyval on the console before running this update.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_PORTS="$ROOT/dist/portmaster/update/roms/ports"

if [ "$#" -gt 1 ]; then
    echo "Usage: bash tools/build_to_ssh.sh [host-or-ark@host]" >&2
    exit 2
fi

TARGET="${SKYVAL_SSH_TARGET:-ark@192.168.0.162}"
if [ "$#" -eq 1 ]; then
    case "$1" in
        *@*) TARGET="$1" ;;
        *) TARGET="ark@$1" ;;
    esac
fi
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
# Only the two explicitly named build files are accepted.
tar -xf - -C "$stage" Skyval.sh skyval/skyval.pck
if [ ! -s "$stage/Skyval.sh" ] || [ ! -s "$stage/skyval/skyval.pck" ]; then
    echo "ERROR: incomplete transfer; installed game was not modified." >&2
    exit 1
fi
chmod 755 "$stage/Skyval.sh" 2>/dev/null || true

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

echo "Uploading only the launcher and PCK in a single SSH connection..."
# Do not allocate a PTY: SSH stdin is a binary tar stream.
# Pipeline failure propagates (pipefail), and a failed transfer leaves the
# original game installed; temporary partial uploads are removed remotely.
tar -C "$BUILD_PORTS" -cf - Skyval.sh skyval/skyval.pck |
    ssh -T -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3 "$TARGET" "$REMOTE_INSTALL"

echo "Done. No SD card removal needed."
