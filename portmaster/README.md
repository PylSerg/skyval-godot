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

## One-time FULL build on Kubuntu

From the cloned `skyval-godot` directory:

```bash
git pull --ff-only
bash tools/build_portmaster.sh
```

This now defaults to **full assets**, NOT the old 14-PNG smoke test.
The script automatically prefers your full Universal LPC addon at
`~/Godot/res/addons/Universal_LPC/resources/spritesheets` and falls back
to the other known local paths. If necessary, set an explicit source:

```bash
LPC_SPRITES_ROOT="$HOME/Godot/res/addons/Universal_LPC/resources/spritesheets" \
  bash tools/build_portmaster.sh --full-assets
```

It copies the **whole LPC resource tree** (all available bodies, heads,
eyes, hair, clothing, footwear, armor and other library resources)
to `dist/portmaster/roms/ports/skyval/resources/lpc/`.
It does not push these large assets into Git and does not import them
into Godot's PCK. Godot loads needed PNGs from the SD card on demand.
This first archive can therefore be large, depending on the local
LPC library and free disk/SD space.

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

Once the full library is on the SD card, use:

```bash
git pull --ff-only
bash tools/build_portmaster.sh --code-only
```

This builds `dist/portmaster/Skyval_PortMaster_Update.zip`, with **only**
`Skyval.sh`, `skyval/skyval.pck` and `skyval/README.txt`.
Install it over the same `roms/ports/` path. The existing
`skyval/resources/lpc/` is untouched. The old `--no-assets`
argument is retained as an alias for `--code-only`.

Runtime environment: `portmaster/Skyval.sh` passes
`SKYVAL_LPC_ROOT="$GAMEDIR/resources/lpc"` to Godot. On startup it
checks the body resource and reports a clear error to
`roms/ports/skyval/log.txt` if the full first-install step was missed.
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
