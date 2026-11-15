extends Node2D
## Temporary camera-test world (not intended as final Skyval graphics).

const WORLD_SIZE := Vector2(1280, 960)
const TILE_SIZE := 16
const GameMenuScript = preload("res://ui/game_menu.gd")

func _ready() -> void:
    # One source of truth for world boundaries.
    var camera: Camera2D = $Player/Camera2D
    camera.limit_left = 0
    camera.limit_top = 0
    camera.limit_right = int(WORLD_SIZE.x)
    camera.limit_bottom = int(WORLD_SIZE.y)
    camera.limit_enabled = true

    # Player stops at the same world edges as the camera.
    var player: CharacterBody2D = $Player
    player.set("world_bounds", Rect2(Vector2.ZERO, WORLD_SIZE))

    # Scenes edited in Godot can be saved from a stale in-memory tree,
    # accidentally removing GameMenu. Recover it without touching .tscn.
    _ensure_game_menu()

func _ensure_game_menu() -> void:
    if has_node("GameMenu"):
        return
    var game_menu: CanvasLayer = GameMenuScript.new() as CanvasLayer
    game_menu.name = "GameMenu"
    game_menu.layer = 3
    add_child(game_menu)
    print("Skyval: GameMenu missing from scene; created automatically at runtime.")

func _draw() -> void:
    # A large enough map to make scrolling visible in 320x240.
    draw_rect(Rect2(Vector2.ZERO, WORLD_SIZE), Color("#477956"))
    for x in range(0, int(WORLD_SIZE.x) + 1, TILE_SIZE):
        draw_line(Vector2(x, 0), Vector2(x, WORLD_SIZE.y), Color("#669267"), 1.0)
    for y in range(0, int(WORLD_SIZE.y) + 1, TILE_SIZE):
        draw_line(Vector2(0, y), Vector2(WORLD_SIZE.x, y), Color("#669267"), 1.0)

    # Road crossing the test world.
    draw_rect(Rect2(0, 450, WORLD_SIZE.x, 60), Color("#bd9d6a"))
    draw_rect(Rect2(610, 0, 60, WORLD_SIZE.y), Color("#bd9d6a"))

    # Fixed landmarks make camera movement obvious.
    for point in [Vector2(280, 250), Vector2(470, 670), Vector2(880, 260), Vector2(990, 720)]:
        draw_circle(point, 23.0, Color("#1f573d"))
        draw_circle(point + Vector2(-5, -6), 15.0, Color("#2b8c55"))
    draw_rect(Rect2(790, 520, 85, 64), Color("#e7c691"))
    draw_rect(Rect2(784, 505, 97, 20), Color("#994c4a"))
    draw_rect(Rect2(825, 551, 17, 33), Color("#523c38"))

    # Visible outline for checking map boundaries during development.
    draw_rect(Rect2(Vector2.ZERO, WORLD_SIZE), Color("#e9d68c"), false, 2.0)
