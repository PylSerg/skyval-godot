extends Node2D
## Skyval LPC renderer: synchronized body, human head, face, eyes, and hair.
## Standard layers use 64px LPC cells; arming sword slashes use native 128px overlays.
## On desktop it discovers the user's local sprite library; PortMaster can
## load the full LPC PNG tree from SKYVAL_LPC_ROOT beside skyval.pck.
## The previous small res://assets/characters/lpc/ fallback remains valid.

const CELL := 64
const IDLE_Y := 1408
const WALK_Y := 512
const SLASH_Y := 768  # Universal LPC classic slash, 6 frames
const ONEHAND_Y := 2944  # LPC Revised 1-Handed Slash uses backslash row 46
const ONEHAND_FRAMES := [0, 1, 2, 3, 4, 5, 6]
const OVERSIZE_CELL := 128
const SLASH_FPS := 24.0
const SLASH_FRAMES := [0, 1, 2, 3, 4, 5]
const DIRECTIONS := ["s", "w", "e", "n"]
const ROW_INDEX := [2, 1, 3, 0]
# Test SOUTH -> EAST -> SOUTH only. Keep the previous turning moments
# (one-third and two-thirds of the swing) even with seven 1H frames.
const SOUTH_TURN_START_PROGRESS := 1.0 / 3.0
const SOUTH_TURN_END_PROGRESS := 2.0 / 3.0
# East-facing right hand is on the near side of the body sprite. The
# generic iron sword atlas seats its grip too far forward in this pose.
# Move only the sword artwork toward the visible hand; never swap W/E rows.
const EAST_SWORD_GRIP_OFFSET := Vector2(-14.0, 0.0)
const IDLE_FRAMES := [0, 0, 1]
const WALK_FRAMES := [1, 2, 3, 4, 5, 6, 7, 8]
const MAX_CACHED_ATLASES := 10
# Keep a few decoded armor animation sets warm for repeated try-ons.
# The full library is NEVER preloaded; unchanged layers remain attached.
const MAX_CACHED_ARMOR_FRAMES := 6
const SLOW_REBUILD_WARNING_MS := 120
const SKINS := ["light", "amber", "olive", "brown", "bronze"]
const HAIR_COLORS := ["black", "dark_brown", "blonde", "redhead", "ash"]
const EYE_COLORS := ["blue", "green", "brown", "gray", "purple", "yellow"]
const HAIR_STYLES := ["none", "buzzcut", "bedhead", "curtains", "mop", "spiked"]
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
# Arming sword uses genuine two-sided Universal LPC sheets, aligned to
# the same 64px 4-direction walk/idle atlas as the body.
@export var weapon_style: String = "none"
@export var body_directory_override: String = ""

signal clothing_changed(state: Dictionary)

var available: bool = false
var _sprites: Array[AnimatedSprite2D] = []
# Sprite name -> source path, committed only after a fully valid swap.
var _layer_paths: Dictionary = {}
var _saved_outfit: Dictionary = {}
var _last_clothing_state: Dictionary = {}
# External PNGs are otherwise decoded on every menu selection. A small
# bounded cache keeps the active LPC atlases in memory for quick swaps.
var _atlas_cache: Dictionary = {}
var _atlas_cache_order: Array[String] = []
var _armor_frames_cache: Dictionary = {}
var _armor_frames_order: Array[String] = []
var _armor_path_cache: Dictionary = {}
var _lining_path_cache: Dictionary = {}
var _direction: int = 0
var _walking: bool = false
var _attacking: bool = false
var _sword_slash_available: bool = false
var _onehand_slash_available: bool = false
var _attack_progress: float = 0.0
var _attack_frame: int = -1  # Shared frame across body, armor and both sword layers.
var _reported_sword_fallback: bool = false

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

    # PortMaster installs the complete LPC PNG library outside the PCK.
    # This allows a one-time SD transfer; later updates replace only the PCK.
    # FileAccess/Image.load handle these absolute PNG paths at runtime.
    var external_root: String = OS.get_environment("SKYVAL_LPC_ROOT").strip_edges()
    if not external_root.is_empty():
        result.append(external_root.path_join("body/bodies").path_join(body_type))

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
    if _atlas_cache.has(path):
        _atlas_cache_order.erase(path)
        _atlas_cache_order.append(path)
        return _atlas_cache[path] as Texture2D

    var texture: Texture2D = null
    if path.begins_with("res://"):
        texture = load(path) as Texture2D
    else:
        var image := Image.new()
        var status: Error = image.load(path)
        if status != OK:
            push_warning("Skyval LPC: couldn't decode %s (error %d)" % [path, status])
            return null
        texture = ImageTexture.create_from_image(image)

    if texture != null:
        _atlas_cache[path] = texture
        _atlas_cache_order.append(path)
        while _atlas_cache_order.size() > MAX_CACHED_ATLASES:
            var oldest: String = _atlas_cache_order.pop_front()
            _atlas_cache.erase(oldest)
    return texture

# Armor variants are expensive to decode and repair on a handheld.
# Reuse the exact SpriteFrames resource for the last few pieces tried on.
# An active sprite retains its frames even after cache eviction.
func _cached_armor_frames(label: String, path: String) -> SpriteFrames:
    if label != "Armor" and label != "ArmorVestFront":
        return null
    var key: String = "%s|%s" % [label, path]
    if not _armor_frames_cache.has(key):
        return null
    _armor_frames_order.erase(key)
    _armor_frames_order.append(key)
    return _armor_frames_cache[key] as SpriteFrames


func _remember_armor_frames(label: String, path: String, frames: SpriteFrames) -> void:
    if label != "Armor" and label != "ArmorVestFront":
        return
    var key: String = "%s|%s" % [label, path]
    _armor_frames_cache[key] = frames
    _armor_frames_order.erase(key)
    _armor_frames_order.append(key)
    while _armor_frames_order.size() > MAX_CACHED_ARMOR_FRAMES:
        var oldest: String = _armor_frames_order.pop_front()
        _armor_frames_cache.erase(oldest)


func _load_appearance(skin: String) -> bool:
    var started_ms: int = Time.get_ticks_msec()
    var body_path: String = _find_body_path(skin)
    if body_path.is_empty():
        return false
    var root: String = _get_sheet_root(body_path)
    if root.is_empty():
        return false

    var human_head: String = "female" if body_type == "female" else "male"
    # Keep each layer independent. A helmet/weapon can be added later
    # without changing the body or another piece of equipment.
    var clothing_shape: String = "thin" if body_type == "female" else "male"
    var shirt_shape: String = "female" if body_type == "female" else "male"
    var footwear_z: int = 15 if footwear_style.begins_with("shoes/") else 25
    var layers: Array[Dictionary] = [
        {"name": "Body", "path": body_path, "z": 10, "required": true},
        {"name": "Head", "path": root.path_join("head/heads/human/%s/%s.png" % [human_head, skin]), "z": 100, "required": true},
        {"name": "Face", "path": root.path_join("head/faces/%s/neutral/%s.png" % [human_head, skin]), "z": 101, "required": false},
        {"name": "Eyes", "path": root.path_join("eyes/human/adult/default/%s.png" % eye_variant), "z": 105, "required": false},
    ]
    if hair_style != "none":
        layers.append({"name": "Hair", "path": root.path_join("hair/%s/adult/%s.png" % [hair_style, hair_variant]), "z": 120, "required": false})
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
            var vest_lining: String = _find_leather_vest_lining(root)
            if not vest_lining.is_empty():
                layers.append({"name": "ArmorVestFront", "path": vest_lining, "z": 40, "required": false})
        layers.append({"name": "Armor", "path": armor_path, "z": 45, "required": true})
    if weapon_style == "arming_iron":
        # Official LPC arming sword has BOTH a behind-body layer (z=9)
        # and a front-body layer (z=140). The variant is shared by both
        # body types. Reuse our existing walk/idle animation pipeline.
        var sword_root: String = root.path_join("weapon/sword/arming/universal")
        layers.append({"name": "WeaponBack", "path": sword_root.path_join("bg/iron.png"), "z": 9, "required": true})
        layers.append({"name": "WeaponFront", "path": sword_root.path_join("fg/iron.png"), "z": 140, "required": true})
        # The arming sword has a separate 128px slash, split front/back.
        var attack_root: String = root.path_join("weapon/sword/arming/attack_slash")
        layers.append({"name": "WeaponSlashBack", "path": attack_root.path_join("bg/iron.png"), "z": 8, "required": false})
        layers.append({"name": "WeaponSlashFront", "path": attack_root.path_join("fg/iron.png"), "z": 150, "required": false})
        # The classic slash pose moves the opposite hand. Universal LPC's
        # revised 1-Handed Slash uses the first seven backslash frames,
        # paired with the authentic 128px Arming Sword backslash layers.
        var onehand_root: String = root.path_join("weapon/sword/arming/attack_backslash")
        layers.append({"name": "WeaponOneHandBack", "path": onehand_root.path_join("bg/iron.png"), "z": 8, "required": false})
        layers.append({"name": "WeaponOneHandFront", "path": onehand_root.path_join("fg/iron.png"), "z": 150, "required": false})

    # Stage and validate only the changed layers. Existing sprites are
    # reused untouched, including their playing animation and atlas.
    # A failed change never removes or mutates the previous outfit.
    var previous_sprites: Dictionary = {}
    for old in _sprites:
        if is_instance_valid(old):
            previous_sprites[str(old.name)] = old

    var validated: Array[Dictionary] = []
    for layer in layers:
        var layer_name: String = str(layer["name"])
        var path: String = str(layer["path"])
        var z: int = int(layer["z"])
        var current: AnimatedSprite2D = previous_sprites.get(layer_name) as AnimatedSprite2D
        if current != null and str(_layer_paths.get(layer_name, "")) == path:
            validated.append({"name": layer_name, "path": path, "z": z, "sprite": current})
            continue

        var cached_frames: SpriteFrames = _cached_armor_frames(layer_name, path)
        if cached_frames != null:
            validated.append({"name": layer_name, "path": path, "z": z, "frames": cached_frames})
            continue

        if not _texture_exists(path):
            if bool(layer["required"]):
                push_warning("Skyval LPC: required character layer missing: %s" % path)
                return false
            continue

        var atlas: Texture2D = _load_texture(path)
        var oversized: bool = layer_name.begins_with("WeaponSlash") or layer_name.begins_with("WeaponOneHand")
        var oversized_frames: int = ONEHAND_FRAMES.size() if layer_name.begins_with("WeaponOneHand") else SLASH_FRAMES.size()
        var min_width: int = oversized_frames * OVERSIZE_CELL if oversized else 9 * CELL
        var min_height: int = 4 * OVERSIZE_CELL if oversized else IDLE_Y + 4 * CELL
        if atlas == null or atlas.get_width() < min_width or atlas.get_height() < min_height:
            if bool(layer["required"]):
                push_warning("Skyval LPC: invalid character sheet: %s" % path)
                return false
            continue
        validated.append({"name": layer_name, "path": path, "z": z, "atlas": atlas})

    if validated.size() < 2:
        return false

    # Create new nodes off-tree. Retire old nodes FIRST so Godot can keep
    # stable layer names ("Armor" is used by the 3x portrait renderer).
    var replacements: Array[AnimatedSprite2D] = []
    var new_nodes: Array[AnimatedSprite2D] = []
    var next_paths: Dictionary = {}
    for layer in validated:
        var layer_name: String = str(layer["name"])
        var path: String = str(layer["path"])
        var sprite: AnimatedSprite2D
        if layer.has("sprite"):
            sprite = layer["sprite"] as AnimatedSprite2D
        else:
            var atlas: Texture2D = layer.get("atlas") as Texture2D
            var frames: SpriteFrames = layer.get("frames") as SpriteFrames
            sprite = _build_layer(layer_name, int(layer["z"]), atlas, path, frames)
            new_nodes.append(sprite)
        sprite.z_index = int(layer["z"])
        replacements.append(sprite)
        next_paths[layer_name] = path

    for old in _sprites:
        if not replacements.has(old):
            remove_child(old)
            old.queue_free()
    for sprite in new_nodes:
        add_child(sprite)
    _sprites = replacements
    _layer_paths = next_paths
    # Never hide the existing sword unless BOTH oversize slash sprites
    # were really loaded from the user's LPC library.
    _sword_slash_available = next_paths.has("WeaponSlashBack") and next_paths.has("WeaponSlashFront")
    _onehand_slash_available = next_paths.has("WeaponOneHandBack") and next_paths.has("WeaponOneHandFront")
    # Do not select the revised attack unless the body actually contains its
    # source animation. Legacy/short LPC atlases retain the original slash.
    for body_layer in _sprites:
        if str(body_layer.name) == "Body" and (body_layer.sprite_frames == null or not body_layer.sprite_frames.has_animation("onehand-s")):
            _onehand_slash_available = false
    if weapon_style == "arming_iron" and not _sword_slash_available and not _reported_sword_fallback:
        push_warning("Skyval LPC: sword attack_slash/bg + fg missing or invalid; using animated equipped-sword fallback.")
        _reported_sword_fallback = true

    skin_variant = skin
    _apply_animation()
    available = true
    var current_state: Dictionary = get_clothing_state()
    if current_state != _last_clothing_state:
        _last_clothing_state = current_state.duplicate()
        clothing_changed.emit(current_state)

    var duration_ms: int = Time.get_ticks_msec() - started_ms
    if duration_ms >= SLOW_REBUILD_WARNING_MS:
        print("Skyval LPC: swapped %d/%d layers in %d ms (skin=%s, armor=%s)" % [
            new_nodes.size(), _sprites.size(), duration_ms, skin_variant, armor_style
        ])
    return true


func _build_layer(label: String, layer_z: int, atlas: Texture2D, path: String, cached_frames: SpriteFrames = null) -> AnimatedSprite2D:
    var sprite := AnimatedSprite2D.new()
    sprite.name = label
    sprite.centered = false
    var oversized: bool = label.begins_with("WeaponSlash") or label.begins_with("WeaponOneHand")
    # Align the larger attack sprites with the same character pivot.
    sprite.offset = Vector2(-64, -86) if oversized else Vector2(-32, -54)
    sprite.z_index = layer_z
    # Native LPC weapon sheets already share the body's facing/origin.
    sprite.flip_h = false
    sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

    var frames: SpriteFrames = cached_frames
    if frames == null:
        frames = SpriteFrames.new()
        if frames.has_animation("default"):
            frames.remove_animation("default")
        if oversized:
            if label.begins_with("WeaponOneHand"):
                _add_oversize_action(frames, atlas, "onehand", ONEHAND_FRAMES)
            else:
                _add_oversize_action(frames, atlas, "slash", SLASH_FRAMES)
        else:
            _add_action(frames, atlas, "idle", IDLE_Y, IDLE_FRAMES, 3.0)
            _add_action(frames, atlas, "walk", WALK_Y, WALK_FRAMES, 9.0)
            _add_action(frames, atlas, "slash", SLASH_Y, SLASH_FRAMES, SLASH_FPS)
            if atlas.get_width() >= 13 * CELL and atlas.get_height() >= ONEHAND_Y + 4 * CELL:
                _add_action(frames, atlas, "onehand", ONEHAND_Y, ONEHAND_FRAMES, float(ONEHAND_FRAMES.size()) / 0.25)
        if label == "Armor" or label == "ArmorVestFront":
            _repair_armor_idle_frames(frames, atlas)
            _remember_armor_frames(label, path, frames)
    sprite.sprite_frames = frames
    return sprite


func _add_action(frames: SpriteFrames, atlas: Texture2D, action: String, start_y: int, indices: Array, fps: float) -> void:
    for direction_index in range(4):
        var animation: String = "%s-%s" % [action, DIRECTIONS[direction_index]]
        frames.add_animation(animation)
        frames.set_animation_loop(animation, action != "slash" and action != "onehand")
        frames.set_animation_speed(animation, fps)
        var row_y: int = start_y + ROW_INDEX[direction_index] * CELL
        for frame_number in indices:
            var cell := AtlasTexture.new()
            cell.atlas = atlas
            cell.region = Rect2(int(frame_number) * CELL, row_y, CELL, CELL)
            frames.add_frame(animation, cell)

func _add_oversize_action(frames: SpriteFrames, atlas: Texture2D, action: String, indices: Array) -> void:
    for direction_index in range(4):
        var animation: String = "%s-%s" % [action, DIRECTIONS[direction_index]]
        frames.add_animation(animation)
        frames.set_animation_loop(animation, false)
        var fps: float = float(ONEHAND_FRAMES.size()) / 0.25 if action == "onehand" else SLASH_FPS
        frames.set_animation_speed(animation, fps)
        var row_y: int = ROW_INDEX[direction_index] * OVERSIZE_CELL
        for frame_number in indices:
            var cell := AtlasTexture.new()
            cell.atlas = atlas
            cell.region = Rect2(int(frame_number) * OVERSIZE_CELL, row_y, OVERSIZE_CELL, OVERSIZE_CELL)
            frames.add_frame(animation, cell)

# Some Universal LPC armor atlases have complete walk frames but
# incomplete idle poses. Apply the same torso-coverage comparison used
# by ui/character_preview.gd to the IN-WORLD idle animations, once when
# equipping the armor. Walking frames themselves remain untouched.
func _repair_armor_idle_frames(frames: SpriteFrames, atlas: Texture2D) -> void:
    var pixels: Image = atlas.get_image()
    if pixels == null or pixels.is_empty():
        return

    for direction in DIRECTIONS:
        var idle_name: StringName = StringName("idle-" + str(direction))
        var walk_name: StringName = StringName("walk-" + str(direction))
        if not frames.has_animation(idle_name) or not frames.has_animation(walk_name):
            continue

        var idle_count: int = frames.get_frame_count(idle_name)
        if idle_count == 0:
            continue

        # Assess all idle poses: a blank alternate idle frame would
        # otherwise flicker even if the first standing frame looks fine.
        var weakest_idle_score: int = 999999
        for idle_index in range(idle_count):
            var idle_frame: AtlasTexture = frames.get_frame_texture(idle_name, idle_index) as AtlasTexture
            if idle_frame == null:
                weakest_idle_score = 0
                continue
            weakest_idle_score = mini(
                weakest_idle_score, _armor_idle_torso_coverage(pixels, idle_frame.region)
            )

        var best_walk_score: int = 0
        var best_walk_frame: Texture2D = null
        # Same order as the confirmed working 3x preview fallback.
        for walk_index in [0, 4, 2, 6, 1, 5, 3, 7]:
            if walk_index >= frames.get_frame_count(walk_name):
                continue
            var candidate: AtlasTexture = frames.get_frame_texture(walk_name, walk_index) as AtlasTexture
            if candidate == null:
                continue
            var coverage: int = _armor_idle_torso_coverage(pixels, candidate.region)
            if coverage > best_walk_score:
                best_walk_score = coverage
                best_walk_frame = candidate

        if best_walk_frame == null or best_walk_score < 5:
            continue
        if best_walk_score <= weakest_idle_score + maxi(4, int(weakest_idle_score * 0.20)):
            continue

        # Reuse ONE genuine walk texture for every idle frame of that
        # facing. The armor remains still when the player stands, instead
        # of flashing between intact and incomplete idle frames.
        for idle_index in range(idle_count):
            frames.set_frame(
                idle_name, idle_index, best_walk_frame,
                frames.get_frame_duration(idle_name, idle_index)
            )


func _armor_idle_torso_coverage(pixels: Image, region: Rect2) -> int:
    var x0: int = int(region.position.x)
    var y0: int = int(region.position.y)
    if x0 < 0 or y0 < 0 or x0 + CELL > pixels.get_width() or y0 + CELL > pixels.get_height():
        return 0

    var visible: int = 0
    var almost_white: int = 0
    for y in range(25, 49, 2):
        for x in range(19, 46, 2):
            var color: Color = pixels.get_pixel(x0 + x, y0 + y)
            if color.a < 0.25:
                continue
            visible += 1
            if color.r > 0.97 and color.g > 0.97 and color.b > 0.97:
                almost_white += 1
    if visible >= 40 and almost_white * 5 >= visible * 4:
        return 0
    return visible


# Read the actual armors in the user's Universal LPC library. The
# project sometimes loads its body from the small assets/lpc_sprites set,
# so armor discovery searches the full addon separately from body root.
# Only files that exist AND have the needed LPC animation atlas are used.
func _armor_roots(body_root: String) -> PackedStringArray:
    var roots := PackedStringArray()
    # Use the same full external LPC tree for plate, legion, leather and
    # optional sleeveless lining. Do not require armor in the PCK.
    var external_root: String = OS.get_environment("SKYVAL_LPC_ROOT").strip_edges()
    if not external_root.is_empty():
        roots.append(external_root)
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
    var cache_key: String = "%s|%s|%s" % [body_root, body_type, style]
    if _armor_path_cache.has(cache_key):
        return str(_armor_path_cache[cache_key])
    var shape: String = "female" if body_type == "female" else "male"
    var types: Array[String] = []
    var preferences: Array[String] = []
    match style:
        "leather_vest":
            types = ["leather"]
            preferences = ["brown", "leather", "tan", "chestnut", "chocolate"]
        "reinforced_vest":
            # Never replace legion armor with a leather vest merely
            # because it shares the same atlas size.
            types = ["legion"]
            preferences = ["iron", "steel", "gray", "black", "slate", "ceramic"]
        "plate_cuirass":
            # A plate cuirass must actually look like plate; accepting
            # legion sprites here made the heavy and reinforced armor identical.
            types = ["plate"]
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
                if atlas == null or atlas.get_width() < 9 * CELL or atlas.get_height() < IDLE_Y + 4 * CELL:
                    continue
                # Size alone is not enough: some original LPC sheets have
                # transparent facing frames despite having a full atlas.
                # Leather gets an independent sleeveless front layer, but
                # legion/plate must cover the chest in all walk/idle facings.
                if style != "leather_vest" and not _has_visible_torso_in_all_directions(atlas):
                    continue
                _armor_path_cache[cache_key] = candidate
                return candidate
    _armor_path_cache[cache_key] = ""
    return ""


# The original LPC leather harness may be largely transparent from
# the front (as seen in the captured gameplay video). A sleeveless vest
# from the SAME Universal LPC artwork set fills that gap while retaining
# the leather armor details above it. Never synthesize replacement pixels.
func _find_leather_vest_lining(body_root: String) -> String:
    var cache_key: String = "%s|%s" % [body_root, body_type]
    if _lining_path_cache.has(cache_key):
        return str(_lining_path_cache[cache_key])
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
            # The vest lining is optional. A correctly sized real LPC
            # sleeveless sprite is preferable to failing a valid armor swap;
            # these sheets can intentionally have narrow side/back coverage.
            _lining_path_cache[cache_key] = path
            return path
    _lining_path_cache[cache_key] = ""
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
    # _load_appearance() validates all layers before replacing _sprites,
    # so a failed change leaves the old render intact. Reloading it here
    # doubles costly PNG decodes and can stall the handheld.
    armor_style = previous
    return false


# This changes the drawn pose only. The combat facing (_direction) stays
# fixed, so hit detection and the resting direction are unaffected.
func _attack_visual_direction() -> int:
    if _attacking and _direction == 0 and _attack_progress >= SOUTH_TURN_START_PROGRESS and _attack_progress < SOUTH_TURN_END_PROGRESS:
        # Use the actual east-facing LPC row. Slash begins at Y=768,
        # not Y=704; the old offset made east/west appear swapped.
        # Keep this turn exclusive to the south-facing test.
        return 2
    return _direction

func _use_onehand_slash() -> bool:
    return _attacking and _direction == 0 and _onehand_slash_available

func start_attack(facing_direction: int) -> void:
    if not available:
        return
    _direction = clampi(facing_direction, 0, 3)
    _attacking = true
    _attack_progress = 0.0
    _attack_frame = -1
    _apply_animation(true)
    set_attack_progress(0.0)  # Lock every attack layer to the same first frame.

func end_attack() -> void:
    if not _attacking:
        return
    _attacking = false
    _attack_progress = 0.0
    _attack_frame = -1
    _reset_sword_pose()
    # The sword returns to its right-hand resting grip after the swing.
    # A hidden normal sword layer must not resume at a random idle frame.
    for sprite in _sprites:
        if str(sprite.name) == "WeaponBack" or str(sprite.name) == "WeaponFront":
            if sprite.sprite_frames != null:
                sprite.set_frame_and_progress(0, 0.0)
    _apply_animation()

# A geometry-only fallback for LPC installations without 128px slash assets.
# Reuse the already loaded weapon sprites, so an attack never looks unarmed.
func set_attack_progress(progress: float) -> void:
    if not _attacking:
        return
    var old_visual_direction: int = _attack_visual_direction()
    _attack_progress = clampf(progress, 0.0, 1.0)
    var new_visual_direction: int = _attack_visual_direction()
    var action: String = "onehand" if _use_onehand_slash() else "slash"
    var frame_count: int = ONEHAND_FRAMES.size() if _use_onehand_slash() else SLASH_FRAMES.size()
    var frame_index: int = mini(int(_attack_progress * frame_count), frame_count - 1)
    # Turning SOUTH -> EAST -> SOUTH is independent of sprite frame count.
    # Preserve the previously confirmed turn timing and synchronize all layers.
    if old_visual_direction != new_visual_direction:
        _apply_animation(true)
    if frame_index != _attack_frame or old_visual_direction != new_visual_direction:
        _attack_frame = frame_index
        var attack_name: StringName = StringName("%s-%s" % [action, DIRECTIONS[new_visual_direction]])
        for sprite in _sprites:
            if not sprite.visible or sprite.sprite_frames == null:
                continue
            if sprite.animation != attack_name:
                continue
            if sprite.sprite_frames.get_frame_count(attack_name) > frame_index:
                sprite.pause()
                sprite.set_frame_and_progress(frame_index, 0.0)

    if _sword_slash_available or _use_onehand_slash():
        return

    # Missing oversize sword art: preserve the existing right-hand grip.
    var lift: float = sin(_attack_progress * PI) * 2.0
    for sprite in _sprites:
        if str(sprite.name) == "WeaponBack" or str(sprite.name) == "WeaponFront":
            sprite.rotation = 0.0
            sprite.position = Vector2.UP * lift

func _reset_sword_pose() -> void:
    for sprite in _sprites:
        if str(sprite.name) == "WeaponBack" or str(sprite.name) == "WeaponFront":
            sprite.rotation = 0.0
            sprite.position = Vector2.ZERO

func has_sword_slash_assets() -> bool:
    return weapon_style == "arming_iron" and (_sword_slash_available or _use_onehand_slash())

func set_motion(direction: Vector2) -> void:
    if _attacking:
        return  # Hold the attack facing until the swing finishes.
    _walking = direction.length_squared() > 0.0001
    if _walking:
        if absf(direction.x) > absf(direction.y):
            _direction = 2 if direction.x > 0.0 else 1
        else:
            _direction = 0 if direction.y > 0.0 else 3
    _apply_animation()

func _apply_animation(restart_attack: bool = false) -> void:
    if _sprites.is_empty():
        return
    var onehand_attack: bool = _use_onehand_slash()
    var action: String = "walk" if _walking else "idle"
    if _attacking:
        action = "onehand" if onehand_attack else "slash"
    var visual_direction: int = _attack_visual_direction()
    var animation: String = "%s-%s" % [action, DIRECTIONS[visual_direction]]
    for sprite in _sprites:
        var is_weapon: bool = str(sprite.name).begins_with("Weapon")
        var slash_weapon: bool = str(sprite.name).begins_with("WeaponSlash")
        var onehand_weapon: bool = str(sprite.name).begins_with("WeaponOneHand")
        var regular_weapon: bool = is_weapon and not slash_weapon and not onehand_weapon
        # Keep LPC's native frame direction for every character layer.
        # Only the south-facing iron sword is mirrored: when the avatar
        # faces the camera, its right hand is on screen-left. Mirroring both
        # fg/bg weapon layers together preserves the grip and the depth split.
        # W/E and north sword sprites must remain unflipped.
        sprite.flip_h = is_weapon and visual_direction == 0 and not onehand_weapon
        var sword_base_offset: Vector2 = Vector2(-64, -86) if (slash_weapon or onehand_weapon) else Vector2(-32, -54)
        if is_weapon:
            sprite.offset = sword_base_offset + (EAST_SWORD_GRIP_OFFSET if visual_direction == 2 else Vector2.ZERO)
        var use_oversize: bool = _attacking and _sword_slash_available and not onehand_attack
        if onehand_weapon:
            sprite.visible = onehand_attack
        elif slash_weapon:
            sprite.visible = use_oversize
        elif regular_weapon:
            sprite.visible = not (use_oversize or onehand_attack)
        if not sprite.visible:
            sprite.pause()  # Invisible sword frames must not drift out of sync.
            continue
        var chosen_animation: String = animation
        # Older accessories may lack the revised backslash row. Use the
        # classical pose as a visual fallback instead of blanking the layer.
        if not is_weapon and onehand_attack and not sprite.sprite_frames.has_animation(chosen_animation):
            chosen_animation = "slash-%s" % DIRECTIONS[visual_direction]
        # Standard arming sword atlas has idle/walk; the 128px overlays
        # provide slash frames when available.
        if regular_weapon and _attacking:
            chosen_animation = "idle-%s" % DIRECTIONS[visual_direction]
        # Don't restart the six-frame slash every physics frame.
        if restart_attack or sprite.animation != StringName(chosen_animation):
            sprite.play(chosen_animation)
            if _attacking and not regular_weapon:
                sprite.set_frame_and_progress(0, 0.0)
        elif not _attacking and not sprite.is_playing():
            sprite.play(chosen_animation)
        if _attacking:
            # Do not let any layer tick independently while the global
            # combat controller is supplying its synchronized slash frame.
            sprite.pause()
    if not _attacking:
        _reset_sword_pose()


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
    var current_index: int = genders.find(body_type)
    if current_index < 0:
        return false
    var next_index: int = posmod(
        current_index + (1 if direction >= 0 else -1), genders.size()
    )
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
        var index: int = posmod(start + step * step_direction, SKINS.size())
        if _load_appearance(SKINS[index]):
            return true
    return false

func _change_variant(property_name: String, options: Array, direction: int) -> bool:
    var previous: String = str(get(property_name))
    var start: int = maxi(options.find(previous), 0)
    var step_direction: int = 1 if direction >= 0 else -1
    # Body appearance and item variants are both cyclic. Invalid LPC
    # files are skipped without changing the currently visible character.
    for step in range(1, options.size()):
        var index: int = posmod(start + step * step_direction, options.size())
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
        "weapon_style": weapon_style,
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
        "weapon_style": ["none", "arming_iron"],
    }
    for key in supported:
        if saved.has(key) and supported[key].has(saved[key]):
            set(key, str(saved[key]))
    if _load_appearance(skin_variant):
        return true
    # Validation happens before old layers are replaced. Restore only
    # properties; leave the existing sprite nodes and textures untouched.
    for key in previous:
        set(key, previous[key])
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
        "weapon_style": "none",
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
