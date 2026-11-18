extends Node2D
## Skyval combat prototype for R36H: normalized Y to attack, geometric
## forward-facing melee hurtbox, two hostile slimes and a tiny HP HUD.
## Damage occurs exactly once per swing, never on every animation frame.

const EnemyScript = preload("res://world/training_enemy.gd")
const UiTheme = preload("res://ui/skyval_theme.gd")
const SWING_DURATION := 0.25
const HIT_DELAY := 0.09
const ATTACK_COOLDOWN := 0.42
const PLAYER_MAX_HP := 20
const ENEMY_POSITIONS := [Vector2(724, 612), Vector2(980, 646)]
const FONT_PATH := "res://assets/fonts/CascadiaMono-Regular.ttf"

var _player: CharacterBody2D
var _appearance: Node
var _menu: Node
var _inventory: Node
var _locale: Node
var _pause: Node
var _enemies: Array[Node2D] = []
var _health: int = PLAYER_MAX_HP
var _invulnerability: float = 0.0
var _swing_left: float = 0.0
var _cooldown_left: float = 0.0
var _swing_hit_pending: bool = false
var _swing_facing: Vector2 = Vector2.DOWN
var _sword_swing: bool = false
var _hud: Control
var _hp_label: Label
var _attack_label: Label


func _ready() -> void:
    # Keep the tiny HUD in sync even while a menu pauses the world.
    # Combat/enemy simulation below still refuses to advance when paused.
    process_mode = Node.PROCESS_MODE_ALWAYS
    z_index = 50
    _player = get_parent().get_node_or_null("Player") as CharacterBody2D
    if _player == null:
        push_error("Skyval Combat: missing Player.")
        set_physics_process(false)
        return
    _appearance = _player.get_node_or_null("CharacterVisual")
    _menu = get_parent().get_node_or_null("GameMenu")
    _inventory = get_node_or_null("/root/SkyvalInventory")
    _locale = get_node_or_null("/root/SkyvalLocale")
    _pause = get_node_or_null("/root/SkyvalUiPause")

    for index in range(ENEMY_POSITIONS.size()):
        var enemy: Node2D = EnemyScript.new() as Node2D
        enemy.name = "Slime_%d" % [index + 1]
        enemy.set("spawn_position", ENEMY_POSITIONS[index])
        add_child(enemy)
        _enemies.append(enemy)

    _build_hud()
    if _locale != null and _locale.has_signal("language_changed"):
        _locale.connect("language_changed", Callable(self, "_refresh_hud"))
    if _inventory != null and _inventory.has_signal("changed"):
        _inventory.connect("changed", Callable(self, "_refresh_hud"))
    var gateway: Node = get_node_or_null("/root/SkyvalInput")
    if gateway != null:
        # All screen overlays have higher input priority. Gameplay Y is
        # normalized centrally, just like inventory/chests/menu buttons.
        gateway.call("register_listener", self, 90)
    _refresh_hud()


func _session_active() -> bool:
    return _menu != null and bool(_menu.call("has_started_session"))


func _can_fight() -> bool:
    if not _session_active() or get_tree().paused:
        return false
    if bool(_menu.call("is_open")):
        return false
    if _pause != null and bool(_pause.call("has_blocking_interface")):
        return false
    return true


func skyval_accepts_input(event: InputEvent) -> bool:
    if not _can_fight() or not (event is InputEventJoypadButton):
        return false
    var button: InputEventJoypadButton = event as InputEventJoypadButton
    return button.pressed and button.button_index == JOY_BUTTON_Y


func handle_skyval_input(event: InputEvent) -> void:
    if event is InputEventJoypadButton:
        var joy: InputEventJoypadButton = event as InputEventJoypadButton
        if joy.pressed and joy.button_index == JOY_BUTTON_Y:
            _begin_swing()


# Laptop smoke test, while the physical R36H uses the logical Y button.
func _unhandled_key_input(event: InputEvent) -> void:
    if event is InputEventKey:
        var key: InputEventKey = event as InputEventKey
        if key.pressed and not key.echo and key.keycode == KEY_J and _can_fight():
            _begin_swing()
            get_viewport().set_input_as_handled()


func _begin_swing() -> void:
    if not _can_fight() or _cooldown_left > 0.0:
        return
    _swing_left = SWING_DURATION
    _cooldown_left = ATTACK_COOLDOWN
    _swing_hit_pending = true
    _swing_facing = _facing_vector()
    _sword_swing = _inventory != null and int(_inventory.call("get_total_attack")) > 0
    # The hit cone and the actual LPC sprite animation share one swing timer.
    if _appearance != null and _appearance.has_method("begin_attack"):
        _appearance.call("begin_attack")
    queue_redraw()


func _facing_vector() -> Vector2:
    if _appearance == null:
        return Vector2.DOWN
    match int(_appearance.get("facing")):
        1:
            return Vector2.LEFT
        2:
            return Vector2.RIGHT
        3:
            return Vector2.UP
    return Vector2.DOWN


func _physics_process(delta: float) -> void:
    if _hud != null:
        _hud.visible = _can_fight()
    if not _can_fight():
        return

    _cooldown_left = maxf(_cooldown_left - delta, 0.0)
    _invulnerability = maxf(_invulnerability - delta, 0.0)
    if _swing_left > 0.0:
        _swing_left = maxf(_swing_left - delta, 0.0)
        if _appearance != null and _appearance.has_method("set_attack_progress"):
            _appearance.call("set_attack_progress", 1.0 - _swing_left / SWING_DURATION)
        if _swing_hit_pending and _swing_left <= SWING_DURATION - HIT_DELAY:
            _swing_hit_pending = false
            _hit_enemies()
        if _swing_left <= 0.0 and _appearance != null and _appearance.has_method("end_attack"):
            _appearance.call("end_attack")
        queue_redraw()

    for enemy in _enemies:
        if not is_instance_valid(enemy):
            continue
        var attack: int = int(enemy.call("advance", delta, _player.global_position))
        if attack > 0 and _invulnerability <= 0.0:
            _receive_damage(attack, enemy.global_position)


func _hit_enemies() -> void:
    var attack_damage: int = maxi(1, int(_inventory.call("get_total_attack"))) if _inventory != null else 1
    var hit_range: float = 36.0 if _sword_swing else 23.0
    for enemy in _enemies:
        if not is_instance_valid(enemy) or not bool(enemy.call("is_alive")):
            continue
        var to_enemy: Vector2 = enemy.global_position - _player.global_position
        var separation: float = to_enemy.length()
        # Radius 9 is the enemy's hurtbox, allowing edge contact.
        if separation > hit_range + float(enemy.call("hurtbox_radius")):
            continue
        if separation > 0.001 and to_enemy.normalized().dot(_swing_facing) < 0.38:
            continue
        enemy.call("take_hit", attack_damage, _player.global_position)


func _receive_damage(damage: int, source_position: Vector2) -> void:
    # Reuse existing physical armor: each two points of protection absorb
    # one point from a slime hit (up to 2), never making the player immune.
    var protection: int = int(_inventory.call("get_total_armor")) if _inventory != null else 0
    var blocked: int = mini(2, protection / 2)
    var received: int = maxi(1, damage - blocked)
    _health = maxi(_health - received, 0)
    _invulnerability = 0.9
    var away: Vector2 = (_player.global_position - source_position).normalized()
    var bounds: Rect2 = _player.get("world_bounds")
    _player.global_position = (_player.global_position + away * 10.0).clamp(
        bounds.position + Vector2(8.0, 14.0), bounds.end - Vector2(8.0, 14.0)
    )
    if _health == 0:
        # Training demo: revive at the original world spawn, preserving
        # equipped inventory and never writing an automatic save.
        _player.global_position = Vector2(640, 480)
        _player.velocity = Vector2.ZERO
        _health = PLAYER_MAX_HP
        _invulnerability = 2.0
        for enemy in _enemies:
            if is_instance_valid(enemy):
                enemy.call("reset_enemy")
    _refresh_hud()


func get_save_state() -> Dictionary:
    return {"hp": _health}


func load_save_state(data: Variant) -> void:
    reset_combat_state()
    if data is Dictionary:
        _health = clampi(int(data.get("hp", PLAYER_MAX_HP)), 1, PLAYER_MAX_HP)
    _refresh_hud()


func reset_combat_state() -> void:
    _health = PLAYER_MAX_HP
    _invulnerability = 0.0
    _swing_left = 0.0
    _cooldown_left = 0.0
    _swing_hit_pending = false
    if _appearance != null and _appearance.has_method("end_attack"):
        _appearance.call("end_attack")
    for enemy in _enemies:
        if is_instance_valid(enemy):
            enemy.call("reset_enemy")
    _refresh_hud()
    queue_redraw()


func _tr(key: String) -> String:
    return str(_locale.call("t", key)) if _locale != null else key


func _refresh_hud() -> void:
    if _hp_label == null or _attack_label == null:
        return
    _hp_label.text = "%s %d/%d" % [_tr("combat.hp"), _health, PLAYER_MAX_HP]
    var power: int = int(_inventory.call("get_total_attack")) if _inventory != null else 0
    _attack_label.text = _tr("combat.sword_hint") if power > 0 else _tr("combat.fist_hint")


func _build_hud() -> void:
    var layer := CanvasLayer.new()
    layer.layer = 1
    add_child(layer)
    _hud = Control.new()
    _hud.position = Vector2(7, 7)
    _hud.size = Vector2(122, 42)
    _hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
    layer.add_child(_hud)
    var bg := Panel.new()
    bg.size = _hud.size
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    bg.add_theme_stylebox_override("panel", UiTheme.panel_style(0.78, 4.0))
    _hud.add_child(bg)

    var font: FontFile = null
    if ResourceLoader.exists(FONT_PATH):
        font = load(FONT_PATH) as FontFile
    _hp_label = Label.new()
    _hp_label.position = Vector2(7, 2)
    _hp_label.size = Vector2(112, 18)
    _hp_label.add_theme_font_size_override("font_size", 14)
    _hp_label.add_theme_color_override("font_color", Color("#f0f1ed"))
    if font != null:
        _hp_label.add_theme_font_override("font", font)
    _hud.add_child(_hp_label)
    _attack_label = Label.new()
    _attack_label.position = Vector2(7, 20)
    _attack_label.size = Vector2(112, 18)
    _attack_label.add_theme_font_size_override("font_size", 14)
    _attack_label.add_theme_color_override("font_color", Color("#e7ca86"))
    if font != null:
        _attack_label.add_theme_font_override("font", font)
    _hud.add_child(_attack_label)
    _hud.hide()


func _draw() -> void:
    if _swing_left <= 0.0 or _player == null:
        return
    # The authentic LPC 128px attack already contains the moving blade.
    # Do not overlay a second blade-shaped trail on the opposite hand.
    if _sword_swing and _appearance != null and _appearance.has_method("uses_real_sword_slash"):
        if bool(_appearance.call("uses_real_sword_slash")):
            return
    # Camera-relative clockwise HALF-circle from the supplied diagram.
    # Starting blade angle -> finishing blade angle:
    # South: right -> down -> left.
    # North: left -> up -> right.
    # West:  down -> left -> up.
    # East:  up -> right -> down.
    # Godot's positive angles rotate clockwise because screen Y points down.
    # Body/armor/sword frames stay in their original cardinal direction;
    # LPC slash artwork already supplies the torso/arm follow-through.
    var progress: float = clampf(1.0 - _swing_left / SWING_DURATION, 0.0, 1.0)
    var center: Vector2 = _player.position + _swing_facing * 10.0
    var radius: float = (22.0 if _sword_swing else 14.0) + progress * 7.0
    var start_angle: float = _swing_facing.angle() - PI * 0.5
    var swing_angle: float = start_angle + progress * PI
    var arc_color: Color = Color("#fff2c6") if _sword_swing else Color("#d6a77e")
    arc_color.a = 0.85 * (1.0 - progress * 0.70)
    # A short moving trail rather than a full stationary semicircle.
    draw_arc(center, radius, swing_angle - 0.32, swing_angle + 0.04,
        8, arc_color, 2.0, false)
