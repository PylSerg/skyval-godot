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
| A | Interact with nearby test chest | Equip/unequip highlighted item (confirm selection) |
| L1 / R1 | Reserved | Previous / next backpack tab |

Press **Select / Back** or **L3** in the world to open the **backpack**.
Press **Select/L3** again to close it, or use **B** to return to the world.
**X** is not a Back shortcut. **Appearance** is a separate,
reusable window which is opened during New Game, not a backpack tab.
Press **Start** or **R3** during gameplay to open the global menu.
The world pauses while a blocking interface is open.

## Main menu, in-game menu and character save folders

Skyval starts paused at 320×240 in the **main menu**.

The **title screen** uses the 320×240 Skyval sunset illustration as a
full-screen background (`assets/images/title_bg.jpg`). Its menu stays
in the original **top-to-bottom order**: Continue, Select Character,
New Game, Settings, Quit. The entire list is centered horizontally and
anchored to the **bottom edge** with a small margin, so shorter menus
move downward instead of reversing their order. Up/down on the D-pad and stick follow the visual
order. Once a submenu opens, the normal readable framed menu is used.
The separate in-game menu keeps its existing layout and options.

The title artwork is a separate 320×240 JPEG resource at
`assets/images/title_bg.jpg`; the PortMaster build script copies it
into the PCK. If the file is absent,
the menu falls back to its dark overlay without changing gameplay.



- **Continue / Продовжити** resumes the **last opened character**.
  `saves/last_opened.json` keeps its ID between launches; if the marker
  has not been created yet, the most recently opened valid profile is used.
  The most recently created manual or quick save **for that character**
  is loaded, using `saved_at` (with the root checkpoint as a fallback).
  Characters with newer saves do **not** steal Continue from the last
  character you played.
- **Select Character / Вибрати персонажа** appears when profiles exist.
  The list is ordered by last launch. **A** opens the **selected
  character's complete save list**; **B** returns to the main menu,
  **X** deletes that character and its saves with confirmation.
  Choose a save with **A** to load it immediately, **without a
  confirmation**. From the save list **B** returns to the character list.
- **New Game / Нова гра**, **Settings / Налаштування**, **Quit / Вихід**.

Continue and Select Character are entirely **hidden** if no valid
characters exist, so the menu begins with New Game.

During gameplay **Start / R3** opens a separate **in-game menu**:

- **Quick Save / Швидке збереження** overwrites just this character's
  `quick.json` and automatically closes the in-game menu after success.
  On a write failure, the menu remains open and reports the error.
- **Quick Load / Швидке завантаження** loads that snapshot immediately,
  **without a confirmation dialog**, automatically closes the menu on
  success, and is disabled until a quick save exists for the character.
- **Save / Зберегти** opens the same 14px controller keyboard as character
  creation. Enter a **save name** (A: letter, Y: random suggestion,
  X: accept, B: cancel), then confirm it with A/B. Each confirmed name
  creates a separate manual save with a unique filename; the human-readable
  title is stored in `save_name` and shown in the save list.
- **Load / Завантажити** displays saves for the current character, sorted
  by creation time, newest first. Loading a selected save requires A/B
  confirmation.
- **Settings / Налаштування**, **Title Screen / Головний екран**,
  and **Quit Game / Вийти з гри**. Both actions require A/B confirmation.
  Returning to the title screen keeps the game running in the main menu;
  Both actions warn that **unsaved progress will be lost**. Returning
  to the title screen or quitting does **not** create a save.

**There is no gameplay autosave.** The only automatic progress write is
the initial `profile.json` created once after the player confirms a
new character's name. From then on, progress is saved **only** by
choosing Quick Save or Save in the in-game menu. Opening menus,
equipping items, looting chests, loading snapshots, returning to the
title screen and quitting never write game progress. In particular,
Quick Save and named Save take the current position, look, inventory and
chest contents directly from the running session; they do **not**
overwrite `profile.json` first.

The last opened character is updated on every successful load and after
new-character creation in `last_opened.json`. This stores only the
character ID and launch-order timestamps, not any game progress.

### Unified Skyval window design (320×240)

All windows use `ui/skyval_theme.gd` for translucent midnight-blue
panels, thin warm-gold borders, gold active-item outlines, readable
Cascadia text (minimum 14px), and common button states. The shared style
covers in-game menus, settings, character/save lists, confirmation
dialogs, both loot chests, the name-entry keyboard, manual-save naming,
character appearance and equipment screens. Window proportions
are now adapted per purpose at 320×240 rather than stretching all
submenus to a single fixed height. The title menu retains its original
bottom-centered layout.

Any menu presenting alternatives uses **one vertical column**:
gameplay actions, character and save lists, loot-chest choices,
the Ukrainian/English language settings, and confirmation actions.
Long confirmation messages wrap within their own area, while the
full-width **A: підтвердити** and **B: скасувати** options each occupy
a separate row and also support mouse/touch activation.
Settings navigate with up/down (left/right still moves between
languages), and A confirms the highlighted language. The in-game
menu and lists preserve their existing gamepad navigation rules.
The name-entry **keyboard** intentionally remains an eight-column grid,
and item/appearance variations retain their compact left/right selectors.

The title screen retains its illustrated sunset and bottom-centered menu.
Character creation and character naming retain the dedicated creation
background. The backpack, chest dialogs, in-game menu and manual-save
name editor instead dim the **paused gameplay world** behind their
semi-opaque panels. The settings/save screens entered from the title
menu keep the Skyval title artwork behind them. No extra bitmaps are
required by the common theme, and the PortMaster builder already copies
the entire `ui/` directory into the PCK.

### Illustrated character creator (320×240)

The dedicated appearance editor now uses
`assets/images/create_hero_bg.jpg` as a full-screen background, plus
a translucent navy/gold control panel and a framed LPC character preview.
The five appearance fields remain visible together as a compact list:
body type, skin, eyes, hairstyle and hair color. One shared selector below
the list shows and changes the highlighted field's actual value and
retains the original field counters. The hairstyle selector includes
**None / Немає**, which hides the hair sprites completely and appears
as **0/5** (the five nonempty hairstyles are numbered 1/5 to 5/5). The D-pad and left stick move through the list or change its value,
right-stick horizontal flicks rotate the portrait by 90°.
**During creation:** A does nothing, B returns to the main menu,
Y randomizes the body type, skin, eyes, hair style and hair color (using
valid LPC assets), and X immediately advances to character-name entry.
There is no extra A-confirmation after X. Inventory A still equips gear.
The backpack now shares this compact five-field layout and the same
gold-accented, translucent panel styling. Unlike creation, its background
is the **paused gameplay world**, not the appearance illustration.
The portrait keeps the armor statistics below the character.

### Character creation

New Game opens the appearance editor. Choose the body, eyes and hair
with left/right, or press **Y** to randomize the entire look. Press
**X** to go directly to the character-name keyboard; **A** has no
action in creation, and **B** returns to the main menu.
The name-entry keyboard then appears. Its Ukrainian/English characters and space/backspace fit 320×240.
**A** picks characters, **Y** suggests a random gender-appropriate name,
**X** confirms with a dialog, and **B** immediately returns to the
**same appearance draft**, retaining all previously selected features.
Pressing X again advances to the name screen. Only a confirmed name
allocates a new profile. Default LPC outfits depend on
body type (male: formal trousers; female: trousers and T-shirt; both
start without shoes).

### Save layout and legacy migration

Every character now has a **separate folder** created on first save.
For example:

```text
saves/
  last_opened.json
  176320012312345-Софія/
    profile.json
    quick.json
    save-1763200900123-12345-Пригода.json
    save-1763201900456-67890-Нова_глава.json
  176320078956789-Данило/
    profile.json
    quick.json
```

`profile.json` stores the **initial creation save** and character identity.
Existing profiles migrated from older versions retain their saved state,
but are no longer overwritten by ordinary gameplay. `quick.json`
stores one explicit quick-save snapshot. Named manual saves are
independent timestamped files. The character ID and human-readable name
remain in the JSON data.

Existing v2 flat files (`<id>-<character>.json`,
`<id>-<character>~quick.json` and
`<id>-<character>~save-*.json`) are **moved into character folders**.
The migration never knowingly overwrites an existing file and can be
retried if interrupted. Flat files that could not be moved remain
readable. The original v1 `user://skyval_save_v1.json` is unchanged.

On R36H the PortMaster launcher uses
`/roms/ports/skyval/saves`; desktop Godot uses `user://saves`.
The `saves/` folder is ignored by Git and is created automatically.
The UI language stays in `user://skyval_settings.cfg`.

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

Open the backpack with Select/L3. **Every opening resets to the first
tab, Clothing / Одяг, with Head / Голова selected as the first field
and the list scrolled to the top**, regardless of the last-used tab.
The horizontally scrollable tabs are **Clothing / Одяг**,
**Armor / Броня**, and **Weapons / Зброя**.
Switch with L1/R1 or select the tabs by mouse/touch; page contents slide
horizontally while the 3× portrait stays fixed. Tab navigation is **bounded**:
L1 on the first tab or R1 on the last tab does nothing. **Weapons** remains
an empty placeholder.

**Clothing and Armor have the same five field positions**, in order:
**Head / Голова**, **Top / Верх**, **Bottom / Низ**,
**Hands / Руки**, **Feet / Ноги**. These are equipment locations,
not separate unrestricted color pickers. The Clothing top shows owned
shirts, bottom owned pants, and feet owned shoes. Armor top shows the
three found armor pieces. The other positions currently show **None / Немає (0/0)**
and disabled choice arrows until real items and LPC art exist for
those areas. New empty slot keys are included in the save state;
existing shirt, pants, footwear and torso-armor save keys are retained,
so older saves remain compatible.

### Compact backpack interface

The inventory now uses the same 320×240 visual language as character
creation: a translucent navy panel with a gold border, compact field rows,
a single shared item selector beneath the list, and a framed portrait on
the right. **There is no full-screen background image or opaque backpack
title card**; the paused game remains visible behind the interface,
lightly darkened for readability. The redundant “Рюкзак” heading has
been removed to leave room for the three tabs.

All five Clothing or Armor equipment locations are visible at once.
Move the selected gold-highlighted field with D-pad/left-stick up/down.
D-pad/left-stick left/right and the on-screen arrows **preview**
owned items **on the character portrait**, including visible clothing
and armor swaps, without changing equipped inventory data or writing a save.
The LPC appearance change is temporary: selecting another field/tab or
closing the backpack restores the actual worn outfit. Press **A** to
commit the previewed item (or unequip when the candidate is None).
Only a successfully confirmed equipment change updates inventory
ownership and the actual avatar; it does not save progress. Each row retains
a `current/total` counter that follows the previewed item. The **single
value selector** shows only the currently selected field and uses
14px-wide arrow controls and a clipped, horizontally scrolling item name
when necessary. The Weapons tab still shows its empty-category message
without a useless selector. The portrait is drawn at **3×**, rotates by
90° with the right stick, and keeps the armor-class/value text below a
gold separator. When browsing an item, the panel shows the **projected**
armor and its change in parentheses, e.g. `+5 (+3)` or `+2 (-3)`.
Positive changes are green, negative red; the preview also accounts
for a shirt being removed when armor is equipped. The pending item
name is gold until A confirms it, with an `A: екіпірувати` hint.
Tabs switch with L1/R1 or by clicking them.

The original first-open layout stabilization remains: on every opening,
the active tab resets to Clothing, the selected field resets to Head,
and the content is rebuilt after its viewport receives a stable width.
Page-slide animation, equipment-change persistence, disabled arrows for
unavailable slots, and all ownership/equipment logic are unchanged.
The font stays at or above 14px.

Each row has a right-edge
`current/total` counter such as `2/5`, counting **only equipped or
owned physical items**. **None / Немає never contributes to either number**:
an empty slot with no owned items shows `0/0`, no equipped item with
three owned choices shows `0/3`, and equipping the second of those
three items shows `2/3`. None remains a valid cyclic preview choice: pressing A while None
is highlighted actually unequips the slot. Browsing alone never does. Character
creation appearance counters continue to count all real appearance
choices normally. Item names are never abbreviated; when needed,
their label scrolls smoothly forward and back.
Left/right previews actual items for that body area; pressing A commits
the selected change and returns replaced equipment to the backpack.
Clothing and armor tops remain mutually exclusive; putting on either
returns the other to the backpack. There are no separate "Equipped" and "In backpack" sections.

**Navigation rules:** moving between fields, tabs, menu items and chest
rows stops at the first/last entry (no wrapping). Item choices **and
appearance choices** (gender, skin, eyes, hair style and color) wrap
cyclically. The creation screen still has no separate Create button:
press X to continue directly to the name screen, Y for a random
appearance, or B to return to the main menu. A is intentionally inactive
on the creation screen. Left/right choice arrows stay enabled at both
ends when multiple options exist. Invalid or missing LPC
alternatives are skipped without modifying the current appearance.
Unobtainable clothes or armor are not silently added.

Taking items and equipping gear only change the live session. Those
changes are written when the player explicitly chooses Save or Quick
Save. The backpack, equipped slots and **both chests'** remaining contents
are included in each explicit save; the original creation profile remains
untouched. The inventory subsystem still supports missing legacy fields
if a profile was converted externally; automatic migration from the
single v1 save is not enabled. Saved outfits and armor still depend on
available LPC art.

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

The connected bridge's **folder tree** confirms a complete
`addons/Universal_LPC/resources/spritesheets/torso/armour/` category
with these subdirectories for both `female` and `male`:
`leather/`, `legion/` and `plate/`. The current bridge view does **not**
expose the exact PNG filenames or bitmap contents inside those
directories. On the actual user's machine, the LPC renderer discovers
the existing PNG files dynamically, tries preferred material colors
first, and accepts a sheet only if its atlas has the supported 64×64
idle/walk frames.

The temporary, hand-drawn pixel armor has been **removed**.
The armor items now map to distinct genuine LPC torso categories:
`leather_vest` → `leather`,
`reinforced_vest` → `legion`, and
`plate_cuirass` → `plate`.
The loader does **not** silently substitute leather for legion or
legion for plate. It also checks the alpha coverage in all four
walking/idle directions for legion and plate atlases; a sheet that is
large enough but empty from the front is not accepted.
Both `res://addons/Universal_LPC/resources/spritesheets` and the
external `~/Godot/res/addons/Universal_LPC/resources/spritesheets`
are searched, independently of the body sheet's source folder.
When no suitable sheet exists, equipping **fails without removing the
currently worn garment or claiming armor protection**. The user
keeps the armor in the backpack; previously saved armor items are
preserved in the backpack if their source art is missing.

**Armor stability fixes (log and recording, 2026-11-15):**
A reported `leather vest has no verified front layer` warning stopped
every attempt to select the first owned armor item. The sleeveless
authentic LPC lining (`torso/clothes/sleeveless/sleeveless/<female|male>/`,
at z=40) is now **optional**: the primary real LPC leather armor
remains the required layer, and missing lining no longer traps the
selector. Cycling also skips other armor pieces whose original LPC
images cannot be loaded, without consuming them. The leather armor
can still look partially bare from the front until an appropriate
real sleeveless sheet is installed; this is explicitly a remaining
visual limitation, not a substitute drawn with procedural pixels.

When a change fails, the live LPC sprites are already intact because
validation happens before sprite replacement. The state is restored
without reloading the previous large PNGs. External LPC textures now
have a bounded 10-atlas cache, and both successful and unsuccessful
armor-path discoveries are remembered for the session. That avoids
repeated directory scans and most repeated PNG decoding.

The persistent solid-white portrait seen in the recording is addressed
by extracting real **64×64 RGBA frames** from the underlying source
atlas, caching those frame textures, and drawing the cropped textures
instead of rendering an `AtlasTexture` region through the GPU. Frames
from deleted sprites are ignored and portrait caches are invalidated
after every outfit change. This change is based on the reported log
and video, **not yet verified by launching Godot**.

**Armor preview idle/walk fallback (recording, 2026-11-15):**
The latest recording shows the leather vest nearly absent on the back,
while the reinforced and heavy armor look normal from the front.
The 3× portrait now inspects the central-torso pixels of each authentic
LPC armor idle frame and compares it with all available walking frames
for the *same facing*. If a walking frame has substantially more visible
armor, the portrait displays the clearest matching walking frame instead.
Other LPC layers (body, face, hair, pants, shoes) continue to show their
ordinary idle frames. The selected armor frame is static, not animated,
and cached until the outfit changes.

**In-world standing uses the same fallback:** when building an Armor or
ArmorVestFront SpriteFrames layer, the LPC renderer checks torso coverage
for all idle poses in each of the four directions against the eight walk
frames in that same direction. If an idle pose is materially incomplete
and a walk pose is visibly better, it reuses that single real walk frame
for the *entire idle cycle* of that direction, preventing flicker while
standing. This selection is performed once when the armor layer is
built. Walking animations, the player's other body/clothing layers,
equipment behavior and armor stats remain unchanged. No new artwork
is generated. If neither action contains an appropriate frame,
the corresponding source LPC sheet still needs correction.

**Torso exclusivity:** Equipping torso armor sets shirt style to
`none` and returns the previously equipped shirt to the backpack.
Equipping any shirt sets armor style to `none` and returns its armor
item to the backpack. This is one atomic visual transition, followed
by inventory mutation only on success. Pants and shoes are not removed.
Older saves containing both a worn shirt and armor are repaired on
load, keeping the shirt as a backpack item. Armor removal leaves
the torso bare until the player selects a shirt again.

These local full-size sheets are **not automatically bundled into
R36H/PortMaster exports**. For standalone builds, copy the licensed
necessary sprite sheets into the project's packed resource paths and
verify the exported atlas and licenses. Do not ship the 900 MB source
tree by accident.

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
