extends CanvasLayer
## Global game menu for Godot 4.7 / PortMaster, opened with Start or R3.
## Select or L3 is reserved for the character editor (future inventory).
## All captions come from localization/strings.json.

const LocaleScript = preload("res://localization/localization.gd")
const FONT_PATH := "res://assets/fonts/CascadiaMono-Regular.ttf"
const NAV_DEBOUNCE_MS := 100
const STICK_PRESS := 0.65
const STICK_RELEASE := 0.42

@onready var _creator: CanvasLayer = get_parent().get_node("CharacterCreator") as CanvasLayer

var _locale: Node
var _font: FontFile
var _opened: bool = false
var _settings_open: bool = false
var _selected_option: int = 0
var _root: Control
var _heading: Label
var _main_panel: VBoxContainer
var _settings_panel: VBoxContainer
var _menu_buttons: Array[Button] = []
var _language_caption: Label
var _language_value: Label
var _back_button: Button
var _held_buttons: Dictionary = {}
var _stick_direction: Dictionary = {}
var _last_navigation_ms: int = -10000

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS

    _locale = get_node_or_null("/root/SkyvalLocale")
    if _locale == null:
        _locale = LocaleScript.new() as Node
        _locale.name = "GameMenuLocale"
        add_child(_locale)

    if ResourceLoader.exists(FONT_PATH):
        _font = load(FONT_PATH) as FontFile
        if _font != null:
            _font = _font.duplicate() as FontFile
            _font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
            _font.hinting = TextServer.HINTING_NORMAL
            _font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO

    _build_interface()
    _locale.connect("language_changed", Callable(self, "_refresh_text"))
    _root.hide()


func is_open() -> bool:
    return _opened


func _tr(key: String) -> String:
    return str(_locale.call("t", key))


func _input(event: InputEvent) -> void:
    if event is InputEventJoypadButton:
        _handle_button(event as InputEventJoypadButton)
    elif event is InputEventJoypadMotion:
        _handle_axis(event as InputEventJoypadMotion)


func _handle_button(event: InputEventJoypadButton) -> void:
    var button_id: String = "%s:%s" % [event.device, event.button_index]
    if not event.pressed:
        _held_buttons.erase(button_id)
        return
    if _held_buttons.has(button_id):
        return
    _held_buttons[button_id] = true

    if not _opened:
        if event.button_index == JOY_BUTTON_START or event.button_index == JOY_BUTTON_RIGHT_STICK:
            _set_open(true)
            get_viewport().set_input_as_handled()
        return

    # This menu owns all joypad input while visible. Select or L3
    # must not open the character creator behind the menu.
    match event.button_index:
        JOY_BUTTON_START, JOY_BUTTON_RIGHT_STICK:
            _set_open(false)
        JOY_BUTTON_B, JOY_BUTTON_X:
            if _settings_open:
                _show_settings(false)
            else:
                _set_open(false)
        JOY_BUTTON_DPAD_UP:
            if not _settings_open:
                _move_selection(-1)
        JOY_BUTTON_DPAD_DOWN:
            if not _settings_open:
                _move_selection(1)
        JOY_BUTTON_DPAD_LEFT:
            if _settings_open:
                _change_language(-1)
        JOY_BUTTON_DPAD_RIGHT:
            if _settings_open:
                _change_language(1)
        JOY_BUTTON_A:
            if _settings_open:
                _change_language(1)
            else:
                _activate_option(_selected_option)
    get_viewport().set_input_as_handled()


func _handle_axis(event: InputEventJoypadMotion) -> void:
    if not _opened:
        return
    if event.axis != JOY_AXIS_LEFT_X and event.axis != JOY_AXIS_LEFT_Y:
        get_viewport().set_input_as_handled()
        return

    var axis_key: String = "%s:%s" % [event.device, event.axis]
    var previous: int = int(_stick_direction.get(axis_key, 0))
    var next_direction: int = 0
    if event.axis_value >= STICK_PRESS:
        next_direction = 1
    elif event.axis_value <= -STICK_PRESS:
        next_direction = -1
    elif absf(event.axis_value) > STICK_RELEASE:
        next_direction = previous
    if next_direction != previous:
        _stick_direction[axis_key] = next_direction
        if next_direction != 0 and _can_navigate():
            if _settings_open and event.axis == JOY_AXIS_LEFT_X:
                _change_language(next_direction)
            elif not _settings_open and event.axis == JOY_AXIS_LEFT_Y:
                _move_selection(next_direction)
    get_viewport().set_input_as_handled()


func _can_navigate() -> bool:
    var now: int = Time.get_ticks_msec()
    if now - _last_navigation_ms < NAV_DEBOUNCE_MS:
        return false
    _last_navigation_ms = now
    return true


func _set_open(next_open: bool) -> void:
    if _opened == next_open:
        return
    if next_open and _creator != null and _creator.has_method("close_for_menu"):
        _creator.call("close_for_menu")

    _opened = next_open
    _settings_open = false
    _selected_option = 0
    _last_navigation_ms = -10000
    _stick_direction.clear()
    _root.visible = next_open
    get_tree().paused = next_open
    if next_open:
        _refresh_text()
    else:
        get_viewport().gui_release_focus()


func _show_settings(show: bool) -> void:
    _settings_open = show
    _refresh_text()


func _move_selection(direction: int) -> void:
    _selected_option = posmod(_selected_option + direction, _menu_buttons.size())
    _update_highlight()


func _activate_option(index: int) -> void:
    if not _opened:
        return
    match index:
        0:
            _show_settings(true)
        1:
            get_tree().quit()


func _change_language(direction: int) -> void:
    if not _opened or not _settings_open:
        return
    var current: String = str(_locale.get("language"))
    var desired: String = "en" if current == "uk" else "uk"
    _locale.call("set_language", desired)


func _build_interface() -> void:
    _root = Control.new()
    _root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _root.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(_root)

    var shade := ColorRect.new()
    shade.color = Color(0.03, 0.08, 0.10, 0.76)
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.add_child(shade)

    var panel := PanelContainer.new()
    panel.position = Vector2(40, 33)
    panel.custom_minimum_size = Vector2(240, 174)
    panel.size = Vector2(240, 174)
    _root.add_child(panel)
    var panel_style := StyleBoxFlat.new()
    panel_style.bg_color = Color("#202c3c")
    panel_style.border_color = Color("#7e95ae")
    panel_style.set_border_width_all(1)
    panel_style.set_corner_radius_all(3)
    panel_style.set_content_margin_all(10)
    panel.add_theme_stylebox_override("panel", panel_style)

    var stack := VBoxContainer.new()
    stack.add_theme_constant_override("separation", 10)
    panel.add_child(stack)

    _heading = _label(19)
    _heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    stack.add_child(_heading)

    var divider := ColorRect.new()
    divider.color = Color("#52657a")
    divider.custom_minimum_size.y = 1
    divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
    stack.add_child(divider)

    _main_panel = VBoxContainer.new()
    _main_panel.add_theme_constant_override("separation", 10)
    stack.add_child(_main_panel)
    for i in range(2):
        var option := _button()
        option.custom_minimum_size.y = 32
        option.pressed.connect(_activate_option.bind(i))
        _main_panel.add_child(option)
        _menu_buttons.append(option)

    _settings_panel = VBoxContainer.new()
    _settings_panel.add_theme_constant_override("separation", 9)
    stack.add_child(_settings_panel)

    _language_caption = _label(15)
    _settings_panel.add_child(_language_caption)

    var language_row := HBoxContainer.new()
    language_row.add_theme_constant_override("separation", 3)
    _settings_panel.add_child(language_row)

    var previous := _button()
    previous.text = "‹"
    previous.custom_minimum_size = Vector2(25, 29)
    previous.pressed.connect(_change_language.bind(-1))
    language_row.add_child(previous)

    _language_value = _label(14)
    _language_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _language_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _language_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _language_value.add_theme_color_override("font_color", Color("#f8d984"))
    language_row.add_child(_language_value)

    var next_button := _button()
    next_button.text = "›"
    next_button.custom_minimum_size = Vector2(25, 29)
    next_button.pressed.connect(_change_language.bind(1))
    language_row.add_child(next_button)

    _back_button = _button()
    _back_button.custom_minimum_size.y = 28
    _back_button.pressed.connect(_show_settings.bind(false))
    _settings_panel.add_child(_back_button)
    _refresh_text()


func _label(font_size: int) -> Label:
    var label := Label.new()
    label.add_theme_font_size_override("font_size", font_size)
    if _font != null:
        label.add_theme_font_override("font", _font)
    label.add_theme_color_override("font_color", Color("#f0f1ed"))
    return label


func _button() -> Button:
    var button := Button.new()
    button.focus_mode = Control.FOCUS_NONE
    button.add_theme_font_size_override("font_size", 16)
    if _font != null:
        button.add_theme_font_override("font", _font)
    button.add_theme_color_override("font_color", Color("#edf1f5"))
    button.add_theme_color_override("font_hover_color", Color.WHITE)
    button.add_theme_color_override("font_pressed_color", Color.WHITE)
    var normal := StyleBoxFlat.new()
    normal.bg_color = Color("#354960")
    normal.border_color = Color("#667f9a")
    normal.set_border_width_all(1)
    normal.set_content_margin_all(3)
    button.add_theme_stylebox_override("normal", normal)
    var hover := normal.duplicate() as StyleBoxFlat
    hover.bg_color = Color("#4c6986")
    button.add_theme_stylebox_override("hover", hover)
    var pressed := normal.duplicate() as StyleBoxFlat
    pressed.bg_color = Color("#6683a1")
    button.add_theme_stylebox_override("pressed", pressed)
    return button


func _update_highlight() -> void:
    for index in range(_menu_buttons.size()):
        var selected: bool = index == _selected_option
        var button: Button = _menu_buttons[index]
        var style := StyleBoxFlat.new()
        style.bg_color = Color("#597a9b") if selected else Color("#354960")
        style.border_color = Color("#e7ca86") if selected else Color("#667f9a")
        style.set_border_width_all(1)
        style.set_content_margin_all(3)
        button.add_theme_stylebox_override("normal", style)
        var hover := style.duplicate() as StyleBoxFlat
        hover.bg_color = Color("#6a8cac") if selected else Color("#4c6986")
        button.add_theme_stylebox_override("hover", hover)
        var pressed := style.duplicate() as StyleBoxFlat
        pressed.bg_color = Color("#7397b4") if selected else Color("#6683a1")
        button.add_theme_stylebox_override("pressed", pressed)
        button.add_theme_color_override("font_color", Color("#fff0c8") if selected else Color("#edf1f5"))


func _refresh_text() -> void:
    if _heading == null:
        return
    _heading.text = _tr("settings.title") if _settings_open else _tr("menu.title")
    _menu_buttons[0].text = _tr("menu.settings")
    _menu_buttons[1].text = _tr("menu.quit")
    _language_caption.text = _tr("settings.language")
    _language_value.text = _tr("settings.language.en") if str(_locale.get("language")) == "en" else _tr("settings.language.uk")
    _back_button.text = _tr("settings.back")
    _main_panel.visible = not _settings_open
    _settings_panel.visible = _settings_open
    _update_highlight()
