extends Control
## Large, pixel-crisp LPC portrait. Turn independently from the paused
## in-world avatar. Horizontal stick flicks rotate cyclically by 90 degrees.

# Clockwise as seen from above: front -> facing right -> back -> left.
const DIRECTIONS := ["s", "e", "n", "w"]
const PREVIEW_SCALE := 3.0

var character: Node2D = null
var facing: int = 0

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    clip_contents = true

func rotate_step(direction: int) -> void:
    if direction == 0:
        return
    facing = posmod(facing + (1 if direction > 0 else -1), DIRECTIONS.size())
    queue_redraw()

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.10, 0.16, 0.22, 0.92))
    draw_rect(Rect2(4, size.y - 18, size.x - 8, 1), Color(0.30, 0.43, 0.47, 0.50))
    if character == null or not is_instance_valid(character):
        return

    var layers: Array[AnimatedSprite2D] = []
    for child in character.get_children():
        if child is AnimatedSprite2D:
            layers.append(child as AnimatedSprite2D)
    layers.sort_custom(func(a: AnimatedSprite2D, b: AnimatedSprite2D) -> bool:
        return a.z_index < b.z_index
    )

    var animation: StringName = StringName("idle-" + DIRECTIONS[facing])
    var origin: Vector2 = Vector2(roundf(size.x * 0.5), roundf(size.y * 0.69))
    draw_set_transform(origin, 0.0, Vector2(PREVIEW_SCALE, PREVIEW_SCALE))
    for sprite in layers:
        if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(animation):
            continue
        if sprite.sprite_frames.get_frame_count(animation) < 1:
            continue
        var texture: Texture2D = sprite.sprite_frames.get_frame_texture(animation, 0)
        if texture != null:
            draw_texture(texture, sprite.offset)
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
