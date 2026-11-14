extends Node2D
## Skyval Character System v2: load one real Universal LPC body sheet.
## External assets are for desktop testing. R36H exports need packed assets.

const CELL := 64
const IDLE_Y := 1408
const WALK_Y := 512
const DIRECTIONS := ["s", "w", "e", "n"]
const ROW_INDEX := [2, 1, 3, 0]
const IDLE_FRAMES := [0, 0, 1]
const WALK_FRAMES := [1, 2, 3, 4, 5, 6, 7, 8]
const SKINS := ["light", "amber", "olive", "brown", "bronze"]

@export var body_type: String = "male"
@export var skin_variant: String = "light"
@export var body_directory_override: String = ""

var available: bool = false
var _sprite: AnimatedSprite2D
var _direction: int = 0
var _walking: bool = false

func _ready() -> void:
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    _sprite = AnimatedSprite2D.new()
    _sprite.name = "BodyFrames"
    _sprite.centered = false
    _sprite.offset = Vector2(-32, -54)
    _sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    add_child(_sprite)
    available = _load_skin(skin_variant)
    if not available:
        push_warning("Skyval: LPC base body not found. Set CharacterVisual/External Body Directory to the directory containing light.png.")
    else:
        set_motion(Vector2.ZERO)

func _candidate_dirs() -> PackedStringArray:
    var result := PackedStringArray()
    if not body_directory_override.strip_edges().is_empty():
        result.append(body_directory_override.strip_edges())
    var home: String = OS.get_environment("HOME")
    if home.is_empty():
        return result
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
    return result

func _locate_skin(variant: String) -> String:
    for dir in _candidate_dirs():
        var filename: String = dir.path_join(variant + ".png")
        if FileAccess.file_exists(filename):
            return filename
    var packaged: String = "res://assets/characters/lpc/body/%s/%s.png" % [body_type, variant]
    if ResourceLoader.exists(packaged):
        return packaged
    return ""

func _load_skin(variant: String) -> bool:
    var path: String = _locate_skin(variant)
    if path.is_empty():
        return false
    var atlas: Texture2D = null
    if path.begins_with("res://"):
        # ResourceLoader also works with textures imported into an exported PCK.
        atlas = load(path) as Texture2D
    else:
        # External absolute paths are only available during local development.
        var image := Image.new()
        var error: Error = image.load(path)
        if error != OK:
            push_warning("Skyval: failed to read %s (%d)" % [path, error])
            return false
        atlas = ImageTexture.create_from_image(image)

    if atlas == null or atlas.get_width() < 9 * CELL or atlas.get_height() < IDLE_Y + 4 * CELL:
        push_warning("Skyval: missing or invalid 64px LPC sheet: %s" % path)
        return false
    var frames := SpriteFrames.new()
    if frames.has_animation("default"):
        frames.remove_animation("default")
    _add_action(frames, atlas, "idle", IDLE_Y, IDLE_FRAMES, 3.0)
    _add_action(frames, atlas, "walk", WALK_Y, WALK_FRAMES, 9.0)
    _sprite.sprite_frames = frames
    skin_variant = variant
    _apply_animation()
    return true

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
    if _sprite == null or _sprite.sprite_frames == null:
        return
    var action: String = "walk" if _walking else "idle"
    var animation: String = "%s-%s" % [action, DIRECTIONS[_direction]]
    if _sprite.animation != StringName(animation) or not _sprite.is_playing():
        _sprite.play(animation)

func cycle_skin() -> void:
    if not available:
        return
    var origin: int = maxi(SKINS.find(skin_variant), 0)
    for shift in range(1, SKINS.size() + 1):
        if _load_skin(SKINS[(origin + shift) % SKINS.size()]):
            return
    push_warning("Skyval: alternate LPC skin textures are missing.")
