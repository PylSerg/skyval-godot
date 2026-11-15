extends Node
## Shared pause ownership for all blocking Skyval UI layers.
## The game stays paused until the last blocking interface closes.
## The original pause state is restored when all UI layers are gone.

var _open_interfaces: Dictionary = {}
var _tracked_interfaces: Dictionary = {}
var _paused_before_ui: bool = false


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS


func set_open(owner: Node, is_open: bool) -> void:
    var owner_id: int = owner.get_instance_id()
    var was_blocked: bool = not _open_interfaces.is_empty()

    if is_open:
        if not _tracked_interfaces.has(owner_id):
            _tracked_interfaces[owner_id] = true
            owner.tree_exiting.connect(_on_interface_exiting.bind(owner_id))
        _open_interfaces[owner_id] = true
    else:
        _open_interfaces.erase(owner_id)

    _sync_pause(was_blocked)


func has_blocking_interface() -> bool:
    return not _open_interfaces.is_empty()


func _on_interface_exiting(owner_id: int) -> void:
    var was_blocked: bool = not _open_interfaces.is_empty()
    _open_interfaces.erase(owner_id)
    _tracked_interfaces.erase(owner_id)
    _sync_pause(was_blocked)


func _sync_pause(was_blocked: bool) -> void:
    var is_blocked: bool = not _open_interfaces.is_empty()

    if is_blocked:
        if not was_blocked:
            _paused_before_ui = get_tree().paused
        get_tree().paused = true
    elif was_blocked:
        get_tree().paused = _paused_before_ui
