extends Control
## Large, pixel-crisp LPC portrait. Turn independently from the paused
## in-world avatar. Horizontal stick flicks rotate cyclically by 90 degrees.

# Clockwise as seen from above: front -> facing right -> back -> left.
const DIRECTIONS := ["s", "e", "n", "w"]
const PREVIEW_SCALE := 3.0

var character: Node2D = null
var facing: int = 0
# Creation has a gold-framed portrait centered on the full panel.
# Inventory uses the same frame but keeps its figure above armor stats.
var scenic_mode: bool = false
var framed_mode: bool = false

# Keep actual 64x64 RGBA frame textures alive until the outfit changes.
# This avoids GPU atlas-UV issues in the paused CanvasItem preview.
var _frame_cache: Dictionary = {}
# One choice per armor layer and facing until the outfit is replaced.
# No full-atlas rescanning while the user just keeps the menu open.
var _armor_choice_cache: Dictionary = {}


func clear_frame_cache() -> void:
    _frame_cache.clear()
    _armor_choice_cache.clear()
    queue_redraw()


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
    if scenic_mode or framed_mode:
        # Both interfaces share the subtle navy/gold frame. The inventory
        # keeps a divider for armor statistics below the character.
        draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.07, 0.12, 0.70))
        draw_rect(Rect2(0.5, 0.5, size.x - 1.0, size.y - 1.0), Color("#d6b77c"), false, 1.0)
        draw_rect(Rect2(4, 4, size.x - 8, 2), Color(0.95, 0.78, 0.43, 0.50))
        draw_rect(Rect2(4, size.y - 6, size.x - 8, 2), Color(0.95, 0.78, 0.43, 0.50))
        if framed_mode and not scenic_mode:
            draw_rect(Rect2(4, size.y - 58, size.x - 8, 1), Color("#d6b77c"))
    else:
        draw_rect(Rect2(Vector2.ZERO, size), Color(0.10, 0.16, 0.22, 0.92))
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
    # Center the full-height LPC figure in the creation portrait.
    # Backpack retains the original raised position above armor statistics.
    var vertical_anchor: float = 0.72 if scenic_mode else 0.57
    var origin: Vector2 = Vector2(roundf(size.x * 0.5), roundf(size.y * vertical_anchor))
    draw_set_transform(origin, 0.0, Vector2(PREVIEW_SCALE, PREVIEW_SCALE))
    for sprite in layers:
        if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(animation):
            continue
        if sprite.sprite_frames.get_frame_count(animation) < 1:
            continue

        var texture: Texture2D = sprite.sprite_frames.get_frame_texture(animation, 0)
        if texture == null:
            continue
        if sprite.name == "Armor" or sprite.name == "ArmorVestFront":
            texture = _select_armor_preview_frame(sprite, texture)
        if texture == null:
            continue

        # Crop the source image to the actual 64x64 LPC frame ONCE and
        # draw a standalone ImageTexture. Atlas UV rendering caused the
        # solid-white portrait regression after repeated armor changes.
        var display: Texture2D = texture
        if texture is AtlasTexture:
            var key: int = texture.get_instance_id()
            if _frame_cache.has(key):
                display = _frame_cache[key] as Texture2D
            else:
                var atlas_frame: AtlasTexture = texture as AtlasTexture
                if atlas_frame.atlas == null:
                    continue
                var atlas_image: Image = atlas_frame.atlas.get_image()
                if atlas_image == null or atlas_image.is_empty():
                    continue
                var region: Rect2 = atlas_frame.region
                var area: Rect2i = Rect2i(
                    Vector2i(int(region.position.x), int(region.position.y)),
                    Vector2i(int(region.size.x), int(region.size.y))
                )
                if area.size.x != 64 or area.size.y != 64:
                    continue
                if area.position.x < 0 or area.position.y < 0:
                    continue
                if area.end.x > atlas_image.get_width() or area.end.y > atlas_image.get_height():
                    continue
                var image: Image = atlas_image.get_region(area)
                if image == null or image.is_empty():
                    continue
                display = ImageTexture.create_from_image(image)
                _frame_cache[key] = display
        if display != null:
            draw_texture(display, sprite.offset)

    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Some authentic LPC armor sheets have fully drawn walking frames but
# incomplete idle frames in individual directions. Prefer an idle frame
# when it is usable; otherwise select the clearest walking frame of the
# SAME direction. This affects preview only, never world animations.
func _select_armor_preview_frame(sprite: AnimatedSprite2D, idle_frame: Texture2D) -> Texture2D:
    var key: String = "%d:%s" % [sprite.get_instance_id(), DIRECTIONS[facing]]
    if _armor_choice_cache.has(key):
        return _armor_choice_cache[key] as Texture2D

    var result: Texture2D = idle_frame
    var idle_atlas: AtlasTexture = idle_frame as AtlasTexture
    if idle_atlas == null or idle_atlas.atlas == null:
        _armor_choice_cache[key] = result
        return result

    var walk_name: StringName = StringName("walk-" + DIRECTIONS[facing])
    var frames: SpriteFrames = sprite.sprite_frames
    if not frames.has_animation(walk_name):
        _armor_choice_cache[key] = result
        return result

    # Read source pixels once, then score the central torso in each
    # prospective frame. No interpolation and no drawn replacement art.
    var pixels: Image = idle_atlas.atlas.get_image()
    if pixels == null or pixels.is_empty():
        _armor_choice_cache[key] = result
        return result

    var idle_score: int = _armor_torso_coverage(pixels, idle_atlas.region)
    var best_walk_score: int = 0
    var best_walk: Texture2D = null

    # Sample visually steadier walking poses first in tie cases.
    for frame_index in [0, 4, 2, 6, 1, 5, 3, 7]:
        if frame_index >= frames.get_frame_count(walk_name):
            continue
        var walk_texture: Texture2D = frames.get_frame_texture(walk_name, frame_index)
        var atlas_frame: AtlasTexture = walk_texture as AtlasTexture
        if atlas_frame == null or atlas_frame.atlas != idle_atlas.atlas:
            continue
        var coverage: int = _armor_torso_coverage(pixels, atlas_frame.region)
        if coverage > best_walk_score:
            best_walk_score = coverage
            best_walk = walk_texture

    # A tiny difference could be ordinary cloth motion. Switch only
    # when the idle image is clearly less complete than the walk image.
    if best_walk != null and best_walk_score >= 5 and best_walk_score > idle_score + maxi(4, int(idle_score * 0.20)):
        result = best_walk

    _armor_choice_cache[key] = result
    return result


func _armor_torso_coverage(pixels: Image, region: Rect2) -> int:
    var x0: int = int(region.position.x)
    var y0: int = int(region.position.y)
    if x0 < 0 or y0 < 0 or x0 + 64 > pixels.get_width() or y0 + 64 > pixels.get_height():
        return 0

    var visible: int = 0
    var almost_white: int = 0
    # Only the chest region matters. Sparse straps count less than an
    # actual torso piece, even if the texture has pixels elsewhere.
    for y in range(25, 49, 2):
        for x in range(19, 46, 2):
            var pixel: Color = pixels.get_pixel(x0 + x, y0 + y)
            if pixel.a < 0.25:
                continue
            visible += 1
            if pixel.r > 0.97 and pixel.g > 0.97 and pixel.b > 0.97:
                almost_white += 1
    # A solid white mask is not a usable visible armor frame.
    if visible >= 40 and almost_white * 5 >= visible * 4:
        return 0
    return visible
