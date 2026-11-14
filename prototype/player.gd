extends CharacterBody2D
## Arrow keys move the temporary player; Camera2D follows as its child.

const SPEED := 100.0
const EDGE_MARGIN := Vector2(8.0, 14.0)

@export var world_bounds := Rect2(Vector2.ZERO, Vector2(1280.0, 960.0))

func _physics_process(_delta: float) -> void:
    var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
    velocity = direction * SPEED
    move_and_slide()
    # Don't let the avatar leave the drawable map.
    global_position = global_position.clamp(
        world_bounds.position + EDGE_MARGIN,
        world_bounds.end - EDGE_MARGIN
    )

func _draw() -> void:
    draw_ellipse_placeholder()

func draw_ellipse_placeholder() -> void:
    # A visible 16x24 pixel prototype avatar, with a separate head.
    draw_rect(Rect2(-6, -7, 12, 16), Color("#5272c6"))
    draw_circle(Vector2(0, -12), 6.0, Color("#f1c28b"))
    draw_rect(Rect2(-6, 7, 5, 7), Color("#303956"))
    draw_rect(Rect2(1, 7, 5, 7), Color("#303956"))
