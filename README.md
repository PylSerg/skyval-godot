# Skyval

Pixel-art top-down RPG prototype for Godot 4.7 (Compatibility renderer), targeting an R36H with a 320×240 logical viewport, shown as 640×480.

## Character Creator v2.4: gender, outfits, localization

Press **C** in the test world to open the character creator. Press **C**, **Esc**, or the **Close** button to return to the game. While the creator is open, movement/camera physics are paused.

The editor has two tabs:
- **Appearance:** male/female body type, skin tone, eye color, and hair color.
- **Clothing:** independent choices for the styles and colors of shirt, pants, and footwear (five styles per slot).

Left/right buttons move through the choices. The preview displays the actual LPC layers in 2× pixel art without importing additional image sheets. Changes are applied immediately.

### Localization from one file

**All in-game interface strings are stored in [localization/strings.json](localization/strings.json)**, with two complete dictionaries: \`uk\` (Ukrainian, the default) and \`en\` (English). The menu code contains only stable translation keys, not visible phrases.

Click **УКР / ENG** in the editor header to switch language immediately. The preferred language is saved to \`user://skyval_settings.cfg\` across launches. The autoload \`SkyvalLocale\` provides \`SkyvalLocale.t("ui.title")\`; a future interface should use its translation keys too. To add another language, supply the same keys in \`strings.json\`, then expose it through the locale selector.

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

The real Universal LPC sprites are combined from the body (z=10), pants (z=20), boots (z=25) or shoes (z=15), shirt (z=35), head (z=100), face (z=101), eyes (z=105), and hair (z=120). Frames use 64×64 LPC sheet cells, with idle starting at Y=1408 and walk at Y=512, north/west/south/east row order.

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

**Testing:** GitHub changes and LPC source paths are checked. Full Godot 4.7.2 execution on the developer's Linux machine still needs to be verified.
