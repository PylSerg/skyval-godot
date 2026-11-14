extends CharacterBody2D
## Prototype movement, now driven by an independent four-direction character visual.

const SPEED := 100.0
const EDGE_MARGIN := Vector2(8.0, 14.0)

@export var world_bounds := Rect2(Vector2.ZERO, Vector2(1280.0, 960.0))

@onready var appearance: SkyvalCharacterVisual = $CharacterVisual

func _physics_process(_delta: float) -> void:
    var direction: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
    velocity = direction * SPEED
    move_and_slide()
    global_position = global_position.clamp(
        world_bounds.position + EDGE_MARGIN,
        world_bounds.end - EDGE_MARGIN
    )
    appearance.set_motion(direction)

func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey:
        return
    if not event.pressed or event.echo:
        return
    # PC-only appearance smoke test; future inventory UI will call the same methods.
    match event.keycode:
        KEY_1:
            appearance.cycle_outfit()
        KEY_2:
            appearance.cycle_hair()
        KEY_3:
            appearance.toggle_weapon()
        KEY_4:
            appearance.toggle_lpc_preview()
        KEY_5:
            appearance.cycle_lpc_skin()
