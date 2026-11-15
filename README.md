# Skyval

Pixel-art top-down RPG prototype for Godot 4.7 Compatibility renderer.
Target device: R36H / ArkOS / PortMaster, 320×240 logical resolution
(displayed at 640×480 with integer nearest-neighbor scaling).
Keep the internal 320×240 viewport to reserve headroom for crowded RPG
scenes; the UI is designed for this size.

## Native gamepad input

**Skyval has no keyboard gameplay bindings.** Godot processes joystick
buttons and analog axes directly on desktop and on R36H. The same code path
is used for both targets.

| Control | World | Character creator |
|---|---|---|
| Left stick | Analog walk (speed depends on tilt) | Select item / change value |
| D-pad ↓ | Open character creator | Next item |
| D-pad ↑/←/→ | Reserved for future equipment/items | Select item / change value |
| Right stick | Smooth camera look | Horizontal flick rotates portrait ±90° |
| Start or X | Reserved | Close creator |
| B | Reserved | Close creator |
| A | Reserved | Change selected option |
| L1 / R1 | Reserved | Appearance / Clothing tab |
| Other buttons | Reserved | Reserved |

Press **D-pad Down** in the world to open the character creator; D-pad Down
then returns to its usual menu-navigation role. Close the creator using
**B**, **Start**, or **X**. Start/X no longer open it from the world.

The creator pauses world movement. Its right-stick rotation cycles through
**front → right → back → left → front**, one 90° step per horizontal tilt.
The stick must return to center before another step. Vertical right-stick
motions do nothing in the creator.

The menu has a 3× character portrait and two tabs. The left panel uses a
**single-column field layout**: each label is above a full-width selector.
Appearance and clothing fields have larger (16px) headings and
subtle 1px horizontal separators. Overflowing lists still scroll using
D-pad / left stick or mouse wheel, and automatically reveal the selected
field, but the scrollbar itself stays hidden to keep the choice arrows
unobstructed. The right-side portrait stays fixed.

The UI prefers the static **Cascadia Mono Regular** at
`assets/fonts/CascadiaMono-Regular.ttf`. This is the correct font discovered
through Kvoka File Bridge at `Cascadia_Mono/static/CascadiaMono-Regular.ttf`
(about 402.5 KB). Run `bash tools/install_cascadia.sh` to copy it from a
local `Cascadia_Mono` download folder to the Git checkout, or pass its
absolute source path as the first argument. The PortMaster builder includes
the project font in its PCK. No fonts are downloaded.

Godot 4.7 renders Cascadia Mono with **grayscale antialiasing** and
normal hinting, keeping its vector contours readable at 320×240.
Previously antialiasing was disabled, which made each jagged font pixel
twice as large on the 640×480 output. This change smooths glyph edges
without increasing the world-render resolution. The code also checks
Ukrainian glyphs and uses a built-in fallback only when needed. The previous Latin-only
`assets/fonts/Cascadia.ttf` is no longer used by the UI.

Clothing styles include **None / Немає**, so each item can be removed
individually. No quick-undress button or language switch is present.

## Appearance and localization

The creator can change LPC body type (male/female), skin, eye color, hairstyle,
and independent shirt/trousers/footwear styles and colors. Body, head, hair and
clothes are separate synchronized LPC sprite layers. The original procedural
avatar remains as a missing-assets fallback.

All in-game strings are in
[localization/strings.json](localization/strings.json), currently Ukrainian
and English. The `SkyvalLocale` service loads it. Language selection will
move to the future global **Settings** menu; the preference is persisted in
`user://skyval_settings.cfg`.

The LPC sprites remain outside Git in the user's local resource library.
Only the selected sprites are bundled for PortMaster tests. Inspect and
retain each asset's original LPC license and attribution before distribution.

## PortMaster native-controller test

The launcher starts Godot via Weston and starts GPtoKEYB
**without a `-c` mapping file**, solely for the system exit hotkey.
The controller configuration is exported by the launcher, not passed as
an inline argument through `westonwrap.sh`, whose command parsing
breaks on the space in `GO-Super Gamepad` (exit code 127).
No `.gptk` or keyboard-emulation project setting is included.

Build from the Linux checkout with:

```bash
bash tools/build_portmaster.sh
```

This writes `dist/portmaster/Skyval_PortMaster_Test.zip`.
Copy `Skyval.sh` and `skyval/` from the ZIP into the SD card's
`roms/ports/` directory. Replace the previous launcher **as well as**
the `.pck`; changing only the PCK will leave the old keyboard-mapping
launcher active.

**R36H status:** Native controls have been confirmed working on the physical
R36H. Walking uses only the left-stick axes now, avoiding any D-pad override
that could force full speed. Analog walking speed is now confirmed working on the R36H. For controller details inspect
`roms/ports/skyval/log.txt` for its name and GUID.

See [portmaster/README.md](portmaster/README.md) for details.

## Main source files

- `prototype/player.gd`: left-stick-only analog movement; D-pad reserved
- `prototype/smart_camera.gd`: native right-stick look
- `ui/character_creator.gd`: native controller-driven creator UI
- `ui/character_preview.gd`: cyclic 90° preview rotation
- `characters/lpc_body_visual.gd`: LPC rendering and appearance slots
- `localization/strings.json`: localized UI text

Native controller input and partial-tilt walking were tested successfully
on R36H. The UI font/layout updates still need a physical-console check.

### Bundle the correct font in Git

After placing the downloaded `Cascadia_Mono` directory locally, run:

```bash
bash tools/install_cascadia.sh /full/path/to/Cascadia_Mono/static/CascadiaMono-Regular.ttf
git add -A assets/fonts
git commit -m "Use Cascadia Mono Regular in Skyval"
git push
```

The installer also copies `OFL.txt` from the downloaded font directory,
when available. The GitHub connector cannot read the TTF bytes from the
browser bridge, so this one-time binary commit is done locally.
