extends CharacterBody2D
## Skyval: analog left-stick movement only; D-pad reserved for gameplay actions.

const SPEED := 100.0
const STICK_DEADZONE := 0.22
const EDGE_MARGIN := Vector2(8.0, 14.0)

@export var world_bounds := Rect2(Vector2.ZERO, Vector2(1280.0, 960.0))

@onready var appearance: SkyvalCharacterVisual = $CharacterVisual

func _ready() -> void:
    Input.joy_connection_changed.connect(_on_joy_connection_changed)
    for device in Input.get_connected_joypads():
        _on_joy_connection_changed(device, true)

func _on_joy_connection_changed(device: int, connected: bool) -> void:
    if connected:
        print("Skyval controller: device=", device, " name=", Input.get_joy_name(device), " guid=", Input.get_joy_guid(device))
    else:
        print("Skyval controller disconnected: device=", device)

func _physics_process(_delta: float) -> void:
    var direction: Vector2 = _read_gamepad_direction()
    velocity = direction * SPEED
    move_and_slide()
    global_position = global_position.clamp(
        world_bounds.position + EDGE_MARGIN,
        world_bounds.end - EDGE_MARGIN
    )
    appearance.set_motion(direction)

func _read_gamepad_direction() -> Vector2:
    var pads: Array[int] = Input.get_connected_joypads()
    if pads.is_empty():
        return Vector2.ZERO
    var id: int = pads[0]

    # D-pad is intentionally NOT used for movement. It can serve as four
    # independent quick-item / equipment shortcuts once gameplay needs them.
    # Preserve the analog magnitude, including partial stick deflection.
    var stick := Vector2(
        Input.get_joy_axis(id, JOY_AXIS_LEFT_X),
        Input.get_joy_axis(id, JOY_AXIS_LEFT_Y)
    )
    var magnitude: float = stick.length()
    if magnitude <= STICK_DEADZONE:
        return Vector2.ZERO
    var intensity: float = clampf((magnitude - STICK_DEADZONE) / (1.0 - STICK_DEADZONE), 0.0, 1.0)
    return stick.normalized() * intensity
