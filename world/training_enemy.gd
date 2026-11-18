extends Node2D
## Lightweight procedural training enemy. No new sprite assets or physics
## bodies: the 320x240 R36H demo uses a small circle hurtbox and pixel art.

const MAX_HP := 9
const AGGRO_RANGE := 110.0
const LEASH_RANGE := 145.0
const MELEE_RANGE := 19.0
const SPEED := 31.0
const ATTACK_INTERVAL := 1.25
const RESPAWN_TIME := 7.0
const HURTBOX_RADIUS := 9.0

@export var spawn_position: Vector2 = Vector2.ZERO

var health: int = MAX_HP
var _alive: bool = true
var _attack_timer: float = 0.4
var _respawn_timer: float = 0.0
var _hurt_flash: float = 0.0
var _bob_time: float = 0.0


func _ready() -> void:
    position = spawn_position
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    queue_redraw()


func reset_enemy() -> void:
    health = MAX_HP
    position = spawn_position
    _alive = true
    _attack_timer = 0.6
    _respawn_timer = 0.0
    _hurt_flash = 0.0
    queue_redraw()


func is_alive() -> bool:
    return _alive


func hurtbox_radius() -> float:
    return HURTBOX_RADIUS


# Return 1 when the enemy successfully performs a melee attack.
# Damage and player invulnerability are handled by CombatController.
func advance(delta: float, target: Vector2) -> int:
    if not _alive:
        _respawn_timer -= delta
        if _respawn_timer <= 0.0:
            reset_enemy()
        return 0

    _hurt_flash = maxf(_hurt_flash - delta, 0.0)
    _attack_timer = maxf(_attack_timer - delta, 0.0)
    _bob_time += delta
    var distance: float = position.distance_to(target)
    var home_distance: float = position.distance_to(spawn_position)

    if distance < AGGRO_RANGE and home_distance < LEASH_RANGE:
        if distance > MELEE_RANGE - 3.0:
            var step: Vector2 = (target - position).normalized() * SPEED * delta
            position += step.limit_length(distance - MELEE_RANGE + 3.0)
        elif _attack_timer <= 0.0:
            _attack_timer = ATTACK_INTERVAL
            queue_redraw()
            return 1
    elif home_distance > 2.0:
        position = position.move_toward(spawn_position, SPEED * 0.6 * delta)

    queue_redraw()
    return 0


func take_hit(damage: int, attacker_position: Vector2) -> bool:
    if not _alive or damage <= 0:
        return false
    health = maxi(health - damage, 0)
    _hurt_flash = 0.20
    if health == 0:
        _alive = false
        _respawn_timer = RESPAWN_TIME
    else:
        var knockback: Vector2 = (position - attacker_position).normalized() * 8.0
        position = (position + knockback).clamp(spawn_position - Vector2(LEASH_RANGE, LEASH_RANGE), spawn_position + Vector2(LEASH_RANGE, LEASH_RANGE))
        _attack_timer = maxf(_attack_timer, 0.42)
    queue_redraw()
    return true


func _draw() -> void:
    if not _alive:
        return
    var lift: float = -1.0 if sin(_bob_time * 5.0) > 0.0 else 0.0
    var body: Color = Color("#f6a0a1") if _hurt_flash > 0.0 else Color("#67b894")
    var highlight: Color = Color("#b7dfb2") if _hurt_flash <= 0.0 else Color("#ffd0c3")
    draw_rect(Rect2(-10, 6, 20, 2), Color(0.10, 0.23, 0.18, 0.35))
    draw_rect(Rect2(-8, -4 + lift, 16, 12), Color("#254a48"))
    draw_rect(Rect2(-9, 0 + lift, 18, 7), body)
    draw_rect(Rect2(-6, -6 + lift, 12, 7), body)
    draw_rect(Rect2(-5, -5 + lift, 7, 3), highlight)
    draw_rect(Rect2(-4, -1 + lift, 2, 3), Color("#162b34"))
    draw_rect(Rect2(3, -1 + lift, 2, 3), Color("#162b34"))
    draw_rect(Rect2(-10, -14, 20, 3), Color("#26323e"))
    draw_rect(Rect2(-9, -13, 18.0 * float(health) / float(MAX_HP), 1), Color("#df8f76"))
