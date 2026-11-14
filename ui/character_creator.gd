extends CanvasLayer
## Character creator for the 320x240 logical viewport.
## Text lives exclusively in localization/strings.json.

const PreviewScript = preload("res://ui/character_preview.gd")
const LocaleScript = preload("res://localization/localization.gd")
const APPEARANCE_FIELDS := ["body_type", "skin_variant", "eye_variant", "hair_style", "hair_variant"]
const CLOTHING_FIELDS := [
    "shirt_style", "shirt_variant",
    "pants_style", "pants_variant",
    "footwear_style", "boots_variant",
]
# GPtoKEYB emits keyboard events. A real gamepad may also be visible to
# Godot, so the menu deliberately uses keyboard navigation only.
const NAV_DEBOUNCE_MS := 120
const LEFT_STICK_PRESS := 0.65
const LEFT_STICK_RELEASE := 0.42

@onready var avatar: SkyvalCharacterVisual = get_parent().get_node("Player/CharacterVisual") as SkyvalCharacterVisual

var _opened: bool = false
var _page: int = 0
var _selected_index: int = 0
var _row_labels: Array[Label] = []
var _row_values: Array[Label] = []
var _last_press_by_key: Dictionary = {}
var _held_joy_buttons: Dictionary = {}
var _joy_axis_direction: Dictionary = {}
var _keyboard_emulated_gamepad: bool = false
var _root: Control
var _tab_appearance: Button
var _tab_clothes: Button
var _rows: VBoxContainer
var _preview: Control
var _missing_label: Label
var _value_labels: Dictionary = {}
var _locale: Node

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    # PortMaster's GPtoKEYB already translates console controls to keyboard
    # events. On a laptop, listen to native gamepad buttons directly.
    _keyboard_emulated_gamepad = bool(ProjectSettings.get_setting("skyval/input/keyboard_emulated_gamepad", false))

    # Do not depend on Godot's compile-time singleton registration. Editors
    # opened before a git pull may not have reloaded the [autoload] section.
    _locale = get_node_or_null("/root/SkyvalLocale")
    if _locale == null:
        _locale = LocaleScript.new() as Node
        _locale.name = "CharacterCreatorLocale"
        add_child(_locale)

    _locale.connect("language_changed", Callable(self, "_refresh_text"))
    _build_interface()
    _root.hide()

func _tr(key: String) -> String:
    return str(_locale.call("t", key))

# Capture input before Godot GUI navigation. PortMaster is keyboard-emulated,
# but a USB controller on a desktop uses native JoypadButton/JoypadMotion.
func _input(event: InputEvent) -> void:
    if event is InputEventJoypadButton:
        if not _keyboard_emulated_gamepad:
            _handle_joy_button(event as InputEventJoypadButton)
        return
    if event is InputEventJoypadMotion:
        if not _keyboard_emulated_gamepad:
            _handle_joy_axis(event as InputEventJoypadMotion)
        return
    if not event is InputEventKey:
        return
    if not event.pressed or event.echo:
        return

    var key: Key = event.keycode
    if not _opened:
        if key == KEY_C:
            _set_open(true)
            get_viewport().set_input_as_handled()
        return

    if key != KEY_C and key != KEY_ESCAPE and key != KEY_UP and key != KEY_DOWN and key != KEY_LEFT and key != KEY_RIGHT and key != KEY_ENTER and key != KEY_KP_ENTER and key != KEY_SPACE and key != KEY_Q and key != KEY_E and key != KEY_TAB and key != KEY_I and key != KEY_J and key != KEY_K and key != KEY_L:
        return

    # Even a rejected bounce must not fall through to Godot UI navigation.
    get_viewport().set_input_as_handled()
    if key == KEY_C or key == KEY_ESCAPE:
        _set_open(false)
        return

    var now: int = Time.get_ticks_msec()
    var last: int = int(_last_press_by_key.get(key, -10000))
    if now - last < NAV_DEBOUNCE_MS:
        return
    _last_press_by_key[key] = now

    match key:
        KEY_UP:
            _move_selection(-1)
        KEY_DOWN:
            _move_selection(1)
        KEY_LEFT:
            _adjust_selected(-1)
        KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
            _adjust_selected(1)
        KEY_Q:
            _set_page(0)
        KEY_E, KEY_TAB:
            _set_page(1 if key == KEY_E else 1 - _page)
        KEY_I:
            _preview.call("show_direction", Vector2.UP)
        KEY_J:
            _preview.call("show_direction", Vector2.LEFT)
        KEY_K:
            _preview.call("show_direction", Vector2.DOWN)
        KEY_L:
            _preview.call("show_direction", Vector2.RIGHT)

# Native gamepad buttons, using Godot's SDL-standard button indices.
# A press is accepted only once until its matching release arrives.
func _handle_joy_button(event: InputEventJoypadButton) -> void:
    var button_id: String = "%s:%s" % [event.device, event.button_index]
    if not event.pressed:
        _held_joy_buttons.erase(button_id)
        return
    if _held_joy_buttons.has(button_id):
        return
    _held_joy_buttons[button_id] = true

    if not _opened:
        if event.button_index == JOY_BUTTON_START or event.button_index == JOY_BUTTON_X:
            _set_open(true)
            get_viewport().set_input_as_handled()
        return

    match event.button_index:
        JOY_BUTTON_START, JOY_BUTTON_X, JOY_BUTTON_B:
            _set_open(false)
        JOY_BUTTON_A:
            _adjust_selected(1)
        JOY_BUTTON_LEFT_SHOULDER:
            _set_page(0)
        JOY_BUTTON_RIGHT_SHOULDER:
            _set_page(1)
        JOY_BUTTON_DPAD_UP:
            _move_selection(-1)
        JOY_BUTTON_DPAD_DOWN:
            _move_selection(1)
        JOY_BUTTON_DPAD_LEFT:
            _adjust_selected(-1)
        JOY_BUTTON_DPAD_RIGHT:
            _adjust_selected(1)
        _:
            return
    get_viewport().set_input_as_handled()

# Optional left-stick menu navigation: one action per tilt, not every frame.
# The lower release threshold prevents drift from triggering repeated actions.
func _handle_joy_axis(event: InputEventJoypadMotion) -> void:
    if not _opened:
        return
    if event.axis == JOY_AXIS_RIGHT_X or event.axis == JOY_AXIS_RIGHT_Y:
        # View-only rotation. Never change the paused in-world player.
        var look: Vector2 = Vector2(
            Input.get_joy_axis(event.device, JOY_AXIS_RIGHT_X),
            Input.get_joy_axis(event.device, JOY_AXIS_RIGHT_Y)
        )
        _preview.call("show_direction", look)
        get_viewport().set_input_as_handled()
        return
    if event.axis != JOY_AXIS_LEFT_X and event.axis != JOY_AXIS_LEFT_Y:
        return

    var axis_id: String = "%s:%s" % [event.device, event.axis]
    var previous: int = int(_joy_axis_direction.get(axis_id, 0))
    var next_direction: int = 0
    if event.axis_value >= LEFT_STICK_PRESS:
        next_direction = 1
    elif event.axis_value <= -LEFT_STICK_PRESS:
        next_direction = -1
    elif absf(event.axis_value) > LEFT_STICK_RELEASE:
        next_direction = previous

    if next_direction == previous:
        return
    _joy_axis_direction[axis_id] = next_direction
    if next_direction == 0:
        return

    if event.axis == JOY_AXIS_LEFT_Y:
        _move_selection(next_direction)
    else:
        _adjust_selected(next_direction)
    get_viewport().set_input_as_handled()

func _move_selection(amount: int) -> void:
    var fields: Array = APPEARANCE_FIELDS if _page == 0 else CLOTHING_FIELDS
    if fields.is_empty():
        return
    _selected_index = posmod(_selected_index + amount, fields.size())
    _update_row_highlight()

func _adjust_selected(direction: int) -> void:
    var fields: Array = APPEARANCE_FIELDS if _page == 0 else CLOTHING_FIELDS
    if _selected_index >= 0 and _selected_index < fields.size():
        _adjust(str(fields[_selected_index]), direction, _selected_index)

func _update_row_highlight() -> void:
    for index in range(_row_labels.size()):
        var selected: bool = index == _selected_index
        var label: Label = _row_labels[index]
        if is_instance_valid(label):
            label.add_theme_color_override("font_color", Color("#f8d984") if selected else Color("#f0f1ed"))
        if index < _row_values.size() and is_instance_valid(_row_values[index]):
            _row_values[index].add_theme_color_override("font_color", Color("#f8d984") if selected else Color("#f0f1ed"))

func _set_open(next_open: bool) -> void:
    _opened = next_open
    _root.visible = next_open
    get_tree().paused = next_open
    if next_open:
        _last_press_by_key.clear()
        # A stick can still be held when the creator reopens; reset the
        # hysteresis latch so the first new tilt is recognized.
        _joy_axis_direction.clear()
        _refresh_text()
        _update_row_highlight()
    else:
        get_viewport().gui_release_focus()

func _build_interface() -> void:
    _root = Control.new()
    _root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _root.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(_root)

    var shade := ColorRect.new()
    shade.color = Color(0.03, 0.08, 0.10, 0.76)
    shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _root.add_child(shade)

    var panel := PanelContainer.new()
    panel.position = Vector2(5, 7)
    panel.custom_minimum_size = Vector2(204, 224)
    panel.size = Vector2(204, 224)
    _root.add_child(panel)
    var panel_style := StyleBoxFlat.new()
    panel_style.bg_color = Color("#202c3c")
    panel_style.border_color = Color("#7e95ae")
    panel_style.set_border_width_all(1)
    panel_style.set_corner_radius_all(3)
    panel_style.set_content_margin_all(5)
    panel.add_theme_stylebox_override("panel", panel_style)

    var stack := VBoxContainer.new()
    stack.add_theme_constant_override("separation", 3)
    panel.add_child(stack)

    # The tabs are now the top row. Controller shortcuts replace the
    # redundant title / language / close header on a 320x240 screen.
    var tabs := HBoxContainer.new()
    tabs.add_theme_constant_override("separation", 2)
    stack.add_child(tabs)
    _tab_appearance = _button()
    _tab_appearance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _tab_appearance.custom_minimum_size.y = 20
    tabs.add_child(_tab_appearance)
    _tab_appearance.pressed.connect(_set_page.bind(0))

    _tab_clothes = _button()
    _tab_clothes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _tab_clothes.custom_minimum_size.y = 20
    tabs.add_child(_tab_clothes)
    _tab_clothes.pressed.connect(_set_page.bind(1))

    _rows = VBoxContainer.new()
    _rows.add_theme_constant_override("separation", 2)
    _rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
    stack.add_child(_rows)

    # Use the full right column; the portrait itself is drawn at 3×.
    _preview = PreviewScript.new() as Control
    _preview.position = Vector2(212, 8)
    _preview.size = Vector2(103, 224)
    _root.add_child(_preview)

    _missing_label = _label(9)
    _missing_label.position = Vector2(214, 94)
    _missing_label.size = Vector2(99, 46)
    _missing_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _missing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _root.add_child(_missing_label)

    _refresh_text()

func _button() -> Button:
    var button := Button.new()
    # Controller/keyboard selection is owned by _input(), not Godot's GUI
    # focus traversal. Mouse/touch button clicks still work normally.
    button.focus_mode = Control.FOCUS_NONE
    button.add_theme_font_size_override("font_size", 10)
    button.add_theme_color_override("font_color", Color("#edf1f5"))
    button.add_theme_color_override("font_hover_color", Color.WHITE)
    button.add_theme_color_override("font_pressed_color", Color.WHITE)
    button.add_theme_color_override("font_focus_color", Color.WHITE)
    var normal := StyleBoxFlat.new()
    normal.bg_color = Color("#354960")
    normal.border_color = Color("#667f9a")
    normal.set_border_width_all(1)
    normal.set_content_margin_all(2)
    button.add_theme_stylebox_override("normal", normal)
    var hover := normal.duplicate() as StyleBoxFlat
    hover.bg_color = Color("#4c6986")
    button.add_theme_stylebox_override("hover", hover)
    var pressed := normal.duplicate() as StyleBoxFlat
    pressed.bg_color = Color("#6683a1")
    button.add_theme_stylebox_override("pressed", pressed)
    return button

func _label(font_size: int) -> Label:
    var label := Label.new()
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", Color("#f0f1ed"))
    label.clip_text = true
    return label

func _set_page(next_page: int) -> void:
    _page = next_page
    _selected_index = 0
    _refresh_text()

func _refresh_text() -> void:
    if _tab_appearance == null:
        return
    _tab_appearance.text = _tr("ui.appearance")
    _tab_clothes.text = _tr("ui.clothes")
    _missing_label.text = _tr("ui.missing_lpc")
    _missing_label.visible = not avatar.has_lpc_character()
    _preview.set("character", avatar.get_lpc_character())
    _preview.queue_redraw()
    _rebuild_rows()

func _rebuild_rows() -> void:
    _value_labels.clear()
    _row_labels.clear()
    _row_values.clear()
    for child in _rows.get_children():
        _rows.remove_child(child)
        child.queue_free()

    var fields: Array = APPEARANCE_FIELDS if _page == 0 else CLOTHING_FIELDS
    for property_key in fields:
        var index: int = _row_labels.size()
        var key: String = str(property_key)
        var row := HBoxContainer.new()
        row.custom_minimum_size.y = 22
        row.add_theme_constant_override("separation", 2)
        _rows.add_child(row)

        var name_label := _label(9)
        name_label.text = _tr("field." + key)
        name_label.custom_minimum_size.x = 78
        row.add_child(name_label)
        _row_labels.append(name_label)

        var previous := _button()
        previous.text = _tr("ui.previous")
        previous.custom_minimum_size = Vector2(19, 20)
        previous.disabled = not avatar.has_lpc_character()
        row.add_child(previous)
        previous.pressed.connect(_adjust.bind(key, -1, index))

        var value_label := _label(9)
        value_label.custom_minimum_size.x = 72
        value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        value_label.text = _localized_value(key)
        row.add_child(value_label)
        _value_labels[key] = value_label
        _row_values.append(value_label)

        var following := _button()
        following.text = _tr("ui.next")
        following.custom_minimum_size = Vector2(19, 20)
        following.disabled = not avatar.has_lpc_character()
        row.add_child(following)
        following.pressed.connect(_adjust.bind(key, 1, index))

    _update_row_highlight()

func _localized_value(key: String) -> String:
    if not avatar.has_lpc_character():
        return _tr("ui.missing_lpc")
    var value: String = avatar.get_lpc_option(key)
    if value == "none":
        return _tr("value.clothing.none")
    if key == "body_type" or key.ends_with("_style"):
        return _tr("value." + key + "." + value.replace("/", "_"))
    return _tr("color." + value)

func _refresh_options() -> void:
    # Refresh live labels rather than rebuilding rows, preserving button focus.
    for option_key in _value_labels.keys():
        var field_label: Label = _value_labels[option_key] as Label
        if is_instance_valid(field_label):
            field_label.text = _localized_value(str(option_key))
    _preview.queue_redraw()

func _adjust(key: String, direction: int, index: int = -1) -> void:
    if index >= 0:
        _selected_index = index
        _update_row_highlight()
    if avatar.change_lpc_option(key, direction):
        _refresh_options()
