extends Node2D
class_name SkyvalCharacterVisual
## Character System v1: four-way, pixel-snapped animated avatar.
## The procedural preview needs no artwork. Universal LPC is an optional renderer.

enum Facing { SOUTH, WEST, EAST, NORTH }

const ExternalBodyScript = preload("res://characters/lpc_body_visual.gd")

const LPC_SCRIPT := "res://addons/universal_lpc/universal_lpc_sprite_2d.gd"
const LPC_METADATA := "res://addons/universal_lpc/universal_lpc_metadata.json"
const OUTFIT_COLORS := ["#4368a8", "#417b56", "#a05e45", "#825a99"]
const HAIR_COLORS := ["#5a3527", "#d5ad61", "#303142", "#bd7550"]

@export_range(1.0, 16.0, 0.5) var walk_fps: float = 8.0
@export var skin_color: Color = Color("#f2c59d")
@export_group("Optional Universal LPC")
@export var use_universal_lpc: bool = false
@export var lpc_configuration: Dictionary = {}
@export var lpc_origin_offset: Vector2 = Vector2(-32, -56)
@export_group("External LPC body (desktop)")
@export var use_external_lpc_body: bool = true
@export var external_body_directory: String = ""

var facing: Facing = Facing.SOUTH
var is_walking: bool = false
var outfit_index: int = 0
var hair_index: int = 0
var weapon_equipped: bool = false

var _walk_clock: float = 0.0
var _walk_frame: int = 0
var _lpc_renderer: Node2D = null
var _external_body: Node2D = null

func _ready() -> void:
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    _try_enable_lpc()
    if _lpc_renderer == null and use_external_lpc_body:
        _try_enable_external_body()
    queue_redraw()

func _process(delta: float) -> void:
    if _lpc_renderer != null or (_external_body != null and _external_body.visible) or not is_walking:
        return
    _walk_clock += delta
    var next_frame: int = int(floor(_walk_clock * walk_fps)) % 4
    if next_frame != _walk_frame:
        _walk_frame = next_frame
        queue_redraw()

func set_motion(direction: Vector2) -> void:
    var next_walking: bool = direction.length_squared() > 0.0001
    var next_facing: Facing = facing
    if next_walking:
        if absf(direction.x) > absf(direction.y):
            next_facing = Facing.EAST if direction.x > 0.0 else Facing.WEST
        else:
            next_facing = Facing.SOUTH if direction.y > 0.0 else Facing.NORTH

    var changed: bool = next_walking != is_walking or next_facing != facing
    is_walking = next_walking
    facing = next_facing
    if not is_walking:
        _walk_clock = 0.0
        _walk_frame = 0
    if _external_body != null:
        _external_body.call("set_motion", direction)
    if changed:
        if _lpc_renderer != null:
            _apply_lpc_animation()
        else:
            queue_redraw()

func cycle_outfit() -> void:
    if _external_body != null and _external_body.visible:
        _external_body.call("cycle_shirt")
    else:
        outfit_index = (outfit_index + 1) % OUTFIT_COLORS.size()
        queue_redraw()

func cycle_hair() -> void:
    hair_index = (hair_index + 1) % HAIR_COLORS.size()
    if _external_body != null and _external_body.visible:
        _external_body.call("cycle_hair")
    queue_redraw()

func toggle_weapon() -> void:
    # Retains the old sword test in prototype mode.
    # LPC mode uses this key to test the new independent pants slot.
    if _external_body != null and _external_body.visible:
        _external_body.call("cycle_pants")
    else:
        weapon_equipped = not weapon_equipped
        queue_redraw()

func cycle_footwear() -> void:
    if _external_body != null and _external_body.visible:
        _external_body.call("cycle_boots")

func toggle_lpc_preview() -> void:
    if _external_body == null:
        push_warning("Skyval: external LPC body not found; showing prototype.")
        return
    _external_body.visible = not _external_body.visible
    queue_redraw()

func cycle_lpc_skin() -> void:
    if _external_body != null:
        _external_body.call("cycle_skin")

func _try_enable_external_body() -> void:
    var body: Node2D = ExternalBodyScript.new() as Node2D
    body.name = "LpcBody"
    body.set("body_directory_override", external_body_directory)
    add_child(body)
    if not bool(body.get("available")):
        body.queue_free()
        return
    _external_body = body
    _external_body.call("set_motion", Vector2.ZERO)

func _try_enable_lpc() -> void:
    if not use_universal_lpc:
        return
    if lpc_configuration.is_empty():
        push_warning("Skyval LPC: configuration is empty; showing the prototype avatar.")
        return
    if not ResourceLoader.exists(LPC_SCRIPT) or not FileAccess.file_exists(LPC_METADATA):
        push_warning("Skyval LPC: addon/metadata not installed in this Godot project; using prototype avatar.")
        return

    var renderer_script: Script = load(LPC_SCRIPT) as Script
    if renderer_script == null:
        push_warning("Skyval LPC: could not load renderer script; using prototype avatar.")
        return
    var instance: Object = renderer_script.new()
    if not instance is Node2D:
        push_warning("Skyval LPC: renderer is not a Node2D; using prototype avatar.")
        return

    _lpc_renderer = instance as Node2D
    _lpc_renderer.name = "UniversalLpcRenderer"
    _lpc_renderer.position = lpc_origin_offset
    add_child(_lpc_renderer)
    _lpc_renderer.set("configuration", lpc_configuration)
    # The plugin rebuilds its sprites with call_deferred(); apply animation afterward.
    call_deferred("_apply_lpc_animation")

func _apply_lpc_animation() -> void:
    if _lpc_renderer == null:
        return
    var direction_name: String = ["s", "w", "e", "n"][int(facing)]
    var base_name: String = "walk" if is_walking else "idle"
    _lpc_renderer.set("animation_name", "%s-%s" % [base_name, direction_name])
    _lpc_renderer.set("is_playing", is_walking)

func _draw() -> void:
    if _lpc_renderer != null or (_external_body != null and _external_body.visible):
        return
    _draw_preview_avatar()

func _draw_preview_avatar() -> void:
    # Feet roughly coincide with the existing collision box at y=10.
    var dark: Color = Color("#283246")
    var shoe: Color = Color("#393944")
    var cloth: Color = Color(OUTFIT_COLORS[outfit_index])
    var hair: Color = Color(HAIR_COLORS[hair_index])
    var swing: int = [0, 2, 0, -2][_walk_frame] if is_walking else 0
    var bob: int = 1 if is_walking and _walk_frame == 2 else 0

    # A small fixed ground shadow, distinct from the animated body.
    draw_rect(Rect2(-8, 12, 16, 2), Color(0.14, 0.20, 0.23, 0.33))

    # The sword is drawn behind a north-facing character.
    if weapon_equipped and facing == Facing.NORTH:
        _draw_sword(-10, -6)

    # Shoes and legs alternate in a four-frame walking loop.
    draw_rect(Rect2(-5, 3 + swing, 4, 8), dark)
    draw_rect(Rect2(1, 3 - swing, 4, 8), dark)
    draw_rect(Rect2(-5, 9 + swing, 4, 3), shoe)
    draw_rect(Rect2(1, 9 - swing, 4, 3), shoe)

    # Shirt, sleeves and tiny cuffs form independent appearance layers.
    draw_rect(Rect2(-7, -10 - bob, 14, 15), dark)
    draw_rect(Rect2(-6, -9 - bob, 12, 13), cloth)
    draw_rect(Rect2(-9, -7 - bob - swing / 2.0, 3, 9), skin_color)
    draw_rect(Rect2(6, -7 - bob + swing / 2.0, 3, 9), skin_color)
    draw_rect(Rect2(-5, 2 - bob, 10, 2), cloth.darkened(0.22))

    # Head and hairstyle rotate to four cardinal directions.
    draw_rect(Rect2(-5, -22 - bob, 10, 13), dark)
    draw_rect(Rect2(-4, -21 - bob, 8, 11), skin_color)
    draw_rect(Rect2(-5, -23 - bob, 10, 4), hair)
    if facing == Facing.NORTH:
        draw_rect(Rect2(-5, -20 - bob, 10, 9), hair)
        draw_rect(Rect2(-4, -13 - bob, 8, 2), hair.darkened(0.15))
    elif facing == Facing.SOUTH:
        draw_rect(Rect2(-5, -19 - bob, 2, 6), hair)
        draw_rect(Rect2(3, -19 - bob, 2, 6), hair)
        draw_rect(Rect2(-3, -16 - bob, 2, 2), dark)
        draw_rect(Rect2(1, -16 - bob, 2, 2), dark)
    elif facing == Facing.WEST:
        draw_rect(Rect2(-5, -19 - bob, 2, 8), hair)
        draw_rect(Rect2(-4, -16 - bob, 2, 2), dark)
    else:
        draw_rect(Rect2(3, -19 - bob, 2, 8), hair)
        draw_rect(Rect2(2, -16 - bob, 2, 2), dark)

    if weapon_equipped and facing != Facing.NORTH:
        _draw_sword(9 if facing != Facing.WEST else -12, -7)

func _draw_sword(x: float, y: float) -> void:
    draw_rect(Rect2(x + 1, y - 12, 2, 13), Color("#dce7e9"))
    draw_rect(Rect2(x, y, 4, 2), Color("#d6a44c"))
    draw_rect(Rect2(x + 1, y + 2, 2, 5), Color("#654a39"))
