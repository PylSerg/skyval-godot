extends Node2D
## Test loot chest beside the prototype house (world coordinates).
## A opens it nearby. A marks individual items; the bottom action takes
## only marked items. X takes everything and closes; B leaves the rest.

const LOOT_DISTANCE := 35.0
const STICK_PRESS := 0.65
const STICK_RELEASE := 0.42
const FONT_PATH := "res://assets/fonts/CascadiaMono-Regular.ttf"
const MIN_UI_FONT_SIZE := 14
const UiTheme = preload("res://ui/skyval_theme.gd")
const ControllerHintsScript = preload("res://ui/nintendo_hints.gd")

# One shared chest UI, with independent stock and world placement.
@export_enum("clothes", "armor", "weapon") var chest_kind: String = "clothes"
@export var chest_spawn: Vector2 = Vector2(905, 554)

var _opened: bool = false
var _root: Control
var _heading: Label
var _hint: Control
var _scroll: ScrollContainer
var _rows: VBoxContainer
var _empty: Label
var _take: Button
var _buttons: Array[Button] = []
var _selection: Dictionary = {}
var _selected_index: int = 0
var _pressed: Dictionary = {}
var _left_axis: Dictionary = {}
var _ignore_until: int = 0
var _font: FontFile
var _prompt: Label
var _locale: Node
var _inventory: Node


func _ready() -> void:
    # The chest overlay must receive input even while the world is paused.
    process_mode = Node.PROCESS_MODE_ALWAYS
    position = chest_spawn
    _locale = get_node_or_null("/root/SkyvalLocale")
    _inventory = get_node_or_null("/root/SkyvalInventory")
    if ResourceLoader.exists(FONT_PATH):
        _font = load(FONT_PATH) as FontFile
        if _font != null:
            _font = _font.duplicate() as FontFile
            _font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
            _font.hinting = TextServer.HINTING_NORMAL

    _prompt = Label.new()
    _prompt.text = "A"
    _prompt.position = Vector2(-5, -31)
    _prompt.add_theme_font_size_override("font_size", MIN_UI_FONT_SIZE)
    if _font != null:
        _prompt.add_theme_font_override("font", _font)
    add_child(_prompt)
    _prompt.hide()

    _build_interface()
    _root.hide()
    if _locale != null:
        _locale.connect("language_changed", Callable(self, "_refresh"))
    get_node("/root/SkyvalInput").call("register_listener", self, 100)


func _tr(key: String) -> String:
    if _locale == null:
        return key
    return str(_locale.call("t", key))


func is_open() -> bool:
    return _opened


func close_for_menu() -> void:
    if _opened:
        _set_open(false)


func _player_nearby() -> bool:
    var player: Node2D = get_parent().get_node_or_null("Player") as Node2D
    return player != null and player.global_position.distance_to(global_position) <= LOOT_DISTANCE


func _can_open_from_world() -> bool:
    if _inventory == null:
        return false
    var menu: Node = get_parent().get_node_or_null("GameMenu")
    var pause_manager: Node = get_node_or_null("/root/SkyvalUiPause")
    if menu == null or not bool(menu.call("has_started_session")):
        return false
    if pause_manager != null and bool(pause_manager.call("has_blocking_interface")):
        return false
    return _player_nearby()


func _process(_delta: float) -> void:
    _prompt.visible = not _opened and _can_open_from_world()


func skyval_accepts_input(event: InputEvent) -> bool:
    if _opened:
        return true
    if event is InputEventJoypadButton:
        var button: InputEventJoypadButton = event as InputEventJoypadButton
        return button.pressed and button.button_index == JOY_BUTTON_A and _can_open_from_world()
    return false


func handle_skyval_input(event: InputEvent) -> void:
    if event is InputEventJoypadButton:
        var joy: InputEventJoypadButton = event as InputEventJoypadButton
        var key: String = "%s:%s" % [joy.device, joy.button_index]
        if not joy.pressed:
            _pressed.erase(key)
            return
        if _pressed.has(key):
            return
        _pressed[key] = true
        # All actions arrive as logical buttons from SkyvalInput.
        var action_button: int = joy.button_index
        if _opened:
            # Let GameMenu own Start/R3, even while chest loot is visible.
            if action_button == JOY_BUTTON_START or action_button == JOY_BUTTON_RIGHT_STICK:
                return
            if Time.get_ticks_msec() < _ignore_until:
                return
            match action_button:
                JOY_BUTTON_B:
                    _set_open(false)
                JOY_BUTTON_A:
                    if _selected_index == _buttons.size():
                        _take_selected()
                    else:
                        var stock: Array[String] = _inventory.call("get_chest_items", chest_kind)
                        if _selected_index >= 0 and _selected_index < stock.size():
                            _toggle_item(stock[_selected_index])
                JOY_BUTTON_X:
                    _take_all()
                JOY_BUTTON_DPAD_UP:
                    _move_selection(-1)
                JOY_BUTTON_DPAD_DOWN:
                    _move_selection(1)
            get_viewport().set_input_as_handled()
        elif action_button == JOY_BUTTON_A and _can_open_from_world():
            _set_open(true)
            get_viewport().set_input_as_handled()
    elif event is InputEventJoypadMotion and _opened:
        var motion: InputEventJoypadMotion = event as InputEventJoypadMotion
        if motion.axis == JOY_AXIS_LEFT_Y:
            var key: String = "%s:%s" % [motion.device, motion.axis]
            var before: int = int(_left_axis.get(key, 0))
            var after: int = 0
            if motion.axis_value >= STICK_PRESS:
                after = 1
            elif motion.axis_value <= -STICK_PRESS:
                after = -1
            elif absf(motion.axis_value) > STICK_RELEASE:
                after = before
            if after != before:
                _left_axis[key] = after
                if after != 0:
                    _move_selection(after)
        get_viewport().set_input_as_handled()


func _set_open(next_open: bool) -> void:
    if _opened == next_open:
        return
    _opened = next_open
    _root.visible = next_open
    if next_open:
        _selection.clear()
        _selected_index = 0
        _pressed.clear()
        _left_axis.clear()
        _ignore_until = Time.get_ticks_msec() + 150
        _refresh()
    else:
        _selection.clear()
        get_viewport().gui_release_focus()
    var pause_manager: Node = get_node_or_null("/root/SkyvalUiPause")
    if pause_manager != null:
        pause_manager.call("set_open", self, next_open)
    else:
        get_tree().paused = next_open


func _move_selection(direction: int) -> void:
    # One additional navigable row is the take-selected action. Stop at
    # the first/last row instead of jumping to the opposite end.
    var next_index: int = clampi(_selected_index + direction, 0, _buttons.size())
    if next_index == _selected_index:
        return
    _selected_index = next_index
    _update_highlight()
    var selected: Control = _take if _selected_index == _buttons.size() else _buttons[_selected_index]
    _reveal(selected)


func _reveal(target: Control) -> void:
    if target == _take:
        return
    await get_tree().process_frame
    if _opened and is_instance_valid(target):
        _scroll.ensure_control_visible(target)


func _toggle_item(item_id: String) -> void:
    if _selection.has(item_id):
        _selection.erase(item_id)
    else:
        _selection[item_id] = true
    _refresh()


func _take_selected() -> void:
    var stock: Array[String] = _inventory.call("get_chest_items", chest_kind)
    var chosen: Array[String] = []
    for item_id in stock:
        if _selection.has(item_id):
            chosen.append(item_id)
    _take_items(chosen)


func _take_all() -> void:
    # X ignores checkboxes and transfers every item still in the chest.
    var stock: Array[String] = _inventory.call("get_chest_items", chest_kind)
    if stock.is_empty():
        _set_open(false)
        return
    _take_items(stock)


func _take_items(items: Array[String]) -> void:
    if items.is_empty():
        return
    var taken: int = int(_inventory.call("take_from_chest", items, chest_kind))
    if taken <= 0:
        return

    # Loot stays in memory until the player chooses Save or Quick Save.

    _selection.clear()
    _selected_index = 0
    var remaining: Array[String] = _inventory.call("get_chest_items", chest_kind)
    if remaining.is_empty():
        # Works for both X -> Take All and A -> Take Selected (all checked).
        _set_open(false)
    else:
        _refresh()


func _refresh() -> void:
    if _root == null or _inventory == null:
        return
    match chest_kind:
        "armor":
            _heading.text = _tr("chest.armor_title")
        "weapon":
            _heading.text = _tr("chest.weapon_title")
        _:
            _heading.text = _tr("chest.title")
    _hint.call("set_hint", _tr("chest.hint"))
    _empty.text = _tr("chest.empty")
    var stock: Array[String] = _inventory.call("get_chest_items", chest_kind)
    for child in _rows.get_children():
        if child == _empty:
            continue
        _rows.remove_child(child)
        child.queue_free()
    _buttons.clear()
    _empty.visible = stock.is_empty()
    for item_id in stock:
        var info: Dictionary = _inventory.call("get_item", item_id)
        var button: Button = _button()
        button.text = ("[x] " if _selection.has(item_id) else "[ ] ") + _tr(str(info.get("label", "")))
        button.custom_minimum_size.y = 24
        button.pressed.connect(_toggle_item.bind(item_id))
        _rows.add_child(button)
        _buttons.append(button)
    _take.text = _tr("chest.take_selected") + " (%d)" % _selection.size()
    _take.disabled = _selection.is_empty()
    _selected_index = mini(_selected_index, _buttons.size())
    _update_highlight()


func _update_highlight() -> void:
    var controls: Array = _buttons.duplicate()
    controls.append(_take)
    for index in range(controls.size()):
        var button: Button = controls[index]
        var active: bool = index == _selected_index
        UiTheme.apply_button(button, active, button.disabled, 3.0)


func _build_interface() -> void:
    var overlay := CanvasLayer.new()
    overlay.layer = 5
    overlay.process_mode = Node.PROCESS_MODE_ALWAYS
    add_child(overlay)

    _root = Control.new()
    _root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _root.mouse_filter = Control.MOUSE_FILTER_STOP
    overlay.add_child(_root)

    var shade := ColorRect.new()
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    # Chest opens over the paused world, like the new backpack.
    shade.color = Color(0.02, 0.03, 0.07, 0.22)
    shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.add_child(shade)

    var panel := PanelContainer.new()
    panel.position = Vector2(20, 12)
    panel.custom_minimum_size = Vector2(280, 216)
    panel.size = Vector2(280, 216)
    _root.add_child(panel)
    panel.add_theme_stylebox_override("panel", UiTheme.panel_style(0.91, 8.0))

    var stack := VBoxContainer.new()
    stack.add_theme_constant_override("separation", 4)
    panel.add_child(stack)

    _heading = _label(17)
    _heading.add_theme_color_override("font_color", UiTheme.LIGHT_GOLD)
    _heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    stack.add_child(_heading)

    _hint = ControllerHintsScript.new() as Control
    _hint.call("configure", _tr("chest.hint"), _font, true)
    _hint.custom_minimum_size.y = 18
    stack.add_child(_hint)

    _scroll = ScrollContainer.new()
    _scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
    _scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    stack.add_child(_scroll)

    _rows = VBoxContainer.new()
    _rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _rows.add_theme_constant_override("separation", 3)
    _scroll.add_child(_rows)

    _empty = _label(MIN_UI_FONT_SIZE)
    _empty.add_theme_color_override("font_color", UiTheme.MUTED)
    _empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _rows.add_child(_empty)

    _take = _button()
    _take.custom_minimum_size.y = 28
    _take.pressed.connect(_take_selected)
    stack.add_child(_take)


func _label(font_size: int) -> Label:
    var label := Label.new()
    label.add_theme_font_size_override("font_size", maxi(font_size, MIN_UI_FONT_SIZE))
    label.add_theme_color_override("font_color", Color("#edf1f5"))
    if _font != null:
        label.add_theme_font_override("font", _font)
    return label


func _button() -> Button:
    var button := Button.new()
    button.focus_mode = Control.FOCUS_NONE
    button.add_theme_font_size_override("font_size", 14)
    if _font != null:
        button.add_theme_font_override("font", _font)
    UiTheme.apply_button(button)
    return button


func _draw() -> void:
    # Brown clothes, blue-steel armor and reddish weapon chests.
    var edge: Color = Color("#2b211d")
    var body: Color = Color("#77482a")
    var lid: Color = Color("#a86b37")
    match chest_kind:
        "armor":
            edge = Color("#243a4c")
            body = Color("#49687e")
            lid = Color("#779aac")
        "weapon":
            edge = Color("#4d3025")
            body = Color("#9b5940")
            lid = Color("#d6a35c")
    draw_rect(Rect2(-11, -9, 22, 19), edge)
    draw_rect(Rect2(-9, -7, 18, 16), body)
    draw_rect(Rect2(-9, -7, 18, 5), lid)
    draw_line(Vector2(-9, -2), Vector2(9, -2), edge, 1.0)
    draw_rect(Rect2(-2, -4, 4, 8), Color("#e1c06d"))
    draw_rect(Rect2(-1, -1, 2, 2), Color("#52412b"))
