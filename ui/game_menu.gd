extends CanvasLayer
## Global game menu for Godot 4.7 / PortMaster, opened with Start or R3.
## Select or L3 is reserved for the character editor (future inventory).
## All captions come from localization/strings.json.

const LocaleScript = preload("res://localization/localization.gd")
const FONT_PATH := "res://assets/fonts/CascadiaMono-Regular.ttf"
const NAV_DEBOUNCE_MS := 100
const STICK_PRESS := 0.65
const STICK_RELEASE := 0.42
const SAVE_FILE := "user://skyval_save_v1.json"
const MAIN_OPTIONS := ["menu.continue", "menu.new_game", "menu.settings", "menu.quit"]

@onready var _creator: CanvasLayer = get_parent().get_node("CharacterCreator") as CanvasLayer

var _locale: Node
var _font: FontFile
var _opened: bool = false
var _settings_open: bool = false
var _confirm_new_game: bool = false
var _session_started: bool = false
var _creation_in_progress: bool = false
var _selected_option: int = 0
var _root: Control
var _heading: Label
var _main_panel: VBoxContainer
var _settings_panel: VBoxContainer
var _confirm_panel: VBoxContainer
var _confirm_message: Label
var _confirm_hint: Label
var _menu_buttons: Array[Button] = []
var _language_caption: Label
var _language_value: Label
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
    print("Skyval GameMenu: READY (Start=", JOY_BUTTON_START, ", R3=", JOY_BUTTON_RIGHT_STICK, ")")
    # A fresh launch always shows a paused main menu before gameplay.
    _set_open(true)


func is_open() -> bool:
    return _opened


func has_started_session() -> bool:
    return _session_started and not _creation_in_progress


func _tr(key: String) -> String:
    return str(_locale.call("t", key))


func _input(event: InputEvent) -> void:
    if event is InputEventJoypadButton:
        var joy_event: InputEventJoypadButton = event as InputEventJoypadButton
        if joy_event.pressed:
            print("Skyval GameMenu: BUTTON device=", joy_event.device, " index=", joy_event.button_index)
        _handle_button(joy_event)
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
        if not _creation_in_progress and (event.button_index == JOY_BUTTON_START or event.button_index == JOY_BUTTON_RIGHT_STICK):
            _set_open(true)
            get_viewport().set_input_as_handled()
        return

    # This menu owns all joypad input while visible. Select or L3
    # must not open the character creator behind the menu.
    match event.button_index:
        JOY_BUTTON_START, JOY_BUTTON_RIGHT_STICK:
            if _session_started:
                _set_open(false)
        JOY_BUTTON_B:
            if _confirm_new_game:
                _confirm_new_game = false
                _refresh_text()
            elif _settings_open:
                _show_settings(false)
            elif _session_started:
                _set_open(false)
        JOY_BUTTON_DPAD_UP:
            if not _settings_open and not _confirm_new_game:
                _move_selection(-1)
        JOY_BUTTON_DPAD_DOWN:
            if not _settings_open and not _confirm_new_game:
                _move_selection(1)
        JOY_BUTTON_DPAD_LEFT:
            if _settings_open:
                _change_language(-1)
        JOY_BUTTON_DPAD_RIGHT:
            if _settings_open:
                _change_language(1)
        JOY_BUTTON_A:
            if _confirm_new_game:
                _start_new_game()
            elif _settings_open:
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
    if _opened == next_open or (not next_open and not _session_started and not _creation_in_progress):
        return
    if next_open and _session_started and not _creation_in_progress:
        _save_current_game() # Never overwrite a save with an unfinished character.
    _opened = next_open
    if next_open:
        # Take pause ownership before closing another UI layer.
        _set_ui_pause(true)
        if _creator != null and _creator.has_method("close_for_menu"):
            _creator.call("close_for_menu")

    print("Skyval GameMenu: OPEN=", _opened)
    _settings_open = false
    _confirm_new_game = false
    _selected_option = 0 if _session_started or _has_valid_save() else 1
    _last_navigation_ms = -10000
    _stick_direction.clear()
    _root.visible = next_open
    if next_open:
        _refresh_text()
    else:
        _set_ui_pause(false)
        get_viewport().gui_release_focus()


func _set_ui_pause(is_open: bool) -> void:
    var pause_manager: Node = get_node_or_null("/root/SkyvalUiPause")
    if pause_manager != null:
        pause_manager.call("set_open", self, is_open)
    else:
        # Fallback for an editor that has not reloaded project.godot yet.
        get_tree().paused = is_open


func _show_settings(show: bool) -> void:
    _settings_open = show
    _refresh_text()


func _move_selection(direction: int) -> void:
    var next_index: int = _selected_option
    for step in range(_menu_buttons.size()):
        next_index = posmod(next_index + direction, _menu_buttons.size())
        if not _menu_buttons[next_index].disabled:
            _selected_option = next_index
            break
    _update_highlight()


func _activate_option(index: int) -> void:
    if not _opened or index < 0 or index >= _menu_buttons.size():
        return
    if _menu_buttons[index].disabled:
        return
    match index:
        0: # Continue: load on launch, resume when already in the game.
            _continue_game()
        1: # New game: ask before replacing an existing save.
            if _has_valid_save():
                _confirm_new_game = true
                _refresh_text()
            else:
                _start_new_game()
        2:
            _show_settings(true)
        3:
            if _session_started:
                _save_current_game()
            get_tree().quit()


func _get_player() -> CharacterBody2D:
    var world: Node = get_tree().current_scene
    if world == null:
        return null
    return world.get_node_or_null("Player") as CharacterBody2D


func _read_save() -> Dictionary:
    if not FileAccess.file_exists(SAVE_FILE):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_FILE))
    if not parsed is Dictionary:
        return {}
    var data: Dictionary = parsed
    if data.get("version", -1) != 1:
        return {}
    var position_data: Variant = data.get("player_position")
    if not position_data is Array or position_data.size() != 2:
        return {}
    for coord in position_data:
        if typeof(coord) != TYPE_FLOAT and typeof(coord) != TYPE_INT:
            return {}
    return data


func _has_valid_save() -> bool:
    return not _read_save().is_empty()


func _save_current_game() -> bool:
    var player: CharacterBody2D = _get_player()
    if player == null:
        return false
    var data: Dictionary = {
        "version": 1,
        "player_position": [player.global_position.x, player.global_position.y],
        "appearance": {},
    }
    var avatar: Node = player.get_node_or_null("CharacterVisual")
    if avatar != null and avatar.has_method("get_save_state"):
        data["appearance"] = avatar.call("get_save_state")
    var file: FileAccess = FileAccess.open(SAVE_FILE, FileAccess.WRITE)
    if file == null:
        push_warning("Skyval: could not write save file: %s" % error_string(FileAccess.get_open_error()))
        return false
    file.store_string(JSON.stringify(data))
    file.flush()
    file.close()
    return true


func _load_saved_game() -> bool:
    var data: Dictionary = _read_save()
    var player: CharacterBody2D = _get_player()
    if data.is_empty() or player == null:
        return false
    var pos: Array = data["player_position"]
    var bounds: Rect2 = player.get("world_bounds")
    var restored: Vector2 = Vector2(float(pos[0]), float(pos[1]))
    player.global_position = restored.clamp(bounds.position + Vector2(8.0, 14.0), bounds.end - Vector2(8.0, 14.0))
    player.velocity = Vector2.ZERO
    var avatar: Node = player.get_node_or_null("CharacterVisual")
    var appearance_data: Variant = data.get("appearance", {})
    if avatar != null and avatar.has_method("apply_save_state") and appearance_data is Dictionary:
        avatar.call("apply_save_state", appearance_data)
    return true


func _continue_game() -> void:
    if not _session_started:
        if not _load_saved_game():
            push_warning("Skyval: saved game is missing or invalid.")
            _refresh_text()
            return
        _session_started = true
    _set_open(false)


func _start_new_game() -> void:
    # Character appearance must be accepted before overwriting the old save.
    if _creation_in_progress:
        return
    var player: CharacterBody2D = _get_player()
    var editor: Node = get_parent().get_node_or_null("AppearanceEditor")
    if player == null or editor == null or not editor.has_method("begin_creation"):
        push_error("Skyval: AppearanceEditor or Player missing; cannot start a new game.")
        return

    var on_confirmed: Callable = Callable(self, "_on_appearance_confirmed")
    var on_cancelled: Callable = Callable(self, "_on_appearance_cancelled")
    if not editor.is_connected("confirmed", on_confirmed):
        editor.connect("confirmed", on_confirmed)
    if not editor.is_connected("cancelled", on_cancelled):
        editor.connect("cancelled", on_cancelled)

    _creation_in_progress = true
    if player.has_method("reset_for_new_game"):
        player.call("reset_for_new_game")
    # Claim the modal pause before releasing GameMenu: no active gameplay frame.
    editor.call("begin_creation")
    _set_open(false)


func _on_appearance_confirmed() -> void:
    if not _creation_in_progress:
        return
    _session_started = true
    _creation_in_progress = false
    _save_current_game()


func _on_appearance_cancelled() -> void:
    if not _creation_in_progress:
        return
    # The last checkpoint remains untouched, including wardrobe and position.
    _load_saved_game()
    # Take menu pause ownership while the editor is still open.
    _set_open(true)
    _creation_in_progress = false


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
    panel.position = Vector2(34, 15)
    panel.custom_minimum_size = Vector2(252, 210)
    panel.size = Vector2(252, 210)
    _root.add_child(panel)
    var panel_style := StyleBoxFlat.new()
    panel_style.bg_color = Color("#202c3c")
    panel_style.border_color = Color("#7e95ae")
    panel_style.set_border_width_all(1)
    panel_style.set_corner_radius_all(3)
    panel_style.set_content_margin_all(7)
    panel.add_theme_stylebox_override("panel", panel_style)

    var stack := VBoxContainer.new()
    stack.add_theme_constant_override("separation", 6)
    panel.add_child(stack)

    _heading = _label(17)
    _heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    stack.add_child(_heading)

    var divider := ColorRect.new()
    divider.color = Color("#52657a")
    divider.custom_minimum_size.y = 1
    divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
    stack.add_child(divider)

    _main_panel = VBoxContainer.new()
    _main_panel.add_theme_constant_override("separation", 6)
    stack.add_child(_main_panel)
    for i in range(MAIN_OPTIONS.size()):
        var option := _button()
        option.custom_minimum_size.y = 30
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

    # Confirmation is kept inside the same panel, with no Back buttons.
    _confirm_panel = VBoxContainer.new()
    _confirm_panel.add_theme_constant_override("separation", 12)
    stack.add_child(_confirm_panel)

    _confirm_message = _label(15)
    _confirm_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _confirm_message.custom_minimum_size.y = 65
    _confirm_panel.add_child(_confirm_message)

    _confirm_hint = _label(12)
    _confirm_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _confirm_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _confirm_panel.add_child(_confirm_hint)

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
        var button: Button = _menu_buttons[index]
        var unavailable: bool = button.disabled
        var selected: bool = index == _selected_option and not unavailable
        var style := StyleBoxFlat.new()
        style.bg_color = Color("#293748") if unavailable else (Color("#597a9b") if selected else Color("#354960"))
        style.border_color = Color("#52657a") if unavailable else (Color("#e7ca86") if selected else Color("#667f9a"))
        style.set_border_width_all(1)
        style.set_content_margin_all(3)
        button.add_theme_stylebox_override("normal", style)
        button.add_theme_stylebox_override("disabled", style)
        button.add_theme_color_override("font_disabled_color", Color("#8493a5"))
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
    _heading.text = _tr("menu.new_game") if _confirm_new_game else (_tr("settings.title") if _settings_open else _tr("menu.title"))
    for index in range(MAIN_OPTIONS.size()):
        _menu_buttons[index].text = _tr(str(MAIN_OPTIONS[index]))
    _menu_buttons[0].disabled = not _session_started and not _has_valid_save()
    if _menu_buttons[_selected_option].disabled:
        _selected_option = 1
    _language_caption.text = _tr("settings.language")
    _language_value.text = _tr("settings.language.en") if str(_locale.get("language")) == "en" else _tr("settings.language.uk")
    _confirm_message.text = _tr("menu.replace_save")
    _confirm_hint.text = _tr("menu.confirm_hint")
    _main_panel.visible = not _settings_open and not _confirm_new_game
    _settings_panel.visible = _settings_open
    _confirm_panel.visible = _confirm_new_game
    _update_highlight()
