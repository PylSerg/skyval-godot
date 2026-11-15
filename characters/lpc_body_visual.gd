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
const EYE_COLORS := ["blue", "green", "brown", "gray", "purple", "yellow"]
const HAIR_STYLES := ["buzzcut", "bedhead", "curtains", "mop", "spiked"]
const SHIRT_COLORS := ["blue", "forest", "maroon", "white", "black", "leather"]
const PANTS_COLORS := ["charcoal", "brown", "navy", "black", "blue", "leather"]
const BOOTS_COLORS := ["brown", "black", "leather", "gray", "tan", "forest"]
# Verified against Universal LPC sprite directories. One variant per slot.
const SHIRT_STYLES := [
    "none",
    "shortsleeve/shortsleeve",
    "shortsleeve/tshirt",
    "longsleeve/longsleeve",
    "sleeveless/sleeveless",
    "shortsleeve/shortsleeve_polo",
]
const PANTS_STYLES := ["none", "pants", "pants2", "formal", "cuffed", "pantaloons"]
const FOOTWEAR_STYLES := [
    "none",
    "boots/basic", "boots/fold", "boots/rimmed",
    "shoes/basic", "shoes/revised",
]

@export var body_type: String = "male"
@export var skin_variant: String = "light"
@export var hair_variant: String = "black"
@export var hair_style: String = "buzzcut"
@export var eye_variant: String = "blue"
@export_group("LPC Apparel")
@export var shirt_variant: String = "blue"
@export var pants_variant: String = "charcoal"
@export var boots_variant: String = "brown"
@export_group("LPC Apparel Styles")
@export var shirt_style: String = "shortsleeve/shortsleeve"
@export var pants_style: String = "pants"
@export var footwear_style: String = "boots/basic"
# Armor is drawn exclusively using authentic Universal LPC sheets.
# Missing assets reject the equipment change instead of drawing fake armor.
@export var armor_style: String = "none"
@export var body_directory_override: String = ""

signal clothing_changed(state: Dictionary)

var available: bool = false
var _sprites: Array[AnimatedSprite2D] = []
var _saved_outfit: Dictionary = {}
var _last_clothing_state: Dictionary = {}
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
        var custom_dir: String = body_directory_override.strip_edges()
        # If an override points to .../male, allow a female switch too.
        if custom_dir.get_file() == "male" or custom_dir.get_file() == "female":
            custom_dir = custom_dir.get_base_dir().path_join(body_type)
        result.append(custom_dir)

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
    # LPC layers keep their official draw order. Empty slots are omitted.
    # Body and human head remain mandatory; clothing is optional.
    var clothing_shape: String = "thin" if body_type == "female" else "male"
    var shirt_shape: String = "female" if body_type == "female" else "male"
    var footwear_z: int = 15 if footwear_style.begins_with("shoes/") else 25
    var layers: Array[Dictionary] = [
        {"name": "Body", "path": body_path, "z": 10, "required": true},
        {"name": "Head", "path": root.path_join("head/heads/human/%s/%s.png" % [human_head, skin]), "z": 100, "required": true},
        {"name": "Face", "path": root.path_join("head/faces/%s/neutral/%s.png" % [human_head, skin]), "z": 101, "required": false},
        {"name": "Eyes", "path": root.path_join("eyes/human/adult/default/%s.png" % eye_variant), "z": 105, "required": false},
        {"name": "Hair", "path": root.path_join("hair/%s/adult/%s.png" % [hair_style, hair_variant]), "z": 120, "required": false},
    ]
    if pants_style != "none":
        layers.append({"name": "Pants", "path": root.path_join("legs/%s/%s/%s.png" % [pants_style, clothing_shape, pants_variant]), "z": 20, "required": true})
    if footwear_style != "none":
        layers.append({"name": "Footwear", "path": root.path_join("feet/%s/%s/%s.png" % [footwear_style, clothing_shape, boots_variant]), "z": footwear_z, "required": true})
    if shirt_style != "none":
        layers.append({"name": "Shirt", "path": root.path_join("torso/clothes/%s/%s/%s.png" % [shirt_style, shirt_shape, shirt_variant]), "z": 35, "required": true})
    if armor_style != "none":
        var armor_path: String = _find_armor_sheet(root, armor_style)
        if armor_path.is_empty():
            push_warning("Skyval LPC: no compatible Universal LPC armor sheet for %s (%s)" % [armor_style, body_type])
            return false

        if armor_style == "leather_vest":
            # Some original leather armor sheets contain a rear harness but
            # leave the chest almost bare. A second AUTHENTIC LPC sleeveless
            # torso layer gives the vest a proper front, not generated art.
            var vest_lining: String = _find_leather_vest_lining(root)
            if vest_lining.is_empty():
                push_warning("Skyval LPC: leather vest has no verified front layer; preserving worn outfit.")
                return false
            layers.append({"name": "ArmorVestFront", "path": vest_lining, "z": 40, "required": true})

        layers.append({"name": "Armor", "path": armor_path, "z": 45, "required": true})
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

    # Two mandatory layers: body and head. Undressed characters are valid.
    if replacements.size() < 2:
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
    var current_state: Dictionary = get_clothing_state()
    if current_state != _last_clothing_state:
        _last_clothing_state = current_state.duplicate()
        clothing_changed.emit(current_state)
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

# Read the actual armors in the user's Universal LPC library. The
# project sometimes loads its body from the small assets/lpc_sprites set,
# so armor discovery searches the full addon separately from body root.
# Only files that exist AND have the needed LPC animation atlas are used.
func _armor_roots(body_root: String) -> PackedStringArray:
    var roots := PackedStringArray()
    var home: String = OS.get_environment("HOME")
    if not home.is_empty():
        var local_res: String = home.path_join("Godot").path_join("res")
        roots.append(local_res.path_join("addons/Universal_LPC/resources/spritesheets"))
        roots.append(local_res.path_join("addons/universal_lpc/resources/spritesheets"))
        roots.append(local_res.path_join("assets/lpc_sprites"))
    roots.append("res://addons/Universal_LPC/resources/spritesheets")
    roots.append("res://addons/universal_lpc/resources/spritesheets")
    roots.append(body_root)
    roots.append("res://assets/characters/lpc")
    return roots


func _find_armor_sheet(body_root: String, style: String) -> String:
    var shape: String = "female" if body_type == "female" else "male"
    var types: Array[String] = []
    var preferences: Array[String] = []
    match style:
        "leather_vest":
            types = ["leather"]
            preferences = ["brown", "leather", "tan", "chestnut", "chocolate"]
        "reinforced_vest":
            types = ["legion", "leather"]
            preferences = ["iron", "steel", "gray", "black", "slate", "ceramic"]
        "plate_cuirass":
            types = ["plate", "legion"]
            preferences = ["iron", "steel", "silver", "brass", "ceramic"]
        _:
            return ""

    for sprite_root in _armor_roots(body_root):
        for armor_type in types:
            var directory: String = sprite_root.path_join("torso/armour").path_join(armor_type).path_join(shape)
            if not DirAccess.dir_exists_absolute(directory):
                continue
            var entries: PackedStringArray = DirAccess.get_files_at(directory)
            var filenames: Array[String] = []
            for filename in entries:
                if filename.ends_with(".png"):
                    filenames.append(filename)
            filenames.sort()
            # Preferred material/color before other existing choices.
            var ordered: Array[String] = []
            for color in preferences:
                var preferred: String = color + ".png"
                if filenames.has(preferred):
                    ordered.append(preferred)
            for filename in filenames:
                if not ordered.has(filename):
                    ordered.append(filename)

            for filename in ordered:
                var candidate: String = directory.path_join(filename)
                if not _texture_exists(candidate):
                    continue
                var atlas: Texture2D = _load_texture(candidate)
                if atlas != null and atlas.get_width() >= 9 * CELL and atlas.get_height() >= IDLE_Y + 4 * CELL:
                    return candidate
    return ""


# The original LPC leather harness may be largely transparent from
# the front (as seen in the captured gameplay video). A sleeveless vest
# from the SAME Universal LPC artwork set fills that gap while retaining
# the leather armor details above it. Never synthesize replacement pixels.
func _find_leather_vest_lining(body_root: String) -> String:
    var shape: String = "female" if body_type == "female" else "male"
    var preferred_colors: Array[String] = [
        "leather.png", "brown.png", "tan.png", "chestnut.png", "dark_brown.png"
    ]
    for sprite_root in _armor_roots(body_root):
        var folder: String = sprite_root.path_join(
            "torso/clothes/sleeveless/sleeveless"
        ).path_join(shape)
        if not DirAccess.dir_exists_absolute(folder):
            continue

        var filenames: PackedStringArray = DirAccess.get_files_at(folder)
        var choices: Array[String] = []
        for filename in preferred_colors:
            if filenames.has(filename):
                choices.append(filename)
        # If the preferred brown leather variant is missing, retain
        # an authentic LPC asset rather than a blank outfit.
        for filename in filenames:
            if filename.ends_with(".png") and not choices.has(filename):
                choices.append(filename)

        for filename in choices:
            var path: String = folder.path_join(filename)
            if not _texture_exists(path):
                continue
            var atlas: Texture2D = _load_texture(path)
            if atlas == null or atlas.get_width() < 9 * CELL or atlas.get_height() < IDLE_Y + 4 * CELL:
                continue
            if _has_visible_torso_in_all_directions(atlas):
                return path
    return ""


func _has_visible_torso_in_all_directions(atlas: Texture2D) -> bool:
    var image: Image = atlas.get_image()
    if image == null or image.is_empty():
        return false
    # Validate ALL four facings in both idle and walk, not just overall
    # atlas dimensions. A sheet with an empty south/west/east cell
    # must never pass as a usable vest.
    for row_index in ROW_INDEX:
        for action_y in [IDLE_Y, WALK_Y]:
            var region_y: int = int(action_y) + int(row_index) * CELL
            var x_offset: int = 0 if int(action_y) == IDLE_Y else CELL
            var pixels: int = 0
            for cy in range(23, 51, 2):
                for cx in range(20, 45, 2):
                    if image.get_pixel(x_offset + cx, region_y + cy).a > 0.20:
                        pixels += 1
            if pixels < 6:
                return false
    return true


func set_armor_style(new_style: String) -> bool:
    if not ["none", "leather_vest", "reinforced_vest", "plate_cuirass"].has(new_style):
        return false
    if armor_style == new_style:
        return true
    var previous: String = armor_style
    if not available:
        return false
    armor_style = new_style
    if _load_appearance(skin_variant):
        return true
    armor_style = previous
    _load_appearance(skin_variant)
    return false


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
    _cycle_option("shirt_variant", SHIRT_COLORS)

func cycle_pants() -> void:
    _cycle_option("pants_variant", PANTS_COLORS)

func cycle_boots() -> void:
    _cycle_option("boots_variant", BOOTS_COLORS)

func cycle_shirt_style() -> void:
    _cycle_option("shirt_style", SHIRT_STYLES)

func cycle_pants_style() -> void:
    _cycle_option("pants_style", PANTS_STYLES)

func cycle_footwear_style() -> void:
    _cycle_option("footwear_style", FOOTWEAR_STYLES)

func _cycle_option(property_name: String, options: Array) -> void:
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
            print("Skyval: %s = %s" % [property_name, choice])
            return
    set(property_name, previous)
    push_warning("Skyval LPC: no valid alternate garment for %s" % property_name)

# Character creator API: use property keys, not translated display strings.
# Changing the body type also switches head, face, shirt, trousers and shoes.
func change_body_type(direction: int = 1) -> bool:
    if not available:
        return false
    var genders: Array[String] = ["male", "female"]
    var next_index: int = genders.find(body_type) + (1 if direction >= 0 else -1)
    if next_index < 0 or next_index >= genders.size():
        return false
    var previous: String = body_type
    body_type = genders[next_index]
    if _load_appearance(skin_variant):
        return true
    body_type = previous
    return false

func change_option(option_key: String, direction: int) -> bool:
    if not available:
        return false
    match option_key:
        "body_type":
            return change_body_type(direction)
        "skin_variant":
            return _change_skin(direction)
        "hair_variant":
            return _change_variant("hair_variant", HAIR_COLORS, direction)
        "hair_style":
            return _change_variant("hair_style", HAIR_STYLES, direction)
        "eye_variant":
            return _change_variant("eye_variant", EYE_COLORS, direction)
        "shirt_variant":
            return _change_variant("shirt_variant", SHIRT_COLORS, direction)
        "pants_variant":
            return _change_variant("pants_variant", PANTS_COLORS, direction)
        "boots_variant":
            return _change_variant("boots_variant", BOOTS_COLORS, direction)
        "shirt_style":
            return _change_variant("shirt_style", SHIRT_STYLES, direction)
        "pants_style":
            return _change_variant("pants_style", PANTS_STYLES, direction)
        "footwear_style":
            return _change_variant("footwear_style", FOOTWEAR_STYLES, direction)
    return false

func _change_skin(direction: int) -> bool:
    var start: int = maxi(SKINS.find(skin_variant), 0)
    var step_direction: int = 1 if direction >= 0 else -1
    for step in range(1, SKINS.size()):
        var index: int = start + step * step_direction
        if index < 0 or index >= SKINS.size():
            break
        if _load_appearance(SKINS[index]):
            return true
    return false

func _change_variant(property_name: String, options: Array, direction: int) -> bool:
    var previous: String = str(get(property_name))
    var start: int = maxi(options.find(previous), 0)
    var step_direction: int = 1 if direction >= 0 else -1
    # Only actual gear choices are circular; appearance choices stop at ends.
    var wrap: bool = property_name in [
        "shirt_variant", "pants_variant", "boots_variant",
        "shirt_style", "pants_style", "footwear_style",
    ]
    for step in range(1, options.size()):
        var index: int = start + step * step_direction
        if wrap:
            index = posmod(index, options.size())
        elif index < 0 or index >= options.size():
            break
        set(property_name, str(options[index]))
        if _load_appearance(skin_variant):
            return true
    set(property_name, previous)
    return false

# Public ordered options for the creator's current/total counter.
# The counter follows the same order used by the character editor.
func get_option_choices(option_key: String) -> Array[String]:
    var source: Array = []
    match option_key:
        "body_type":
            source = ["male", "female"]
        "skin_variant":
            source = SKINS
        "hair_variant":
            source = HAIR_COLORS
        "hair_style":
            source = HAIR_STYLES
        "eye_variant":
            source = EYE_COLORS
        "shirt_variant":
            source = SHIRT_COLORS
        "pants_variant":
            source = PANTS_COLORS
        "boots_variant":
            source = BOOTS_COLORS
        "shirt_style":
            source = SHIRT_STYLES
        "pants_style":
            source = PANTS_STYLES
        "footwear_style":
            source = FOOTWEAR_STYLES
    var result: Array[String] = []
    for choice in source:
        result.append(str(choice))
    return result


# Keep save files independent of sprite paths and translated labels.
# Import is validated against supported variants before rebuilding layers.
func export_appearance_state() -> Dictionary:
    return {
        "body_type": body_type,
        "skin_variant": skin_variant,
        "hair_variant": hair_variant,
        "hair_style": hair_style,
        "eye_variant": eye_variant,
        "shirt_variant": shirt_variant,
        "pants_variant": pants_variant,
        "boots_variant": boots_variant,
        "shirt_style": shirt_style,
        "pants_style": pants_style,
        "footwear_style": footwear_style,
        "armor_style": armor_style,
    }


func apply_appearance_state(saved: Dictionary) -> bool:
    if not available:
        return false
    var previous: Dictionary = export_appearance_state()
    var supported: Dictionary = {
        "body_type": ["male", "female"],
        "skin_variant": SKINS,
        "hair_variant": HAIR_COLORS,
        "hair_style": HAIR_STYLES,
        "eye_variant": EYE_COLORS,
        "shirt_variant": SHIRT_COLORS,
        "pants_variant": PANTS_COLORS,
        "boots_variant": BOOTS_COLORS,
        "shirt_style": SHIRT_STYLES,
        "pants_style": PANTS_STYLES,
        "footwear_style": FOOTWEAR_STYLES,
        "armor_style": ["none", "leather_vest", "reinforced_vest", "plate_cuirass"],
    }
    for key in supported:
        if saved.has(key) and supported[key].has(saved[key]):
            set(key, str(saved[key]))
    if _load_appearance(skin_variant):
        return true
    # Missing/incompatible assets must never destroy the existing character.
    for key in previous:
        set(key, previous[key])
    _load_appearance(skin_variant)
    return false


func reset_appearance_state() -> void:
    apply_appearance_state({
        "body_type": "male",
        "skin_variant": "light",
        "hair_variant": "black",
        "hair_style": "buzzcut",
        "eye_variant": "blue",
        "shirt_variant": "blue",
        "pants_variant": "charcoal",
        "boots_variant": "brown",
        "shirt_style": "shortsleeve/shortsleeve",
        "pants_style": "pants",
        "footwear_style": "boots/basic",
        "armor_style": "none",
    })


# Stable wardrobe state for save files and future NPC dialogue conditions.
func get_clothing_state() -> Dictionary:
    return {
        "shirt": shirt_style != "none",
        "pants": pants_style != "none",
        "footwear": footwear_style != "none",
        "fully_undressed": is_fully_undressed(),
    }

func is_fully_undressed() -> bool:
    return shirt_style == "none" and pants_style == "none" and footwear_style == "none"

# Remove all layers; press again to restore the saved outfit styles.
# Cosmetic colors and physical appearance are preserved.
func toggle_all_clothes() -> bool:
    if not available:
        return false

    var previous: Dictionary = {
        "shirt_style": shirt_style,
        "pants_style": pants_style,
        "footwear_style": footwear_style,
    }

    if is_fully_undressed():
        var restore: Dictionary = _saved_outfit
        if restore.is_empty():
            restore = {
                "shirt_style": "shortsleeve/shortsleeve",
                "pants_style": "pants",
                "footwear_style": "boots/basic",
            }
        shirt_style = str(restore.get("shirt_style", "shortsleeve/shortsleeve"))
        pants_style = str(restore.get("pants_style", "pants"))
        footwear_style = str(restore.get("footwear_style", "boots/basic"))
    else:
        shirt_style = "none"
        pants_style = "none"
        footwear_style = "none"

    if _load_appearance(skin_variant):
        if is_fully_undressed():
            _saved_outfit = previous.duplicate()
        else:
            _saved_outfit.clear()
        return true

    shirt_style = str(previous["shirt_style"])
    pants_style = str(previous["pants_style"])
    footwear_style = str(previous["footwear_style"])
    return false
