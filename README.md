# Skyval

2D top-down RPG prototype for Godot 4.7 (Compatibility renderer), targeting a 320×240 logical viewport on R36H (640×480 display).

## Character System v1

Run the project with F5. The existing test terrain and smooth camera remain unchanged.

Controls:
- Arrow keys: move (four directions, with four-frame walk/idle preview).
- I/J/K/L: move the camera's look-ahead (right-stick emulator).
- Controller: left stick or D-pad for movement, right stick for camera look.
- 1: cycle tunic color; 2: cycle hair color; 3: equip/unequip sword.

The current avatar is deliberately drawn in GDScript so the smoke test works without artwork. It demonstrates appearance slots but does not claim to render LPC sprites yet.

### Optional Universal LPC renderer

The visual node at `Player/CharacterVisual` can use the Universal LPC addon at `res://addons/universal_lpc/` when its script, metadata and selected textures are installed **inside the Godot project**.

Enable `use_universal_lpc`, set a validated `lpc_configuration` dictionary containing `body_type` and `selections`, then adjust `lpc_origin_offset` for foot alignment. The renderer automatically selects `idle-s/w/e/n` and `walk-s/w/e/n`. Example **schema only**: `{"body_type":"...","selections":{"valid/definition/path":"valid_variant"}}`.

The LPC library at `/home/serhii/Godot/res` is currently outside the game project; a `res://` resource path cannot directly load that sibling folder. For R36H exports, copy or install a *small licensed selection* of assets into the game. Do not commit all 900 MB. Preserve the artwork's required credits.

The addon is optional and disabled by default. Without it, the demo runs on the procedural preview.

## Project files

- `prototype/camera_test.gd`: terrain and world bounds
- `prototype/smart_camera.gd`: smooth follow and look-around
- `prototype/player.gd`: movement and debug input
- `prototype/camera_test.tscn`: runnable test scene
- `characters/character_visual.gd`: avatar display and appearance API
