# Skyval

Pixel-art top-down RPG prototype for Godot 4.7 (Compatibility renderer), targeting an R36H with a 320×240 logical viewport, shown as 640×480.

## Character Creator v2.5: optional clothing, gender, outfits, localization

Press **C** in the test world to open the character creator. Press **C** or **Esc** to close it from the keyboard. On a controller, use **Start/X** to open or close it, or **B** to close it. While the creator is open, movement/camera physics are paused.

**Menu controls:** Up/Down selects a row; Left/Right changes it; Q/E changes tabs; Enter advances an option. I/J/K/L (right stick via PortMaster) rotates the portrait in four directions. The selected row is highlighted in gold; key repeats are filtered. On R36H, Start/X opens or closes, L1/R1 switches tabs, and B closes. There is no creator language switch or quick-undress action. See [portmaster/README.md](portmaster/README.md).

**USB controller on desktop:** Start/X opens/closes, A advances the value, B closes, L1/R1 changes tabs. D-pad and left stick navigate, while the **right stick rotates the 3× LPC portrait**. Y and Select have no creator actions. PortMaster's staged PCK sets `skyval/input/keyboard_emulated_gamepad=true` to avoid duplicate GPtoKEYB inputs.

The compact 320×240 editor contains only two tabs, appearance controls and a **large 3× portrait**. The preview fills nearly the entire right column. The title, preview caption, help footer, language switch and quick-undress button have been removed. Language selection will belong to global Settings.

The editor has two tabs:
- **Appearance:** male/female body type, skin tone, eye color, **five hairstyle shapes** (buzzcut, bedhead, curtains, mop, spiked), and hair color.
- **Clothing:** independent choices for shirt, pants and footwear (five styles **plus None** per slot), with separate color settings.

Left/right buttons move through the choices. The preview draws synchronized idle frames at 3× nearest-neighbor scale without loading extra sheets. Right-stick rotation changes this portrait only, not the paused in-world character.

### Empty clothing slots and NPC reactions

Each style selector now includes **None / Немає**. Removing a style removes only the associated clothing sprite layer; the base body and head stay visible. It works for male and female LPC types. Color selection is preserved even while a slot is empty.

There is **no quick-undress button** in the creator. Set each clothing style to **None / Немає** to remove items individually. The wardrobe-state API remains available for future NPC reactions.

Future NPC dialogue and quests can use these stable methods on the LPC character node:
- `get_clothing_state() -> Dictionary`: keys `shirt`, `pants`, `footwear` and `fully_undressed` (booleans).
- `is_fully_undressed() -> bool`: true only when **all three** garment slots are empty.
- `clothing_changed(state: Dictionary)`: signal emitted when a successful change alters which slots are covered.

These methods are also exposed to gameplay through `SkyvalCharacterVisual.get_lpc_clothing_state()` and `is_lpc_fully_undressed()`. NPC dialogue is not added yet.

All user-visible text remains in `localization/strings.json` (Ukrainian and English).

### Localization from one file

**All in-game interface strings are stored in [localization/strings.json](localization/strings.json)**, with two complete dictionaries: \`uk\` (Ukrainian, the default) and \`en\` (English). The menu code contains only stable translation keys, not visible phrases.

Language selection will live in the future **Settings** menu. The current preference is already saved in `user://skyval_settings.cfg`, and `SkyvalLocale` supplies localized strings. To add another language, supply the same keys in \`strings.json\`, then expose it through the locale selector.

### Female and male LPC assets

The body-type switch updates the body, matching human head/face, clothing torso variant, and \`male\` versus \`thin\` trousers/shoes variants. Existing skin tone, colors, hairstyle, and clothes are retained when the alternate resources are available. If any required sheet fails to load, the current complete appearance stays unchanged.

The external LPC library under \`$HOME/Godot/res\` is searched automatically. If using an absolute directory override ending in \`male\` or \`female\`, it also adapts when switching types. To bundle a build for the handheld, provide only the required, correctly attributed LPC sheets under \`res://assets/characters/lpc/\`, retaining the original \`spritesheets/\`-relative folder structure.

### Existing game controls

| Key | Action |
|---|---|
| Arrows / left stick | Walk, including four facings |
| I / J / K / L, right stick | Smooth camera look-around |
| C | Open/close character creator |
| 1 | Cycle LPC shirt color |
| 2 | Cycle LPC hair color |
| 3 | Cycle LPC pants color |
| 4 | Switch LPC / old procedural preview |
| 5 | Cycle LPC skin tone |
| 6 | Cycle LPC footwear color |
| 7 | Cycle LPC shirt style |
| 8 | Cycle LPC pants style |
| 9 | Cycle LPC footwear style |

Old prototype controls are preserved when the procedural preview is selected.

### Current character layers

The real Universal LPC sprites are combined from the body (z=10), optional pants (z=20), optional boots (z=25) or shoes (z=15), optional shirt (z=35), head (z=100), face (z=101), eyes (z=105), and hair (z=120). Frames use 64×64 LPC sheet cells, with idle starting at Y=1408 and walk at Y=512, north/west/south/east row order.

The default starting outfit is a blue short-sleeved shirt, charcoal pants, brown boots, black buzzcut, and blue eyes.

This code reads a **local asset library without copying it into Git**. A small licensed asset selection will eventually need to be packed for R36H, and credits retained. See [LPC artwork licensing](https://github.com/csaga77-godot-addons/universal_lpc/blob/main/artwork_credits/ARTWORK_LICENSING.md).

## Project files

- \`project.godot\`: Godot viewport + \`SkyvalLocale\` autoload
- \`prototype/camera_test.tscn\`: runnable scene and editor CanvasLayer
- \`prototype/camera_test.gd\`: test world and camera boundaries
- \`prototype/smart_camera.gd\`: camera follows hero, right stick explores
- \`prototype/player.gd\`: movement and debug hotkeys
- \`characters/character_visual.gd\`: appearance facade and procedural fallback
- \`characters/lpc_body_visual.gd\`: all LPC visual layers and clothing/gender change API
- \`ui/character_creator.gd\`: localized two-tab editor, keyboard shortcuts
- \`ui/character_preview.gd\`: live LPC preview
- \`localization/localization.gd\`: JSON localization provider and saved preference
- \`localization/strings.json\`: all displayed text (UK/EN)

**Testing:** GitHub changes and localization keys are checked. The new clothing toggles still need runtime verification in Godot 4.7.2 on Linux.
