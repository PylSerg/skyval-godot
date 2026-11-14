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
The five appearance fields fit at once; the six clothing fields scroll
automatically as the player navigates. The right-side portrait stays fixed.

The UI prefers the project-local `assets/fonts/Cascadia.ttf`.
Run `bash tools/install_cascadia.sh` once to copy it from
`$HOME/Godot/res/assets/fonts/Cascadia.ttf` into the Git checkout.
The PortMaster builder already includes the project font in the PCK.
Without the project copy, desktop development can still use the external
asset. `SKYVAL_FONT_PATH` overrides the builder's font location.

**Important:** The supplied Cascadia 1909.16 TTF only has Latin glyphs
(102 Unicode code points), not Ukrainian Cyrillic. The UI uses Godot's
built-in fallback for Ukrainian text. In Godot 4.7 use
`TextServer.HINTING_NORMAL`, not the nonexistent `HINTING_FULL`,
with integer-aligned subpixel positioning.

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

### Bundle the font into Git

After `bash tools/install_cascadia.sh` the font will exist inside the
project at `assets/fonts/Cascadia.ttf`. Godot imports the TTF when
opening the project; its generated `.ttf.import` need not be committed.

```bash
git add assets/fonts/Cascadia.ttf
git commit -m "Bundle Cascadia font in Skyval"
git push
```

The GitHub text-file connector can commit code but not upload raw font
binary attachments, so commit the font once from your local checkout.
