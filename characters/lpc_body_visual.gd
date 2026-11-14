extends Node2D
## Skyval LPC renderer: synchronized body, human head, face, eyes, and hair.
## All layers use the SAME 64x64 LPC cells and animation timeline.
## On desktop it discovers the user's local sprite library; for exports, pack
## only selected, license-compliant sprites into res://assets/characters/lpc/.

const CELL := 64
const IDLE_Y := 1408
const WALK_Y := 512
const DIRECTIONS := ["s", "w", "e", "n"]
const ROW_INDEX := [2, 1, 3, 0]
const IDLE_FRAMES := [0, 0, 1]
const WALK_FRAMES := [1, 2, 3, 4, 5, 6, 7, 8]
const SKINS := ["light", "amber", "olive", "brown", "bronze"]
const HAIR_COLORS := ["black", "dark_brown", "blonde", "redhead", "ash"]
const SHIRT_COLORS := ["blue", "forest", "maroon", "white", "black", "leather"]
const PANTS_COLORS := ["charcoal", "brown", "navy", "black", "blue", "leather"]
const BOOTS_COLORS := ["brown", "black", "leather", "gray", "tan", "forest"]

@export var body_type: String = "male"
@export var skin_variant: String = "light"
@export var hair_variant: String = "black"
@export var eye_variant: String = "blue"
@export_group("LPC Apparel")
@export var shirt_variant: String = "blue"
@export var pants_variant: String = "charcoal"
@export var boots_variant: String = "brown"
@export var body_directory_override: String = ""

var available: bool = false
var _sprites: Array[AnimatedSprite2D] = []
var _direction: int = 0
var _walking: bool = false

func _ready() -> void:
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    available = _load_appearance(skin_variant)
    if not available:
        push_warning("Skyval LPC: complete body + head not found. Using original prototype avatar.")

func _candidate_dirs() -> PackedStringArray:
    var result := PackedStringArray()
    if not body_directory_override.strip_edges().is_empty():
        result.append(body_directory_override.strip_edges())

    var home: String = OS.get_environment("HOME")
    if not home.is_empty():
        var base: String = home.path_join("Godot").path_join("res")
        var roots := [
            "assets/lpc_sprites",
            "assets/lpc_sprites/spritesheets",
            "assets/lpc_sprites/resources/spritesheets",
            "addons/Universal_LPC/resources/spritesheets",
            "addons/universal_lpc/resources/spritesheets",
            "addons/Godot_LPC_Spritesheet/resources/spritesheets",
        ]
        for root in roots:
            result.append(base.path_join(root).path_join("body/bodies").path_join(body_type))

    # Packaged sheets have the same relative layout as the source LPC library.
    result.append("res://assets/characters/lpc/body/bodies/%s" % body_type)
    # Legacy path accepted by the previous v2 loader.
    result.append("res://assets/characters/lpc/body/%s" % body_type)
    return result

func _texture_exists(path: String) -> bool:
    if path.begins_with("res://"):
        return ResourceLoader.exists(path)
    return FileAccess.file_exists(path)

func _find_body_path(variant: String) -> String:
    for directory in _candidate_dirs():
        var candidate: String = directory.path_join(variant + ".png")
        if _texture_exists(candidate):
            return candidate
    return ""

func _get_sheet_root(body_path: String) -> String:
    var body_dir: String = body_path.get_base_dir()
    var parent_dir: String = body_dir.get_base_dir()
    if parent_dir.get_file() == "bodies":
        return parent_dir.get_base_dir().get_base_dir()
    # Legacy packed res://assets/characters/lpc/body/male layout.
    if parent_dir.get_file() == "body":
        return parent_dir.get_base_dir()
    return ""

func _load_texture(path: String) -> Texture2D:
    if path.begins_with("res://"):
        return load(path) as Texture2D
    var image := Image.new()
    var status: Error = image.load(path)
    if status != OK:
        push_warning("Skyval LPC: couldn't decode %s (error %d)" % [path, status])
        return null
    return ImageTexture.create_from_image(image)

func _load_appearance(skin: String) -> bool:
    var body_path: String = _find_body_path(skin)
    if body_path.is_empty():
        return false
    var root: String = _get_sheet_root(body_path)
    if root.is_empty():
        return false

    var human_head: String = "female" if body_type == "female" else "male"
    # Explicit LPC layers and z positions from the metadata manifest:
    # body (10), pants (20), boots (25), shirt (35), head (100).
    # Required clothing makes a fully dressed avatar our all-or-nothing default.
    # Other facial details remain optional as before.
    var clothing_shape: String = "thin" if body_type == "female" else "male"
    var shirt_shape: String = "female" if body_type == "female" else "male"
    var layers: Array[Dictionary] = [
        {"name": "Body", "path": body_path, "z": 10, "required": true},
        {"name": "Pants", "path": root.path_join("legs/pants/%s/%s.png" % [clothing_shape, pants_variant]), "z": 20, "required": true},
        {"name": "Boots", "path": root.path_join("feet/boots/basic/%s/%s.png" % [clothing_shape, boots_variant]), "z": 25, "required": true},
        {"name": "Shirt", "path": root.path_join("torso/clothes/shortsleeve/shortsleeve/%s/%s.png" % [shirt_shape, shirt_variant]), "z": 35, "required": true},
        {"name": "Head", "path": root.path_join("head/heads/human/%s/%s.png" % [human_head, skin]), "z": 100, "required": true},
        {"name": "Face", "path": root.path_join("head/faces/%s/neutral/%s.png" % [human_head, skin]), "z": 101, "required": false},
        {"name": "Eyes", "path": root.path_join("eyes/human/adult/default/%s.png" % eye_variant), "z": 105, "required": false},
        {"name": "Hair", "path": root.path_join("hair/buzzcut/adult/%s.png" % hair_variant), "z": 120, "required": false},
    ]
    # First validate all required files before creating Node2D instances.
    # A failed outfit change must never remove the working character.
    var validated: Array[Dictionary] = []
    for layer in layers:
        var path: String = str(layer["path"])
        if not _texture_exists(path):
            if bool(layer["required"]):
                push_warning("Skyval LPC: required character layer missing: %s" % path)
                return false
            continue

        var atlas: Texture2D = _load_texture(path)
        if atlas == null or atlas.get_width() < 9 * CELL or atlas.get_height() < IDLE_Y + 4 * CELL:
            if bool(layer["required"]):
                push_warning("Skyval LPC: invalid character sheet: %s" % path)
                return false
            continue
        validated.append({"name": str(layer["name"]), "z": int(layer["z"]), "atlas": atlas})

    var replacements: Array[AnimatedSprite2D] = []
    for layer in validated:
        var atlas: Texture2D = layer["atlas"] as Texture2D
        replacements.append(_build_layer(str(layer["name"]), int(layer["z"]), atlas))

    # A complete stack contains the body, head, and all three garments.
    if replacements.size() < 5:
        for candidate in replacements:
            candidate.free()
        return false

    for old in _sprites:
        remove_child(old)
        old.queue_free()
    _sprites.clear()
    for sprite in replacements:
        add_child(sprite)
        _sprites.append(sprite)

    skin_variant = skin
    _apply_animation()
    available = true
    return true

func _build_layer(label: String, layer_z: int, atlas: Texture2D) -> AnimatedSprite2D:
    var sprite := AnimatedSprite2D.new()
    sprite.name = label
    sprite.centered = false
    sprite.offset = Vector2(-32, -54)
    sprite.z_index = layer_z
    sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    var frames := SpriteFrames.new()
    if frames.has_animation("default"):
        frames.remove_animation("default")
    _add_action(frames, atlas, "idle", IDLE_Y, IDLE_FRAMES, 3.0)
    _add_action(frames, atlas, "walk", WALK_Y, WALK_FRAMES, 9.0)
    sprite.sprite_frames = frames
    return sprite

func _add_action(frames: SpriteFrames, atlas: Texture2D, action: String, start_y: int, indices: Array, fps: float) -> void:
    for direction_index in range(4):
        var animation: String = "%s-%s" % [action, DIRECTIONS[direction_index]]
        frames.add_animation(animation)
        frames.set_animation_loop(animation, true)
        frames.set_animation_speed(animation, fps)
        var row_y: int = start_y + ROW_INDEX[direction_index] * CELL
        for frame_number in indices:
            var cell := AtlasTexture.new()
            cell.atlas = atlas
            cell.region = Rect2(int(frame_number) * CELL, row_y, CELL, CELL)
            frames.add_frame(animation, cell)

func set_motion(direction: Vector2) -> void:
    _walking = direction.length_squared() > 0.0001
    if _walking:
        if absf(direction.x) > absf(direction.y):
            _direction = 2 if direction.x > 0.0 else 1
        else:
            _direction = 0 if direction.y > 0.0 else 3
    _apply_animation()

func _apply_animation() -> void:
    if _sprites.is_empty():
        return
    var action: String = "walk" if _walking else "idle"
    var animation: String = "%s-%s" % [action, DIRECTIONS[_direction]]
    for sprite in _sprites:
        if sprite.animation != StringName(animation) or not sprite.is_playing():
            sprite.play(animation)

func cycle_skin() -> void:
    if not available:
        return
    var origin: int = maxi(SKINS.find(skin_variant), 0)
    for shift in range(1, SKINS.size() + 1):
        if _load_appearance(SKINS[(origin + shift) % SKINS.size()]):
            return
    push_warning("Skyval LPC: no other complete body + head variants found.")

func cycle_hair() -> void:
    if not available:
        return
    var previous: String = hair_variant
    hair_variant = HAIR_COLORS[(maxi(HAIR_COLORS.find(hair_variant), 0) + 1) % HAIR_COLORS.size()]
    if not _load_appearance(skin_variant):
        hair_variant = previous

func cycle_shirt() -> void:
    _cycle_color("shirt_variant", SHIRT_COLORS)

func cycle_pants() -> void:
    _cycle_color("pants_variant", PANTS_COLORS)

func cycle_boots() -> void:
    _cycle_color("boots_variant", BOOTS_COLORS)

func _cycle_color(property_name: String, options: Array) -> void:
    if not available:
        return
    var previous: String = str(get(property_name))
    var origin: int = maxi(options.find(previous), 0)
    for step in range(1, options.size() + 1):
        var choice: String = str(options[(origin + step) % options.size()])
        if choice == previous:
            continue
        set(property_name, choice)
        if _load_appearance(skin_variant):
            return
    set(property_name, previous)
    push_warning("Skyval LPC: no valid alternate garment for %s" % property_name)
