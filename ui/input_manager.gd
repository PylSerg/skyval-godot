extends Node
## Skyval's only native joypad input gateway.
## New interfaces register themselves as listeners and receive logical
## InputEventJoypadButton (Nintendo/Standard mapping applied ONCE here).
## The UI never needs to inspect or translate physical A/B/X/Y indices.

# Priority: name keyboard > game menu / global Start > appearance editor
# > backpack > loot chests / in-world interaction.
const NAME_PRIORITY := 500
const MENU_PRIORITY := 400
const APPEARANCE_PRIORITY := 300
const BACKPACK_PRIORITY := 200
const WORLD_PRIORITY := 100

var _listeners: Array[Dictionary] = []
# Physical device:index -> logical index held when PRESSED. Releasing
# the button uses that original value even if layout changed meanwhile.
var _pressed_physical: Dictionary = {}
var _locale: Node


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    _locale = get_node_or_null("/root/SkyvalLocale")


func register_listener(listener: Node, priority: int) -> void:
    if listener == null or not listener.has_method("skyval_accepts_input") or not listener.has_method("handle_skyval_input"):
        push_error("SkyvalInput: listeners need skyval_accepts_input(event) and handle_skyval_input(event)")
        return
    unregister_listener(listener)
    _listeners.append({"node": weakref(listener), "priority": priority})
    _listeners.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return int(a["priority"]) > int(b["priority"])
    )


func unregister_listener(listener: Node) -> void:
    for index in range(_listeners.size() - 1, -1, -1):
        var candidate: Node = (_listeners[index]["node"] as WeakRef).get_ref() as Node
        if candidate == null or candidate == listener:
            _listeners.remove_at(index)


func _active_listeners() -> Array[Node]:
    var active: Array[Node] = []
    for index in range(_listeners.size() - 1, -1, -1):
        var candidate: Node = (_listeners[index]["node"] as WeakRef).get_ref() as Node
        if candidate == null or not is_instance_valid(candidate):
            _listeners.remove_at(index)
        elif candidate.is_inside_tree():
            active.append(candidate)
    # Reverse traversal above is for safe removal; actual order is priority.
    active.reverse()
    return active


func _logical_button(physical: int) -> int:
    if _locale == null or str(_locale.get("input_layout")) != "nintendo":
        return physical
    match physical:
        JOY_BUTTON_A:
            return JOY_BUTTON_B
        JOY_BUTTON_B:
            return JOY_BUTTON_A
        JOY_BUTTON_X:
            return JOY_BUTTON_Y
        JOY_BUTTON_Y:
            return JOY_BUTTON_X
    return physical


func _input(event: InputEvent) -> void:
    if event is InputEventJoypadButton:
        var original: InputEventJoypadButton = event as InputEventJoypadButton
        var physical_key: String = "%d:%d" % [original.device, original.button_index]
        var logical: int
        if original.pressed:
            # Some controllers generate repeats while held; one action
            # per physical press is enough until that same key is released.
            if _pressed_physical.has(physical_key):
                get_viewport().set_input_as_handled()
                return
            logical = _logical_button(original.button_index)
            _pressed_physical[physical_key] = logical
        else:
            logical = int(_pressed_physical.get(physical_key, _logical_button(original.button_index)))
            _pressed_physical.erase(physical_key)

        var normalized := InputEventJoypadButton.new()
        normalized.device = original.device
        normalized.button_index = logical
        normalized.pressed = original.pressed
        normalized.pressure = original.pressure
        if original.pressed:
            _dispatch(normalized)
        else:
            # Deliver releases to EVERY registered screen. A screen may
            # close during its own press, or a modal may replace it, but
            # its press latch must always be cleared.
            for listener in _active_listeners():
                listener.call("handle_skyval_input", normalized)
        get_viewport().set_input_as_handled()
    elif event is InputEventJoypadMotion:
        # Axes are not remapped. In-world movement reads Input directly;
        # the focused menu still receives axis changes via this gateway.
        _dispatch(event)


func _dispatch(event: InputEvent) -> void:
    for listener in _active_listeners():
        if bool(listener.call("skyval_accepts_input", event)):
            listener.call("handle_skyval_input", event)
            get_viewport().set_input_as_handled()
            return
