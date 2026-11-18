# Skyval / R36H: complete one-time LPC asset installation

This is a developer build, not a public release. The port uses the shared
Godot 4.7.1 (aarch64) runtime and Westonpack 0.2 on ArkOS.

## Changes from the keyboard-mapped test

- Godot reads R36H controller events **directly**.
- GPtoKEYB is still launched but **without -c**. It only handles
  PortMaster's system exit hotkey (typically Start + Select).
- No `skyval.gptk` is used or shipped.
- The launcher exports PortMaster's `sdl_controllerconfig` to the host
  environment, **not** as an inline `westonwrap.sh` command argument.
  Passing the spaced `GO-Super Gamepad` mapping via the wrapper's
  command string causes an immediate shell error (exit 127).
- The `skyval/input/keyboard_emulated_gamepad` project setting is gone.
- All former character creator debug keyboard bindings are removed.

PortMaster documents the GPtoKEYB no-config setup for games that already
support gamepads. Native controller input has now been tested successfully
on a physical R36H. Left-stick analog movement no longer competes with
D-pad input; partial-tilt walking speed is verified on ArkOS/R36H.

## Build and deploy directly over SSH (R36H)

Once ArkOS SSH is enabled and Skyval is already installed, **leave the SD
card inside the console**. Quit the game first (return to EmulationStation),
then run on your Kubuntu laptop:

```bash
bash tools/build_to_ssh.sh
```

The default console address is `ark@192.168.0.162`. If it changes,
pass the new address explicitly:

```bash
bash tools/build_to_ssh.sh ark@OTHER_IP
```

You may alternatively set `SKYVAL_SSH_TARGET=ark@host` in your shell or
use an SSH config alias.

**What happens:** The existing `tools/build_portmaster.sh --code-only
--no-zip` exports a fresh PCK locally. A single SSH connection (usually
one password prompt) streams **only `Skyval.sh` and
`skyval/skyval.pck`**, finds the already-installed game in
`/roms/ports` or `/roms2/ports`, stages both files on the console
and renames them into place after a successful transfer. Identical files
are skipped. No ZIP, LPC sprites, saves, configurations or game logs are
copied, removed or replaced. The script fails safely if the existing
installation or writable SD path cannot be found; it never creates a
second Skyval installation.

When **new LPC sprite files** are introduced, use the separate SD
workflow `bash tools/build_to_sd.sh --full-assets` to transfer the
selected assets (or copy those specific files another way). The SSH
script is intentionally **code-only**, protecting the large resource
library from unintended bulk transfers.

SSH access uses ArkOS credentials; the script never stores or embeds
passwords. SSH keys may be configured separately if desired.

## Direct build to the EASYROMS SD card (recommended)

When the card is inserted in your Kubuntu laptop, use **one command**:

```bash
bash tools/build_to_sd.sh
```

Default deployment target: `/run/media/serhii/EASYROMS/ports/`.

This script verifies the EASYROMS mountpoint before building, runs the
existing PortMaster Godot exporter with `--code-only --no-zip`, then
copies **only two files** straight onto the SD card:

- `/run/media/serhii/EASYROMS/ports/Skyval.sh`
- `/run/media/serhii/EASYROMS/ports/skyval/skyval.pck`

It makes no ZIP files. A temporary PCK is copied onto the SD card first
and renamed into place only when the copy finishes successfully.
**The existing `skyval/resources/lpc/`, `skyval/saves/` and `skyval/conf/`
are never deleted or recopied in this default mode.**
No manual copy through Dolphin is needed. Safely unmount/eject the card
after the script finishes.

When new equipment art needs to be installed for the first time,
explicitly request:

```bash
bash tools/build_to_sd.sh --full-assets
```

That mode builds the selected game-art set and uses `rsync --checksum`
to transfer **only new/changed sprites** without deleting existing art.
It needs `rsync` installed on the laptop. The source LPC library does
not need to be copied to the SD every time.

If your card is mounted at a different directory, override the mountpoint:

```bash
SKYVAL_SD_MOUNT="/run/media/$USER/EASYROMS" bash tools/build_to_sd.sh
```

The script rejects unmounted destinations, so it cannot silently write
a fake `EASYROMS` folder onto the internal drive.

## One-time game-assets build on Kubuntu

From the cloned `skyval-godot` directory:

```bash
git pull --ff-only
bash tools/build_portmaster.sh
```

This defaults to **the LPC images currently used by Skyval**, NOT the old
14-PNG smoke test and NOT the entire Universal LPC library.
The script automatically prefers your local Universal LPC addon at
`~/Godot/res/addons/Universal_LPC/resources/spritesheets` and falls back
to the other known local paths. If necessary, set an explicit source:

```bash
LPC_SPRITES_ROOT="$HOME/Godot/res/addons/Universal_LPC/resources/spritesheets" \
  bash tools/build_portmaster.sh --full-assets
```

It copies **only assets referenced by the current character creator and
inventory**: both body types and available skin tones, human heads/faces,
eye and hair combinations, starter clothes, items listed in
`inventory/inventory_state.gd`, and the leather/legion/plate armor
sprites (plus optional matching leather-vest lining).
It excludes unrelated LPC assets such as other armors, tools, weapons,
accessories, hairstyles and clothing that Skyval cannot use yet.

The selection is generated by `tools/collect_lpc_assets.py` from the
current `characters/lpc_body_visual.gd` and inventory catalog.
Missing optional variants are reported in the terminal and in
`skyval/resources/LPC_SELECTED_ASSETS.txt`.
The original library is **not copied into Git or into Godot's PCK**;
only the selected PNGs go to the SD card, where the renderer loads them
on demand. This keeps the archive considerably smaller than the entire
library, though the exact size depends on local PNGs.

All UI code, translations, title/creation JPEG backgrounds, and
CascadiaMono-Regular.ttf remain **inside** the small `skyval.pck`.
The font is auto-discovered or can be set with `SKYVAL_FONT_PATH`.
Godot can be set with `GODOT_BIN` if not found automatically.

**First-time output**: `dist/portmaster/Skyval_PortMaster_Full.zip`.

Unzip the entire `Skyval.sh` and `skyval/` tree onto your SD
under `roms/ports/` (or `roms2/ports/`). The layout must be:

```text
roms/ports/
  Skyval.sh
  skyval/
    skyval.pck
    resources/lpc/
      body/bodies/male/light.png
      body/bodies/female/light.png
      head/heads/human/...
      hair/...
      torso/armour/...
      ...
    saves/             (your existing character saves; KEEP THIS!)
    conf/              (existing preferences; KEEP THIS!)
```

**NEVER delete the existing `skyval/` directory** on the console:
merging the archive over it preserves `skyval/saves/`, `conf/`, and
any existing logs. Do not manually replace/decompress the LPC PNGs
individually. If transferring via a file manager, merge directories,
overwrite matching game files, but leave `saves/` alone. Remove any
obsolete `skyval.gptk` from the earlier keyboard-mapping version.

Make sure the console has `godot_4.7.1` and `weston_pkg_0.2`
installed via PortMaster Runtime Manager.

## Smaller future updates (no asset recopy)

Once the selected resource set is on the SD card, use:

```bash
git pull --ff-only
bash tools/build_portmaster.sh --code-only
```

This builds `dist/portmaster/Skyval_PortMaster_Update.zip`, with **only**
`Skyval.sh`, `skyval/skyval.pck` and `skyval/README.txt`.
It also creates a **separate clean folder**:
`dist/portmaster/update/roms/ports/`.
You can safely copy that folder's contents to the SD card
`roms/ports/`. It never contains `resources/lpc/`.

**Do not copy `dist/portmaster/roms/ports/` for code-only updates!**
That older full-install directory can still contain tens of thousands of
LPC sprites, and copying it overwrites them all. Existing
`roms/ports/skyval/resources/lpc/`, `saves/` and `conf/`
are untouched by an update. If new item sprites or hairstyles are added,
run `--full-assets` once to refresh the asset set.
The old `--no-assets` argument is an alias for `--code-only`.

Runtime environment: `portmaster/Skyval.sh` passes
`SKYVAL_LPC_ROOT="$GAMEDIR/resources/lpc"` to Godot. On startup it
checks the body resource and reports a clear error to
`roms/ports/skyval/log.txt` if the first asset-install step was missed.
No additional console configuration is required.

**Asset licenses:** This is for private development/testing. Audit and
preserve LPC licensing and credits before public distribution.

## Native controller mapping

| Button | In world | In creator |
|---|---|---|
| Left stick | Analog walking only | Up/down select, left/right change |
| D-pad ↓ | Open character creator | Next option |
| D-pad ↑/←/→ | Reserved for future quick actions (items, weapons) | Up selects, left/right changes |
| Right stick | Camera look-around | One ±90° turn per horizontal flick |
| Start / X | Reserved | Close creator |
| B | Reserved | Close creator |
| A | Reserved | Change selected value |
| L1 / R1 | Reserved | Appearance / Clothing tab |

D-pad Down opens the creator from the world. Once open, it navigates
down through options; B, Start or X closes the creator. Start/X do not
open it from the world anymore.

The creator ignores vertical right-stick movements. It pauses the world;
recenter the right stick before each new 90° step. The D-pad remains active
for creator navigation, but no longer moves the player in the world.

## Troubleshooting

If R36H does not recognize buttons, inspect
`roms/ports/skyval/log.txt`. A connected controller is printed as:

```text
Skyval controller: device=<id> name=<name> guid=<guid>
```

If no controller appears, the Godot runtime may not have received the
device. If the name/GUID is present but buttons are wrong, PortMaster's
SDL mapping or the Godot joypad profile needs investigation.

The previous functional keyboard-emulation launcher is preserved in Git
history: you can revert to it if the native gamepad test fails. Do not
assume successful USB controller testing on Linux guarantees R36H support.

References:
- https://portmaster.games/contribute/porting/engines/godot/
- https://portmaster.games/contribute/porting/packaging/
- https://portmaster.games/gptokeyb-documentation.html
