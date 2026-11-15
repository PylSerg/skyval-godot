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

| Control | World | Wardrobe/backpack |
|---|---|---|
| Left stick | Analog walk (speed depends on tilt) | Select item / change value |
| D-pad ↓ | Reserved for future quick actions | Next item |
| D-pad ↑/←/→ | Reserved for future equipment/items | Select item / change value |
| Right stick | Smooth camera look | Horizontal flick rotates portrait ±90° |
| Select / Back or L3 | Open backpack | Close backpack |
| Start or R3 | Open main menu | Open main menu (closes backpack) |
| B | Reserved | Close backpack |
| X | Reserved | Reserved (creates character in Appearance window; takes all in chest) |
| A | Interact with nearby test chest | Cycle owned option in selected field |
| L1 / R1 | Reserved | Previous / next backpack tab |

Press **Select / Back** or **L3** in the world to open the **backpack**.
Press **Select/L3** again to close it, or use **B** to return to the world.
**X** is not a Back shortcut. **Appearance** is a separate,
reusable window which is opened during New Game, not a backpack tab.
Press **Start** or **R3** during gameplay to open the global menu.
The world pauses while a blocking interface is open.

## Main menu and prototype saves

The game **starts paused in its main menu**, with four vertically stacked
options: **Continue / Продовжити**, **New Game / Нова гра**,
**Settings / Налаштування**, and **Quit / Вийти**.
On a fresh install, Continue is disabled. New Game first resets a
**draft** character to the prototype spawn and opens the separate
**Appearance / Зовнішність** window. Configure body type, skin, eyes,
hairstyle and hair color, then press **X**, as indicated by the fixed
hint below the appearance heading. A separate modal asks for confirmation:
**A** creates the character, while **B** dismisses the confirmation and
returns to editing. There is no Create Character button in the parameter
list. Only after confirming with A is the new save committed and the
paused world started. The reusable appearance editor uses the same X →
A/B confirmation to apply later changes.
At creation time, the starting LPC outfit depends on the selected body type:
**male** gets only **formal trousers** (no shirt, no shoes), while **female**
gets **formal trousers plus a T-shirt** (no shoes). The draft outfit updates
when gender changes during creation. These defaults are applied only to
**New Game**, never when continuing an existing save or editing appearance
later. If required LPC sprite sheets are unavailable, the old valid
appearance is retained and a warning is logged.
**B** cancels appearance creation and returns to the main menu without
overwriting a previous save. An existing save still requires the
New Game overwrite-intent confirmation (A confirms, B cancels).
Continue loads saved position and appearance before unpausing; when
already playing, it simply resumes the world.

The provisional save file is `user://skyval_save_v1.json`. It stores the
player position, appearance, equipped item ids, backpack inventory and
the remaining contents of the test chest (when available). The game writes
the initial save **after character creation is confirmed**, then checkpoints
when opening the in-game menu or choosing Quit. This is **not yet**
a complete RPG save system: future NPCs, quests and world changes
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

## Test chest, backpack and equipped clothing

Two test chests are instantiated in code on opposite sides of the
prototype house: **Clothing** (brown) at **(905, 554)** and **Armor**
(blue-steel) at **(745, 554)**. Walk close until the **A** prompt appears.
Press **A** to open it. Use D-pad up/down or the left stick to navigate.
Press **A** on an item to mark/unmark it, then navigate to
**Take selected / Забрати вибране** and press **A** to transfer *only*
marked items to the backpack. Unmarked items remain in the chest.
Alternatively, press **X** anywhere in the open chest to transfer **all
remaining items**, regardless of selections. Whenever the last item is
taken (either by X or by selecting them all via A), the chest closes
automatically. Press **B** to close it without taking the rest.
Start/R3 may open GameMenu from the chest.
The chest and backpack pause the world through SkyvalUiPause.

The starter outfit is **equipped**, not duplicated in the backpack.
The backpack initially contains **no spare clothes**. The chest contains
seven test garments: white shirt, green polo, black long-sleeved top,
brown pants, navy cuffed pants, brown boots and black shoes.
The **armor chest** contains three distinct pieces: a leather vest
(**Light armor +2**), reinforced vest (**Light armor +3**) and plate
cuirass (**Heavy armor +5**). Neither chest grants items at startup:
loot must be selected with A or collected all at once with X. Each
chest is depleted and persisted independently. Items are unique and
are never generated merely by cycling clothing or armor selectors.

Open the backpack with Select/L3. The horizontally scrollable tabs are
**Clothing / Одяг**, **Armor / Броня**, and **Weapons / Зброя**.
Switch with L1/R1 or select the tabs by mouse/touch; page contents slide
horizontally while the 3× portrait stays fixed. Tab navigation is **bounded**:
L1 on the first tab or R1 on the last tab does nothing. **Weapons** remains
an empty placeholder. **Armor** now has a working, single-field cyclical
selector with the owned options only (including None), live 1/N count
and the same 12px full-width selection background. Switching armor
returns the previously equipped piece to the backpack, updates the
class/defense panel and checkpoints progress.
The Clothing tab retains the **original six selector rows**: Top,
Top color, Pants, Pants color, Shoes and Shoes color, with their
left/right arrows. On the right edge of each field name, a 14px
`current/total` counter (e.g. `2/10`) shows the active choice among
**owned selectable choices**. The `None` option counts as a valid
style choice; color selectors show `0/0` when the slot is empty.
Character appearance fields also show these counters, using the ordered
LPC appearance options. Counters update after selecting an item and
after opening the menu.
The selectable values now come only from clothes the character already
wears or has taken from the chest. **No separate Equipped / In backpack
sections** are displayed. The player's unused owned garments remain in
the backpack state and become available through the original selectors.
Changing the style equips an owned garment (returning the previous one
to the backpack); changing its color cycles only through *owned*
variants of that style. Selecting **None / Немає** in a style row
unequips the garment. Clothes and armor alternatives remain **cyclic**
(last choice returns to first), while navigation between
parameter rows, between backpack tabs, in the main menu and in the chest
is **non-cyclic**. Character appearance choices are also bounded
(first/last value does not wrap). If no clothing alternatives are owned,
the relevant arrows are disabled. The LPC sprite validation still applies: failed changes
leave items and appearance untouched.

The game checkpoints after taking items and after equipment changes.
The backpack, equipped slots and **both chests'** remaining contents
are written in the same v1 save. Loading older v1 saves without inventory
starts with an empty backpack and unopened chests, while keeping the
saved character appearance. Loading existing saves that predate armor
preserves their original clothing-chest depletion and initializes
the new armor chest once, without resetting their clothing or position.

## Armor classes and portrait information

The 3× character portrait and its bottom divider have moved **upward**
to make room for a two-line status block inside the right-side preview:

- `Тканина` / `Cloth`, followed by `Броня +0` / `Armor +0`
  for the existing clothing-only character
- `Легка броня` / `Light armor`: default protection **+2**
- `Важка броня` / `Heavy armor`: default protection **+5**

These are **prototype game-balancing numbers**, not ratings from LPC.
Every current ordinary clothing item declares `armor_class: "cloth"`
and `armor_value: 0`. Armor loot declares light/heavy classes and
item-specific protection: +2, +3 or +5. The item catalog also supports
class-specific defaults and per-item protection overrides.
`SkyvalInventory.get_total_armor()` sums equipped protection, while
`get_equipped_armor_class()` reports the highest equipped class.
`compare_item_armor(item_id)` calculates the change relative to the
currently worn item in the same slot without equipping anything.
The lower portrait panel currently displays the total for equipped items;
prospective comparisons can use the comparison method in future equipment
selection UI. Current saves remain compatible because these stats are
looked up from item definitions, not added to save-file contents.

### Universal LPC armor candidates (bridge catalog, 2026-11-15)

The connected **Kvoka File Bridge** directory listing for the local
`/home/serhii/Godot/res` resource folder confirms these exact paths:

- `assets/lpc_sprites/torso/armour/plate/female/brass.png`
- `assets/lpc_sprites/legs/armour/plate/female/brass.png`
- `assets/lpc_sprites/feet/armour/plate/female/iron.png`
- `assets/lpc_sprites/shoulders/plate/female/bronze.png`
- `assets/lpc_sprites/torso/armour/legion/male/ceramic.png`

The connected folder also contains `addons/Universal_LPC/resources/`
with many spritesheets, but the brief catalog view did not establish
complete male/female variant coverage or which light armor pieces should
be imported. The LPC renderer now *optionally* overlays the matching
heavy torso layer when `plate_cuirass` is equipped: female brass plate
or male ceramic legion. If the corresponding valid sheet is absent,
armor still equips and grants defense; its base garment remains visible.
Light armor likewise works mechanically without a verified sprite overlay.
Future work should verify both body types and licenses before shipping
the full armor sets to PortMaster.

## Pause and Back navigation

The autoload `SkyvalUiPause` (`ui/pause_manager.gd`) tracks every blocking UI
owner. The first open interface pauses the SceneTree: world nodes
using inherited/pausable processing stop, including player movement, NPCs,
ordinary animations and Timer nodes. For future gameplay timers created via
`get_tree().create_timer()`, pass `process_always=false` so they also pause.
Nodes explicitly set to always-process remain active. The last closing
interface restores the pause state from before the first UI was opened.
Transitions between the backpack, both test chests, main menu and standalone
appearance window transfer pause ownership **before** closing the previous
layer, preventing an unpaused frame during the transition.

Blocking interfaces must use `Node.PROCESS_MODE_ALWAYS` for their own
controller navigation, and call
`SkyvalUiPause.set_open(self, true/false)` whenever they open/close.
**B** moves one level back: Settings → Main Menu → World,
or Backpack / TestChest → World. No on-screen Back button is required.
**Select/L3** toggles the backpack; **Start/R3** toggles
the global menu while playing. At launch, neither gameplay nor the backpack
can be entered until a valid Continue or a *completed* character creation.
The appearance editor also exposes `open_for_edit()` for future NPC or
other world interactions, with `confirmed` and `cancelled` signals.

The creator pauses world movement. Its right-stick rotation cycles through
**front → right → back → left → front**, one 90° step per horizontal tilt.
The stick must return to center before another step. Vertical right-stick
motions do nothing in the creator.

The backpack and standalone appearance editor share the same 3×
character portrait and single-column full-width selectors. They remain
**separate windows**; only the backpack has category tabs (Clothing,
Armor, Weapons), while the appearance creator has none. Fixed panel insets
(7px), field group spacing (12px), symmetric **inner padding**
(12px on all four sides of each field), and spacing between a field's
heading and selector (5px) preserve the 320×240 layout. Each highlighted
field's background and border span the **entire available width** of the
left scrollable column. Individual fields no longer draw horizontal
divider lines; spacing and the active background distinguish them.
Field headings and counters stay at 14px or larger. The clothing list scrolls vertically with a hidden
scrollbar; the tab strip scrolls horizontally and auto-reveals the active
tab. L1/R1 switch backpack tabs with a slide transition. Horizontal
right-stick flick rotates the portrait ±90°. The appearance window
shows a fixed X hint instead of a button at the end of its fields; X
opens a separate A/B confirmation dialog.

**Minimum UI font size: 14** at the 320×240 logical resolution.
All visible labels, gamepad hints, status text, menu buttons and chest
prompts must use at least 14, including future tabs and dialogs.
The shared label builders in `ui/character_creator.gd`,
`ui/game_menu.gd` and `world/test_chest.gd` enforce this minimum.
The two defense labels in the right-side portrait were enlarged from
11 to 14 and widened to fit localized class names. Do not shrink text
below 14 to work around tight layouts: adjust spacing or wrap text.

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

Empty clothing styles display **None / Немає** in both the style
and color fields. Changing a style to None returns the worn item to
the backpack. There is no quick-undress shortcut or in-world language switch.

## Appearance and localization

The standalone appearance window changes LPC body type (male/female),
skin, eyes, hairstyle and hair color. Clothing is now selected from
owned items in the backpack, not through unrestricted style/color cycling. Body, head, hair and
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
- `ui/character_creator.gd`: shared controller UI, instantiated as Backpack and reusable AppearanceEditor
- `inventory/inventory_state.gd`: physical item catalog, bag, equipment and chest persistence
- `world/test_chest.gd`: visible house-side chest with multi-select loot UI
- `prototype/camera_test.gd`: ensures the independent AppearanceEditor is created at runtime
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
