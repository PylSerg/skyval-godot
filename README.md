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

## Main menu, in-game menu and save slots

Skyval starts paused in the **main menu**. The initial viewport is 320×240.
The main menu contains, in order:

- **Continue / Продовжити**: immediately loads the most recently saved
  snapshot across all characters (the newest manual save or quick save,
  including an initial character profile when no other saves exist).
  Snapshot creation timestamps (`saved_at`), not menu-opening checkpoints
  or last character launch times, determine which save wins.
- **Select Character / Вибрати персонажа**: opens the character list ordered
  by last launch; select **A** to confirm loading that character's newest
  snapshot; **X** to delete the character and all its snapshots with
  confirmation; **B** to go back.
- **New Game / Нова гра**, **Settings / Налаштування**, **Quit / Вихід**.

Continue and Select Character are **hidden**, rather than disabled, until
at least one valid profile exists. There are no blank rows in that case.

During gameplay, **Start / R3** opens a separate **in-game menu** with:

- **Quick Save / Швидке збереження**: overwrite only the current
  character's dedicated quick-save snapshot.
- **Quick Load / Швидке завантаження**: load the current character's
  quick-save snapshot, with an A/B confirmation. Unavailable until a
  quick save exists.
- **Save / Зберегти**: create a new, timestamped manual save slot for
  the current character without overwriting prior manual slots.
- **Load / Завантажити**: browse this character's current profile
  checkpoint, manual snapshots and quick snapshot, newest first.
  Selecting a save requires A/B confirmation.
- **Settings / Налаштування** and **Main Menu / Головне меню**.
  Returning to the main menu requires A/B confirmation and retains
  the latest live checkpoint. B/Start closes the in-game menu.

The same confirmation behavior is used for selected character loads.
Selecting Continue automatically loads the most recent snapshot,
without an extra prompt.

### Creating characters

**New Game** starts a draft at the spawn point and opens the separate
**Appearance / Зовнішність** editor. Configure body type, skin, eyes and
hair. Press **X**, then **A**, to confirm appearance. This only moves to
the name screen, not to a saved profile.

The **character-name** screen shows a row of 14px Cascadia name slots,
followed by an eight-column grid of Ukrainian or English letters, space
and backspace. Maximum length is computed from the available width;
both sticks and D-pad navigate. **A** picks a letter, **Y** suggests a
gender-appropriate random name, **X** confirms the name with a modal,
and **B** returns to the main menu with a modal. Empty names cannot be
confirmed. Cancelling does not create a profile or save.

New characters get gender-specific starting LPC outfits: male starts
with formal trousers, female with formal trousers and a T-shirt.
Both begin without shoes. The draft inventory is discarded on cancel.

### Where saves go

Each character keeps a persistent `<identifier>-<name>.json` root
checkpoint in `saves/`. Quick saves use `<identifier>-<name>~quick.json`
and manual slots use `<identifier>-<name>~save-<timestamp>-<nonce>.json`.
The files contain version-2 JSON with identity, position, appearance,
equipped items, inventory and chest state. Snapshots track `saved_at`;
the profile itself tracks `last_played` for character-list sorting.
Checkpoint writes (menu openings, chest/inventory changes and returning
to the main menu) do not overwrite manual or quick snapshots.

The folder is created on the first save and ignored by Git. On R36H,
the PortMaster launcher sets `SKYVAL_SAVES_DIR` to
`/roms/ports/skyval/saves`; on desktop it defaults to `user://saves`.
Existing v2 character files are recognized as profile checkpoints,
with no migration needed. Legacy `user://skyval_save_v1.json` remains
untouched and is not automatically converted.

The selected UI language is stored separately in
`user://skyval_settings.cfg`. The backpack is available only in
gameplay; the game remains paused in any main/game menu or confirmation.

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
three found armor pieces. The other positions currently show **None /
Немає (1/1)** and disabled arrows until real items and LPC art exist
for those areas. New empty slot keys are included in the save state;
existing shirt, pants, footwear and torso-armor save keys are retained,
so older saves remain compatible.

A full-width selection background, 12px all-around inner padding and
14px or larger text remain in both categories. The selected row heading
and the selected tab label use the **exact gold color of their borders**
(`#e7ca86`), while the equipment value text stays neutral. The main
menu's active option uses the same gold border/text accent, including
when hovered or pressed.

**First-open layout stabilization (2026-11-15 recording):**
The first Clothing page was created while the entire overlay was hidden
and its column did not yet have a final viewport width. The recording
showed counters cut off at the right edge and partially invisible right
arrows on Clothing, while switching to Armor produced a correctly sized
page. The overlay now rebuilds the initial Clothing scroll page after
the visible panel completes its first layout pass (using the same
creation route as tab switching), resets to Head and scroll position
zero, and only reveals the page after its layout has settled. An opening
generation guard prevents late asynchronous layout work from modifying
a subsequently closed/reopened menu. Field names and buttons remain
anchored inside the page width, and longer item names keep their own
clipped horizontal marquee. This fix is based on recorded behavior and
source inspection; it still needs a Godot runtime retest.

**Compact choice arrows:** The shared five-field equipment selector and
the appearance creator use the same compact 14px-wide left/right
buttons (down from 22px). Their chevron font stays at the 14px minimum
and button content padding is removed, while the 21px button height is
unchanged. Only 2px of gap is reserved on either side of the name
viewport, so the full item/appearance label gains 16px of space. Long
values retain the horizontal forward/back marquee. Heading counters,
12px panel padding and the first-open sizing fix are unchanged.

Each row has a right-edge
`current/total` counter such as `2/5`, counting **only equipped or
owned physical items**. **None / Немає never contributes to either number**:
an empty slot with no owned items shows `0/0`, no equipped item with
three owned choices shows `0/3`, and equipping the second of those
three items shows `2/3`. None remains a valid cyclic selector choice
for unequipping; only its counter representation changes. Character
creation appearance counters continue to count all real appearance
choices normally. Item names are never abbreviated; when needed,
their label scrolls smoothly forward and back.
Pressing left/right cycles through actual items for that body area,
returning replaced equipment to the backpack. Clothing and armor tops
remain mutually exclusive; putting on either returns the other to the
backpack. There are no separate "Equipped" and "In backpack" sections.

**Navigation rules:** moving between fields, tabs, menu items and chest
rows stops at the first/last entry (no wrapping). Item choices **and
appearance choices** (gender, skin, eyes, hair style and color) wrap
cyclically. The creation screen still has no separate Create button:
press X to open confirmation, then A to create or B to cancel.
The left/right arrows in the appearance screen therefore stay enabled
at both ends when multiple options exist. Invalid or missing LPC
alternatives are skipped without modifying the current appearance.
Unobtainable clothes or armor are not silently added.

The game checkpoints after taking items and after equipment changes.
The backpack, equipped slots and **both chests'** remaining contents
are stored in each character's v2 profile. The inventory subsystem still
supports missing legacy inventory fields if a profile was converted
externally; automatic migration from the single v1 save is not enabled.
Saved outfits and armor still depend on available LPC art.

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
