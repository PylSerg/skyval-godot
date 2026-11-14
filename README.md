# Skyval

Pixel-art top-down RPG prototype for Godot 4.7 Compatibility renderer.
Target device: R36H / ArkOS / PortMaster, 320×240 logical resolution
(displayed at 640×480 with integer nearest-neighbor scaling).

## Native gamepad input

**Skyval has no keyboard gameplay bindings.** Godot processes joystick
buttons and analog axes directly on desktop and on R36H. The same code path
is used for both targets.

| Control | World | Character creator |
|---|---|---|
| D-pad / left stick | Walk | Select item / change value |
| Right stick | Smooth camera look | Horizontal flick rotates portrait ±90° |
| Start or X | Open creator | Close creator |
| B | Reserved | Close creator |
| A | Reserved | Change selected option |
| L1 / R1 | Reserved | Appearance / Clothing tab |
| Other buttons | Reserved | Reserved |

The creator pauses world movement. Its right-stick rotation cycles through
**front → right → back → left → front**, one 90° step per horizontal tilt.
The stick must return to center before another step. Vertical right-stick
motions do nothing in the creator.

The menu has an enlarged 3× character portrait and two tabs. Clothing styles
include **None / Немає**, so each item can be removed individually. No
quick-undress button or language switch is present in this menu.

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

The launcher starts Godot via Weston, passes PortMaster's
`SDL_GAMECONTROLLERCONFIG` mapping to the runtime, and starts GPtoKEYB
**without a `-c` mapping file**, solely for the system exit hotkey.
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

**Risk:** Native joypad mapping is not yet verified on R36H. PortMaster's
Godot documentation warns about controller profiles and duplicate inputs.
The tested GPtoKEYB configuration remains available in the prior Git
history if a fallback is needed. If buttons do not work, inspect
`roms/ports/skyval/log.txt` for the detected controller name and GUID.

See [portmaster/README.md](portmaster/README.md) for details.

## Main source files

- `prototype/player.gd`: gamepad-only D-pad and analog movement
- `prototype/smart_camera.gd`: native right-stick look
- `ui/character_creator.gd`: native controller-driven creator UI
- `ui/character_preview.gd`: cyclic 90° preview rotation
- `characters/lpc_body_visual.gd`: LPC rendering and appearance slots
- `localization/strings.json`: localized UI text

No physical R36H runtime test has been run on this updated version yet.
