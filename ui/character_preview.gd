extends Control
## Live pixel-art preview of the actual LPC layers, drawn without loading
## extra copies of the massive source sheets.

var character: Node2D = null

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.10, 0.16, 0.22, 0.92))
    draw_rect(Rect2(2, size.y - 24, size.x - 4, 1), Color(0.30, 0.43, 0.47, 0.8))

    if character == null or not is_instance_valid(character):
        return

    var layers: Array[AnimatedSprite2D] = []
    for child in character.get_children():
        if child is AnimatedSprite2D:
            layers.append(child as AnimatedSprite2D)
    layers.sort_custom(func(a: AnimatedSprite2D, b: AnimatedSprite2D) -> bool:
        return a.z_index < b.z_index
    )

    # Full 64px LPC cells are shown at 2x scale without interpolation.
    draw_set_transform(Vector2(size.x * 0.5, 127), 0.0, Vector2(2.0, 2.0))
    for sprite in layers:
        if sprite.sprite_frames == null:
            continue
        if sprite.sprite_frames.get_frame_count(sprite.animation) <= sprite.frame:
            continue
        var texture: Texture2D = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
        if texture != null:
            draw_texture(texture, sprite.offset)
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
