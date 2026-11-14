# Skyval / R36H: native-controller PortMaster test

This is a developer test, not a public release. The port uses the shared
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
D-pad input; partial-tilt speed on ArkOS still needs verification.

## Build on Linux

From the cloned `skyval-godot` directory:

```bash
bash tools/build_portmaster.sh
```

The script detects Godot 4.7.2 at the known local location; use
`GODOT_BIN=/path/to/Godot` if needed. Override the sprite root with
`LPC_SPRITES_ROOT=/path/to/spritesheets` if desired.

Only 14 selected LPC PNGs and static **CascadiaMono-Regular.ttf** are
bundled. The font is discovered through Kvoka File Bridge under
`Cascadia_Mono/static/CascadiaMono-Regular.ttf` and should be installed
once with `bash tools/install_cascadia.sh /full/path/to/ttf`. The builder
prefers the project-local copy; `SKYVAL_FONT_PATH` overrides the location.
Missing fonts fall back to the Godot default; the huge LPC library remains
external.

Output:

```text
dist/portmaster/Skyval_PortMaster_Test.zip
dist/portmaster/roms/ports/
  Skyval.sh
  skyval/
    skyval.pck
    README.txt
```

Ensure the console has `godot_4.7.1` and `weston_pkg_0.2` installed
through PortMaster Runtime Manager. Copy **both** the new `Skyval.sh`
and `skyval/skyval.pck` to `roms/ports/` (or `roms2/ports/` for a
two-card setup). Delete any old `skyval.gptk`: the new launcher does not
read it.

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
