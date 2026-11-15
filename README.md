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
| D-pad ↓ | Reserved for future quick actions | Next item |
| D-pad ↑/←/→ | Reserved for future equipment/items | Select item / change value |
| Right stick | Smooth camera look | Horizontal flick rotates portrait ±90° |
| Select / Back or L3 | Open character creator (future inventory) | Close creator |
| Start or R3 | Open main menu | Open main menu (closes creator) |
| B | Reserved | Close creator |
| X | Reserved | Reserved |
| A | Reserved | Change selected option |
| L1 / R1 | Reserved | Appearance / Clothing tab |

Press **Select / Back** or **L3** in the world to open the character creator.
Press **Select/L3** again to close it, or use **B** to return to the world.
**X** is not a Back shortcut. Press **Start** or **R3** from the world or
while editing the character to open the global game menu. The world pauses
while either interface is open.

## Main menu and prototype saves

The game **starts paused in its main menu**, with four vertically stacked
options: **Continue / Продовжити**, **New Game / Нова гра**,
**Settings / Налаштування**, and **Quit / Вийти**.
On a fresh install, Continue is disabled and New Game starts the
prototype world at the scene-defined spawn. When a v1 save exists,
Continue loads its saved position and appearance before unpausing.
Starting a New Game with an existing save requires **A** to confirm;
**B** cancels. Continue in the in-game menu simply resumes the world.

The provisional save file is `user://skyval_save_v1.json`. It stores the
player position and appearance (including LPC wardrobe variants, if
available). The game writes an initial save after New Game and a checkpoint
when opening the in-game menu or choosing Quit. This is **not yet**
a complete RPG save system: future inventory, NPCs, quests and world changes
will need their own serialization. Continue stays disabled if the v1 save
is absent or invalid.

Settings currently contains only language (Ukrainian / English). Use
D-pad up/down or left-stick vertical to pick a menu item and **A** to
activate it. Inside Settings, use D-pad left/right, left-stick horizontal,
or **A** to switch languages. **B** goes back; **Start/R3** closes the
menu only after a game has begun, preventing startup-menu bypass.
The selected language is stored in `user://skyval_settings.cfg` via
the existing localization service. **Quit** exits Godot, returning to
PortMaster on the handheld.

## Pause and Back navigation

The autoload `SkyvalUiPause` (`ui/pause_manager.gd`) tracks every blocking UI
owner. The first open interface pauses the SceneTree: world nodes
using inherited/pausable processing stop, including player movement, NPCs,
ordinary animations and Timer nodes. For future gameplay timers created via
`get_tree().create_timer()`, pass `process_always=false` so they also pause.
Nodes explicitly set to always-process remain active. The last closing
interface restores the pause state from before the first UI was opened.
Opening GameMenu from CharacterCreator transfers pause ownership **before**
closing the creator, preventing an unpaused frame during the transition.

Blocking interfaces must use `Node.PROCESS_MODE_ALWAYS` for their own
controller navigation, and call
`SkyvalUiPause.set_open(self, true/false)` whenever they open/close.
The future inventory should follow the same contract; it is **not yet
implemented**. **B** moves one level back: Settings → Main Menu → World,
or CharacterCreator → World. No on-screen Back button is required.
**Select/L3** also toggles CharacterCreator (and will toggle the future
inventory); **Start/R3** separately toggles the global menu while
playing. At launch, the main menu cannot be dismissed until New Game
or a valid Continue is selected.

The creator pauses world movement. Its right-stick rotation cycles through
**front → right → back → left → front**, one 90° step per horizontal tilt.
The stick must return to center before another step. Vertical right-stick
motions do nothing in the creator.

The menu has a 3× character portrait and two tabs. The left panel uses a
**single-column field layout**: each label is above a full-width selector.
Appearance and clothing fields share fixed panel insets (7px),
group spacing (12px), and inner field spacing (5px), with 16px headings
and subtle 1px horizontal separators. Overflowing lists continue to
scroll vertically and auto-reveal the selected field; the vertical bar
stays hidden. L1 / R1 select the tabs and slide page contents horizontally.
Each tab is sized by its text and equal 10px left/right padding; the
top tab strip can scroll horizontally when tabs do not fit. The active
tab is automatically revealed, with a brighter background and border.
No swipe-to-switch input was added. The right-side portrait stays fixed.

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
and English. The `SkyvalLocale` service loads it. Language selection lives in the global **Settings** menu; the preference is
persisted in `user://skyval_settings.cfg`.

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
- `ui/game_menu.gd`: launch/pause menu, prototype save/load, language and Quit
- `ui/pause_manager.gd`: shared pause ownership for menus and future inventory
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
