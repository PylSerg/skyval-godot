extends Camera2D
## Skyval camera v3: smooth follow, right-stick look-around, pixel snapping.
## This node is top_level=true, so it is NOT dragged by the player's transform.

@export_range(1.0, 25.0, 0.5) var follow_speed: float = 8.0
@export_range(1.0, 25.0, 0.5) var look_speed: float = 12.0
@export_range(1.0, 25.0, 0.5) var return_speed: float = 7.0
@export_range(0.0, 140.0, 1.0) var look_distance_x: float = 96.0
@export_range(0.0, 100.0, 1.0) var look_distance_y: float = 72.0
@export_range(0.05, 0.50, 0.01) var stick_deadzone: float = 0.22

@onready var player: Node2D = get_parent() as Node2D

var _look_offset: Vector2 = Vector2.ZERO
var _smooth_position: Vector2 = Vector2.ZERO

func _ready() -> void:
    top_level = true
    position_smoothing_enabled = false
    _smooth_position = player.global_position
    global_position = _smooth_position.round()

func _physics_process(delta: float) -> void:
    var look_input: Vector2 = _read_look_input()
    var desired_offset: Vector2 = Vector2(
        look_input.x * look_distance_x,
        look_input.y * look_distance_y
    )

    # Look quickly; return to the player more gently when the stick is released.
    var offset_speed: float = look_speed if look_input.length_squared() > 0.0 else return_speed
    var offset_weight: float = 1.0 - exp(-offset_speed * delta)
    _look_offset = _look_offset.lerp(desired_offset, offset_weight)
    if _look_offset.distance_squared_to(desired_offset) < 0.0001:
        _look_offset = desired_offset

    # Follow the player and smoothly reach the look-ahead offset.
    var desired_position: Vector2 = player.global_position + _look_offset
    var follow_weight: float = 1.0 - exp(-follow_speed * delta)
    _smooth_position = _smooth_position.lerp(desired_position, follow_weight)
    if _smooth_position.distance_squared_to(desired_position) < 0.0001:
        _smooth_position = desired_position

    # With a 320x240 viewport, these are logical pixels. Avoid fractional
    # camera coordinates so the 2x pixel-art scaling remains crisp.
    global_position = _smooth_position.round()

func _read_look_input() -> Vector2:
    # PC test: I/J/K/L emulate the right stick, while arrows move the player.
    var keyboard_input: Vector2 = Vector2.ZERO
    if Input.is_key_pressed(KEY_J):
        keyboard_input.x -= 1.0
    if Input.is_key_pressed(KEY_L):
        keyboard_input.x += 1.0
    if Input.is_key_pressed(KEY_I):
        keyboard_input.y -= 1.0
    if Input.is_key_pressed(KEY_K):
        keyboard_input.y += 1.0
    keyboard_input = keyboard_input.normalized()

    var result: Vector2 = keyboard_input
    for joy_id in Input.get_connected_joypads():
        var raw_input: Vector2 = Vector2(
            Input.get_joy_axis(joy_id, JOY_AXIS_RIGHT_X),
            Input.get_joy_axis(joy_id, JOY_AXIS_RIGHT_Y)
        )
        var magnitude: float = raw_input.length()
        if magnitude <= stick_deadzone:
            continue
        var strength: float = clampf(
            (magnitude - stick_deadzone) / (1.0 - stick_deadzone), 0.0, 1.0
        )
        var stick_input: Vector2 = raw_input.normalized() * strength
        if stick_input.length_squared() > result.length_squared():
            result = stick_input
    return result
