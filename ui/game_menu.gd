extends CanvasLayer
## Global game menu for Godot 4.7 / PortMaster, opened with Start or R3.
## Select or L3 is reserved for the character editor (future inventory).
## All captions come from localization/strings.json.

const LocaleScript = preload("res://localization/localization.gd")
const SaveStoreScript = preload("res://game/save_store.gd")
const NameEntryScript = preload("res://ui/name_entry.gd")
const FONT_PATH := "res://assets/fonts/CascadiaMono-Regular.ttf"
const MIN_UI_FONT_SIZE := 14
const ACTIVE_HIGHLIGHT := Color("#e7ca86")
const NAV_DEBOUNCE_MS := 100
const STICK_PRESS := 0.65
const STICK_RELEASE := 0.42
const VISIBLE_PROFILES := 4
const MAIN_OPTIONS := ["menu.continue", "menu.select_character", "menu.new_game", "menu.settings", "menu.quit"]
const GAME_OPTIONS := ["game.quick_save", "game.quick_load", "game.save", "game.load", "menu.settings", "game.main_menu"]

@onready var _creator: CanvasLayer = get_parent().get_node("CharacterCreator") as CanvasLayer

var _locale: Node
var _font: FontFile
var _opened: bool = false
var _main_mode: bool = true
var _settings_open: bool = false
var _list_mode: String = "" # characters or load
var _confirm_action: String = "" # load, delete, main
var _pending_save_path: String = ""
var _session_started: bool = false
var _creation_in_progress: bool = false
var _selected_option: int = 0
var _selected_list: int = 0
var _listed_items: Array[Dictionary] = []
var _visible_options: Array[String] = []
var _status_message: String = ""
var _profile_data: Dictionary = {}
var _active_save_path: String = ""
var _save_store: RefCounted
var _name_entry: CanvasLayer
var _root: Control
var _heading: Label
var _main_panel: VBoxContainer
var _settings_panel: VBoxContainer
var _continue_panel: VBoxContainer
var _profile_list: VBoxContainer
var _profile_hint: Label
var _confirm_panel: VBoxContainer
var _confirm_message: Label
var _confirm_hint: Label
var _menu_buttons: Array[Button] = []
var _language_caption: Label
var _language_value: Label
var _held_buttons: Dictionary = {}
var _stick_direction: Dictionary = {}
var _last_navigation_ms: int = -10000
var _ignore_presses_before_ms: int = 0

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

    _save_store = SaveStoreScript.new()
    _name_entry = NameEntryScript.new() as CanvasLayer
    _name_entry.name = "CharacterNameEntry"
    _name_entry.layer = 5
    # Never add a sibling to the world from GameMenu._ready(): the
    # world may still be setting up its children, so add_child() fails
    # and leaves NameEntry detached (get_tree() == null on opening).
    # Attach the layer to GameMenu itself, which is ready to add children.
    add_child(_name_entry)
    if not _name_entry.is_inside_tree():
        push_error("Skyval: CharacterNameEntry was not added to SceneTree.")
    _name_entry.call("ensure_initialized")
    _name_entry.connect("accepted", Callable(self, "_on_name_confirmed"))
    _name_entry.connect("cancelled", Callable(self, "_on_name_cancelled"))
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


func save_checkpoint() -> bool:
    if not has_started_session():
        return false
    return _save_current_game()


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
    var key: String = "%s:%s" % [event.device, event.button_index]
    if not event.pressed:
        _held_buttons.erase(key)
        return
    if _held_buttons.has(key):
        return
    _held_buttons[key] = true
    if _opened and Time.get_ticks_msec() < _ignore_presses_before_ms:
        get_viewport().set_input_as_handled()
        return
    if not _opened:
        if _session_started and not _creation_in_progress and event.button_index in [JOY_BUTTON_START, JOY_BUTTON_RIGHT_STICK]:
            _set_open(true)
            get_viewport().set_input_as_handled()
        return

    if not _confirm_action.is_empty():
        if event.button_index == JOY_BUTTON_A:
            _accept_confirmation()
        elif event.button_index == JOY_BUTTON_B:
            _dismiss_confirmation()
    elif not _list_mode.is_empty():
        match event.button_index:
            JOY_BUTTON_B:
                _list_mode = ""
                _refresh_text()
            JOY_BUTTON_DPAD_UP:
                _move_list(-1)
            JOY_BUTTON_DPAD_DOWN:
                _move_list(1)
            JOY_BUTTON_A:
                _choose_list_item()
            JOY_BUTTON_X:
                if _list_mode == "characters" and not _listed_items.is_empty():
                    _ask_confirmation("delete")
    else:
        match event.button_index:
            JOY_BUTTON_START, JOY_BUTTON_RIGHT_STICK:
                if _session_started and not _settings_open:
                    _set_open(false)
            JOY_BUTTON_B:
                if _settings_open:
                    _show_settings(false)
                elif _session_started:
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
    if event.axis not in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
        get_viewport().set_input_as_handled()
        return
    var key: String = "%s:%s" % [event.device, event.axis]
    var previous: int = int(_stick_direction.get(key, 0))
    var direction: int = 0
    if event.axis_value >= STICK_PRESS:
        direction = 1
    elif event.axis_value <= -STICK_PRESS:
        direction = -1
    elif absf(event.axis_value) > STICK_RELEASE:
        direction = previous
    if direction != previous:
        _stick_direction[key] = direction
        if direction != 0 and _can_navigate() and _confirm_action.is_empty():
            if not _list_mode.is_empty() and event.axis == JOY_AXIS_LEFT_Y:
                _move_list(direction)
            elif _settings_open and event.axis == JOY_AXIS_LEFT_X:
                _change_language(direction)
            elif _list_mode.is_empty() and not _settings_open and event.axis == JOY_AXIS_LEFT_Y:
                _move_selection(direction)
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
    _opened = next_open
    if next_open:
        _ignore_presses_before_ms = Time.get_ticks_msec() + 150
        _set_ui_pause(true)
        if _creator != null and _creator.has_method("close_for_menu"):
            _creator.call("close_for_menu")
        for chest_name in ["TestChest", "ArmorChest"]:
            var chest: Node = get_parent().get_node_or_null(chest_name)
            if chest != null and bool(chest.call("is_open")):
                chest.call("close_for_menu")
        var appearance: Node = get_parent().get_node_or_null("AppearanceEditor")
        if appearance != null and not _creation_in_progress and bool(appearance.call("is_open")):
            appearance.call("close_for_menu")
        if _session_started and not _creation_in_progress:
            _save_current_game()
        _main_mode = not _session_started
        _status_message = ""
    print("Skyval GameMenu: OPEN=", _opened)
    _settings_open = false
    _list_mode = ""
    _confirm_action = ""
    _pending_save_path = ""
    _selected_option = 0
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
    # Respect first and last options; skip disabled entries without wrapping.
    var next_index: int = _selected_option + direction
    while next_index >= 0 and next_index < _menu_buttons.size():
        if not _menu_buttons[next_index].disabled:
            _selected_option = next_index
            _update_highlight()
            return
        next_index += direction


func _activate_option(index: int) -> void:
    if not _opened or index < 0 or index >= _menu_buttons.size() or _menu_buttons[index].disabled:
        return
    match index:
        0:
            _profiles = _save_store.call("list_profiles")
            if not _profiles.is_empty():
                _selected_profile = 0
                _continue_open = true
                _refresh_text()
        1:
            _start_new_game()
        2:
            _show_settings(true)
        3:
            if _session_started:
                _save_current_game()
            get_tree().quit()


func _move_profile(direction: int) -> void:
    var next_index: int = _selected_profile + direction
    if next_index >= 0 and next_index < _profiles.size():
        _selected_profile = next_index
        _draw_profiles()


func _select_profile() -> void:
    if _selected_profile < 0 or _selected_profile >= _profiles.size():
        return
    if _load_profile(str(_profiles[_selected_profile].get("path", "")), true):
        _continue_open = false
        _set_open(false)
    else:
        _profiles = _save_store.call("list_profiles")
        _selected_profile = mini(_selected_profile, maxi(0, _profiles.size() - 1))
        _continue_open = not _profiles.is_empty()
        _refresh_text()


func _delete_selected_profile() -> void:
    _confirm_delete = false
    if _selected_profile < 0 or _selected_profile >= _profiles.size():
        _refresh_text()
        return
    var path: String = str(_profiles[_selected_profile].get("path", ""))
    if not bool(_save_store.call("delete_profile", path)):
        push_warning("Skyval: failed to delete profile: %s" % path)
        _refresh_text()
        return
    if path == _active_save_path:
        _active_save_path = ""
        _profile_data.clear()
        _session_started = false
    _profiles = _save_store.call("list_profiles")
    _selected_profile = mini(_selected_profile, maxi(0, _profiles.size() - 1))
    if _profiles.is_empty():
        _continue_open = false
        _selected_option = 1
    _refresh_text()


func _draw_profiles() -> void:
    if _profile_list == null:
        return
    for child in _profile_list.get_children():
        _profile_list.remove_child(child)
        child.queue_free()
    if _profiles.is_empty():
        var empty_label := _label(MIN_UI_FONT_SIZE)
        empty_label.text = _tr("save.none")
        _profile_list.add_child(empty_label)
        return
    var first: int = maxi(0, _selected_profile - VISIBLE_PROFILES + 1)
    var last: int = mini(_profiles.size(), first + VISIBLE_PROFILES)
    for i in range(first, last):
        var button := _button()
        button.add_theme_font_size_override("font_size", MIN_UI_FONT_SIZE)
        button.custom_minimum_size.y = 26
        button.clip_text = true
        button.text = str(_profiles[i].get("character_name", ""))
        button.pressed.connect(_pick_profile.bind(i))
        var selected: bool = i == _selected_profile
        var style := StyleBoxFlat.new()
        style.bg_color = Color("#597a9b") if selected else Color("#354960")
        style.border_color = ACTIVE_HIGHLIGHT if selected else Color("#667f9a")
        style.set_border_width_all(1)
        style.set_content_margin_all(3)
        button.add_theme_stylebox_override("normal", style)
        button.add_theme_stylebox_override("hover", style)
        var text_color: Color = ACTIVE_HIGHLIGHT if selected else Color("#edf1f5")
        button.add_theme_color_override("font_color", text_color)
        button.add_theme_color_override("font_hover_color", text_color)
        _profile_list.add_child(button)
    _profile_hint.text = "%d/%d   %s" % [_selected_profile + 1, _profiles.size(), _tr("save.list_hint")]


func _pick_profile(index: int) -> void:
    _selected_profile = index
    _select_profile()

func _get_player() -> CharacterBody2D:
    var world: Node = get_tree().current_scene
    if world == null:
        return null
    return world.get_node_or_null("Player") as CharacterBody2D


func _has_valid_save() -> bool:
    var available: Array[Dictionary] = _save_store.call("list_profiles")
    return not available.is_empty()


func _save_current_game() -> bool:
    if _active_save_path.is_empty():
        return false
    var player: CharacterBody2D = _get_player()
    if player == null:
        return false
    var data: Dictionary = _profile_data.duplicate(true)
    data["version"] = 2
    data["player_position"] = [player.global_position.x, player.global_position.y]
    data["appearance"] = {}
    var avatar: Node = player.get_node_or_null("CharacterVisual")
    if avatar != null and avatar.has_method("get_save_state"):
        data["appearance"] = avatar.call("get_save_state")
    var inventory: Node = get_node_or_null("/root/SkyvalInventory")
    if inventory != null:
        data["inventory"] = inventory.call("get_save_state")
    if not bool(_save_store.call("write_profile", _active_save_path, data)):
        return false
    _profile_data = data
    return true


func _load_profile(path: String, touch_launch: bool = true) -> bool:
    var data: Dictionary = _save_store.call("read_profile", path)
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
    var inventory: Node = get_node_or_null("/root/SkyvalInventory")
    if inventory != null:
        inventory.call("load_save_state", data.get("inventory", null), avatar)
    _active_save_path = path
    _profile_data = data
    _session_started = true
    if touch_launch:
        _profile_data["last_played"] = int(Time.get_unix_time_from_system() * 1000.0)
        _save_current_game()
    return true


func _start_new_game() -> void:
    if _creation_in_progress:
        return
    var player: CharacterBody2D = _get_player()
    var editor: Node = get_parent().get_node_or_null("AppearanceEditor")
    if player == null or editor == null or not editor.has_method("begin_creation"):
        push_error("Skyval: AppearanceEditor or Player missing; cannot create a character.")
        return
    var on_confirmed: Callable = Callable(self, "_on_appearance_confirmed")
    var on_cancelled: Callable = Callable(self, "_on_appearance_cancelled")
    if not editor.is_connected("confirmed", on_confirmed):
        editor.connect("confirmed", on_confirmed)
    if not editor.is_connected("cancelled", on_cancelled):
        editor.connect("cancelled", on_cancelled)

    _creation_in_progress = true
    var inventory: Node = get_node_or_null("/root/SkyvalInventory")
    if inventory != null:
        inventory.call("reset_for_new_game", "male")
    if player.has_method("reset_for_new_game"):
        player.call("reset_for_new_game")
    var avatar: Node = player.get_node_or_null("CharacterVisual")
    if avatar != null and avatar.has_method("apply_starter_outfit"):
        avatar.call("apply_starter_outfit")
    editor.call("begin_creation")
    _set_open(false)


func _on_appearance_confirmed() -> void:
    if not _creation_in_progress:
        return
    var player: CharacterBody2D = _get_player()
    var body_type: String = "male"
    if player != null:
        var avatar: Node = player.get_node_or_null("CharacterVisual")
        if avatar != null and avatar.has_method("apply_starter_outfit"):
            avatar.call("apply_starter_outfit")
        var inventory: Node = get_node_or_null("/root/SkyvalInventory")
        if inventory != null and avatar != null and avatar.has_method("get_lpc_option"):
            body_type = str(avatar.call("get_lpc_option", "body_type"))
            inventory.call("set_starter_equipment", body_type)
    # The character has no profile or save until the name is confirmed.
    _name_entry.call("open_entry", body_type)


func _on_name_confirmed(character_name: String) -> void:
    if not _creation_in_progress:
        return
    var old_path: String = _active_save_path
    var data: Dictionary = _save_store.call("new_profile", character_name)
    if data.is_empty():
        _on_name_cancelled()
        return
    _active_save_path = str(data["path"])
    _profile_data = data
    _session_started = true
    _creation_in_progress = false
    if not _save_current_game():
        push_warning("Skyval: first character save failed.")
        _active_save_path = old_path
        if not old_path.is_empty():
            _load_profile(old_path, false)
        else:
            _session_started = false
            _profile_data.clear()
        _set_open(true)


func _on_name_cancelled() -> void:
    if not _creation_in_progress:
        return
    if not _active_save_path.is_empty():
        _load_profile(_active_save_path, false)
    _set_open(true)
    _creation_in_progress = false


func _on_appearance_cancelled() -> void:
    if not _creation_in_progress:
        return
    if not _active_save_path.is_empty():
        _load_profile(_active_save_path, false)
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
    _language_value.add_theme_color_override("font_color", ACTIVE_HIGHLIGHT)
    language_row.add_child(_language_value)

    var next_button := _button()
    next_button.text = "›"
    next_button.custom_minimum_size = Vector2(25, 29)
    next_button.pressed.connect(_change_language.bind(1))
    language_row.add_child(next_button)

    _continue_panel = VBoxContainer.new()
    _continue_panel.add_theme_constant_override("separation", 5)
    stack.add_child(_continue_panel)
    _profile_list = VBoxContainer.new()
    _profile_list.add_theme_constant_override("separation", 3)
    _continue_panel.add_child(_profile_list)
    _profile_hint = _label(MIN_UI_FONT_SIZE)
    _profile_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _profile_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _continue_panel.add_child(_profile_hint)

    # Confirmation is kept inside the same panel, with no Back buttons.
    _confirm_panel = VBoxContainer.new()
    _confirm_panel.add_theme_constant_override("separation", 12)
    stack.add_child(_confirm_panel)

    _confirm_message = _label(15)
    _confirm_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _confirm_message.custom_minimum_size.y = 65
    _confirm_panel.add_child(_confirm_message)

    _confirm_hint = _label(MIN_UI_FONT_SIZE)
    _confirm_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _confirm_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _confirm_panel.add_child(_confirm_hint)

    _refresh_text()


func _label(font_size: int) -> Label:
    var label := Label.new()
    label.add_theme_font_size_override("font_size", maxi(font_size, MIN_UI_FONT_SIZE))
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
        style.border_color = Color("#52657a") if unavailable else (ACTIVE_HIGHLIGHT if selected else Color("#667f9a"))
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
        # Selected menu text uses EXACTLY the same gold as its border.
        # Apply the same color on hover/pressed for mouse and gamepad parity.
        var menu_text: Color = ACTIVE_HIGHLIGHT if selected else Color("#edf1f5")
        button.add_theme_color_override("font_color", menu_text)
        button.add_theme_color_override("font_hover_color", menu_text)
        button.add_theme_color_override("font_pressed_color", menu_text)


func _refresh_text() -> void:
    if _heading == null:
        return
    if _confirm_delete:
        _heading.text = _tr("save.delete_title")
    elif _continue_open:
        _heading.text = _tr("save.list_title")
    elif _settings_open:
        _heading.text = _tr("settings.title")
    else:
        _heading.text = _tr("menu.title")
    for index in range(MAIN_OPTIONS.size()):
        _menu_buttons[index].text = _tr(str(MAIN_OPTIONS[index]))
    _menu_buttons[0].disabled = not _has_valid_save()
    if _menu_buttons[_selected_option].disabled:
        _selected_option = 1
    _language_caption.text = _tr("settings.language")
    _language_value.text = _tr("settings.language.en") if str(_locale.get("language")) == "en" else _tr("settings.language.uk")
    if _confirm_delete and _selected_profile >= 0 and _selected_profile < _profiles.size():
        _confirm_message.text = _tr("save.delete_confirm") % str(_profiles[_selected_profile].get("character_name", ""))
    _confirm_hint.text = _tr("menu.confirm_hint")
    _main_panel.visible = not _settings_open and not _continue_open and not _confirm_delete
    _settings_panel.visible = _settings_open and not _confirm_delete
    _continue_panel.visible = _continue_open and not _confirm_delete
    _confirm_panel.visible = _confirm_delete
    if _continue_open:
        _draw_profiles()
    _update_highlight()
