# Skyval

Godot 4.7 top-down RPG prototype with the GL Compatibility renderer, built for a 320×240 logical viewport (R36H display: 640×480).

## Character System v2.3: modular LPC clothing styles

The game reads **real Universal LPC spritesheets** for the body, human head, face, eyes, short hair, **shirt, pants and boots** from the local art library. All available layers animate together in four directions. The original GDScript-drawn character remains available as a fallback. No changes were made to the tested movement, collision, camera, or world.

### Controls

- **Arrow keys / left stick**: movement, including facing and walking animations.
- **I/J/K/L / right stick**: smooth camera look-around.
- **4**: switch between real LPC body and original prototype avatar.
- **5**: cycle real LPC skin variants (light, amber, olive, brown, bronze).
- **1**: change LPC shirt color (prototype outfit color when LPC is off).
- **2**: change LPC hair color (prototype hair color when LPC is off).
- **3**: change LPC pants color (toggle prototype sword when LPC is off).
- **6**: change LPC footwear color.
- **7**: cycle **LPC shirt style**.
- **8**: cycle **LPC pants style**.
- **9**: cycle **LPC footwear style**.

Color and style are separate choices. The five style options per slot use the existing LPC animation rows; switching doesn't change the camera, movement, or player hitbox.

### Finding the actual LPC sprites

The required file is `body/bodies/male/light.png` from the user's Universal LPC resource library. The game checks common directories under `$HOME/Godot/res`, including:

- `assets/lpc_sprites/body/bodies/male/light.png`
- `assets/lpc_sprites/spritesheets/body/bodies/male/light.png`
- `addons/Universal_LPC/resources/spritesheets/body/bodies/male/light.png`
- `addons/universal_lpc/resources/spritesheets/body/bodies/male/light.png`

If your folder layout differs, open `prototype/camera_test.tscn`, select **Player → CharacterVisual** and set **External Body Directory** to the **absolute folder path** containing `light.png`. Keep this machine-specific value out of commits unless intentionally shared.

On startup, if the body, head, shirt, pants or boots is missing or invalid, Skyval retains the working procedural preview and prints a warning. Face, eye color and hair remain separate optional layers. Layers are found relative to the selected body sheet, so all resources must share the original LPC directory tree. The game does not copy or index the entire asset library.

### Clothing layers and paths

The v2.2 starting outfit is **blue short-sleeved shirt**, **charcoal pants**, **brown basic boots**. These are local assets and are **not** committed to this repo.

| Layer | Path relative to `spritesheets/` | LPC z-index |
|---|---|---:|
| Pants | `legs/pants/male/charcoal.png` | 20 |
| Boots | `feet/boots/basic/male/brown.png` | 25 |
| Shirt | `torso/clothes/shortsleeve/shortsleeve/male/blue.png` | 35 |

All three are sampled from the **same animation rows and 64px cells** as the body and head. If a garment's texture is missing, the complete new outfit is rejected instead of silently leaving an undressed or partially dressed hero. Female body type uses the `female` shirt sheet and `thin` legs/feet sheets.

### Clothing styles

Each slot has five tested LPC sprite directories and preserves its currently selected color while switching styles.

| Hotkey | Slot | Styles in cycle order |
|---|---|---|
| **7** | Shirts | Shortsleeve · T-shirt · Longsleeve · Sleeveless · Polo |
| **8** | Pants | Pants · Long Pants · Formal · Cuffed · Pantaloons |
| **9** | Footwear | Basic boots · Folded boots · Rimmed boots · Basic shoes · Revised shoes |

The initial outfit remains the blue short-sleeved shirt, charcoal pants and brown basic boots. Style changes retain independently chosen colors, using the same `male` or `female/thin` LPC sheet variants as the existing outfit. If a needed garment is missing, the character keeps the previous look and the program tries the next style. In Godot's **Output**, a successful change logs the selected style path.

Footwear uses LPC metadata depth sorting: **boots at z=25**, while **shoes at z=15** so the trousers can overlap them. Pants remain at z=20 and shirts at z=35. Each set of frames stays synchronized with the other character layers.

The style list is deliberately small and curated for the prototype. We can later drive it through a proper inventory/catalog.

### LPC animation layout

This code reads the full 64×64 LPC sheet using the standard metadata layout:

| Animation | Source Y | Frame columns | Rows |
|---|---:|---|---|
| Idle | 1408 | 0, 0, 1 | N, W, S, E |
| Walk | 512 | 1, 2, 3, 4, 5, 6, 7, 8 | N, W, S, E |

Each direction uses a row offset of 64 pixels. Sprite placement aligns the art with the existing player foot collision.

### R36H export and art credits

Absolute Linux paths are **development-only**. For handheld exports, pack a small set of approved PNG sheets at `res://assets/characters/lpc/body/male/` and adjust the loader if needed. Do not ship the full 900 MB resource library.

LPC artwork has mixed per-asset licenses and attribution conditions. Review [Universal LPC licensing guidance](https://github.com/csaga77-godot-addons/universal_lpc/blob/main/artwork_credits/ARTWORK_LICENSING.md) and retain the required credits when shipping resources.

## Project files

- `prototype/camera_test.tscn`: runnable smoke test.
- `prototype/camera_test.gd`: map and world bounds.
- `prototype/smart_camera.gd`: smooth camera and right-stick view.
- `prototype/player.gd`: movement and test keys.
- `characters/character_visual.gd`: appearance controller, fallback and optional addon integration.
- `characters/lpc_body_visual.gd`: real LPC layered sprite loader (body, clothes, head, face, eyes, hair) with synchronized idle/walk animations.

**Status:** Source, actual LPC directory paths and GitHub commits verified. Test v2.3 in Godot 4.7.2 on the developer's Linux machine after pulling.
