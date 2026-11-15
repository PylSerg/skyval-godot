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
    # Leave the bottom 50+ pixels free for class/defense labels.
    draw_rect(Rect2(4, size.y - 58, size.x - 8, 1), Color(0.30, 0.43, 0.47, 0.50))
    if character == null or not is_instance_valid(character):
        return

    var layers: Array[AnimatedSprite2D] = []
    for child in character.get_children():
        # Outfit swaps replace AnimatedSprite2D children. Never reuse a
        # queued-for-deletion layer during a paused-menu redraw.
        if child is AnimatedSprite2D and not child.is_queued_for_deletion():
            layers.append(child as AnimatedSprite2D)
    layers.sort_custom(func(a: AnimatedSprite2D, b: AnimatedSprite2D) -> bool:
        return a.z_index < b.z_index
    )

    var animation: StringName = StringName("idle-" + DIRECTIONS[facing])
    # Raise the standing figure so its feet clear the relocated divider.
    var origin: Vector2 = Vector2(roundf(size.x * 0.5), roundf(size.y * 0.57))
    draw_set_transform(origin, 0.0, Vector2(PREVIEW_SCALE, PREVIEW_SCALE))
    for sprite in layers:
        if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(animation):
            continue
        if sprite.sprite_frames.get_frame_count(animation) < 1:
            continue

        var texture: Texture2D = sprite.sprite_frames.get_frame_texture(animation, 0)
        if texture == null:
            continue

        # LPC frames are AtlasTextures. Draw their explicit atlas region
        # instead of handing a nested AtlasTexture to draw_texture(), which
        # can show a solid white area during repeated rapid equipment swaps.
        if texture is AtlasTexture:
            var atlas_frame: AtlasTexture = texture as AtlasTexture
            if atlas_frame.atlas == null:
                continue
            var frame_region: Rect2 = atlas_frame.region
            if frame_region.size.x <= 0 or frame_region.size.y <= 0:
                continue
            draw_texture_rect_region(
                atlas_frame.atlas,
                Rect2(sprite.offset, frame_region.size),
                frame_region,
                Color.WHITE,
                false,
                true
            )
        else:
            draw_texture(texture, sprite.offset)

    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
