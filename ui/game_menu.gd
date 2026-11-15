extends CanvasLayer
## Global game menu for Godot 4.7 / PortMaster, opened with Start or R3.
## Select or L3 is reserved for the character editor (future inventory).
## All captions come from localization/strings.json.

const LocaleScript = preload("res://localization/localization.gd")
const SaveStoreScript = preload("res://game/save_store.gd")
const NameEntryScript = preload("res://ui/name_entry.gd")
const UiTheme = preload("res://ui/skyval_theme.gd")
const ControllerChoiceScript = preload("res://ui/nintendo_choice.gd")
const FONT_PATH := "res://assets/fonts/CascadiaMono-Regular.ttf"
const TITLE_IMAGE_PATH := "res://assets/images/title_bg.jpg"
const TITLE_MENU_WIDTH := 184.0
const TITLE_BUTTON_HEIGHT := 24.0
const TITLE_BUTTON_GAP := 1.0
const MIN_UI_FONT_SIZE := 14
const ACTIVE_HIGHLIGHT := Color("#e7ca86")
const NAV_DEBOUNCE_MS := 100
const STICK_PRESS := 0.65
const STICK_RELEASE := 0.42
const VISIBLE_PROFILES := 4
const MAIN_OPTIONS := ["menu.continue", "menu.select_character", "menu.new_game", "menu.settings", "menu.quit"]
const GAME_OPTIONS := ["game.quick_save", "game.quick_load", "game.save", "game.load", "menu.settings", "game.main_menu", "game.quit"]

@onready var _creator: CanvasLayer = get_parent().get_node("CharacterCreator") as CanvasLayer

var _locale: Node
var _font: FontFile
var _opened: bool = false
var _main_mode: bool = true
var _settings_open: bool = false
var _list_mode: String = "" # characters, character_saves or load
var _selected_character_id: String = ""
var _selected_character_index: int = 0
var _pending_manual_save: bool = false
var _confirm_action: String = "" # load, delete, main, quit
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
var _title_image: TextureRect
var _shade: ColorRect
var _panel: PanelContainer
var _panel_style: StyleBoxFlat
var _title_panel_style: StyleBoxFlat
var _divider: ColorRect
var _heading: Label
var _main_panel: VBoxContainer
var _settings_panel: VBoxContainer
var _continue_panel: VBoxContainer
var _profile_list: VBoxContainer
var _profile_hint: Label
var _confirm_panel: VBoxContainer
var _confirm_message: Label
var _confirm_accept: Control
var _confirm_cancel: Control
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


# Progress is saved only after creating a character, or by the player's
# explicit Quick Save / Save command. No periodic/menu/loot checkpoints.

func _tr(key: String) -> String:
    return str(_locale.call("t", key))


func _input(event: InputEvent) -> void:
    # NameEntry is a separate modal above this menu. Do not handle its
    # X/Y/A/B presses a second time behind the name keyboard.
    if _name_entry != null and bool(_name_entry.call("is_open")):
        return
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
                _back_from_list()
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
    # Title and game menus both preserve their natural top-to-bottom order.
    var next_index: int = _selected_option + direction
    while next_index >= 0 and next_index < _visible_options.size():
        if not _menu_buttons[next_index].disabled:
            _selected_option = next_index
            _status_message = ""
            _refresh_text()
            return
        next_index += direction

func _activate_option(index: int) -> void:
    if not _opened or index < 0 or index >= _visible_options.size():
        return
    if _menu_buttons[index].disabled:
        return
    _status_message = ""
    match _visible_options[index]:
        "menu.continue":
            var profile: Dictionary = _save_store.call("last_opened_profile")
            if not profile.is_empty():
                var recent: Dictionary = _save_store.call("latest_save", str(profile.get("profile_id", "")))
                if not recent.is_empty():
                    _load_selected_save(str(recent.get("path", "")))
        "menu.select_character":
            _open_list("characters")
        "menu.new_game":
            _start_new_game()
        "menu.settings":
            _show_settings(true)
        "menu.quit":
            get_tree().quit()
        "game.quick_save":
            _write_snapshot("quick")
        "game.quick_load":
            var quick: Dictionary = _save_store.call("quick_save_for", str(_profile_data.get("profile_id", "")))
            if not quick.is_empty():
                # Quick Load intentionally skips the confirmation dialog.
                _load_selected_save(str(quick.get("path", "")))
        "game.save":
            _pending_manual_save = true
            _name_entry.call("open_save_entry")
        "game.load":
            _open_list("load")
        "game.main_menu":
            _ask_confirmation("main")
        "game.quit":
            _ask_confirmation("quit")
    _refresh_text()


func _open_list(mode: String) -> void:
    _list_mode = mode
    _selected_list = 0
    _listed_items.clear()
    if mode == "characters":
        _listed_items = _save_store.call("list_profiles")
    elif mode == "load":
        _listed_items = _save_store.call("list_saves", str(_profile_data.get("profile_id", "")))
    elif mode == "character_saves":
        _listed_items = _save_store.call("list_saves", _selected_character_id)
    if _listed_items.is_empty():
        if mode == "character_saves":
            _back_from_list()
        else:
            _list_mode = ""
            _status_message = _tr("save.none") if mode == "characters" else _tr("save.no_slots")
    _refresh_text()


func _back_from_list() -> void:
    if _list_mode == "character_saves":
        _open_list("characters")
        _selected_list = mini(_selected_character_index, maxi(0, _listed_items.size() - 1))
        _draw_profiles()
    else:
        _list_mode = ""
        _refresh_text()

func _move_list(direction: int) -> void:
    var next_index: int = _selected_list + direction
    if next_index >= 0 and next_index < _listed_items.size():
        _selected_list = next_index
        _draw_profiles()


func _choose_list_item() -> void:
    if _selected_list < 0 or _selected_list >= _listed_items.size():
        return
    var selected: Dictionary = _listed_items[_selected_list]
    if _list_mode == "characters":
        # Selecting a character opens ALL of that character's save slots.
        _selected_character_id = str(selected.get("profile_id", ""))
        _selected_character_index = _selected_list
        _open_list("character_saves")
        return
    var selected_path: String = str(selected.get("path", ""))
    if _list_mode == "character_saves":
        # Selecting a save through Select Character loads it directly.
        # Only the in-game Load menu requires confirmation.
        _load_selected_save(selected_path)
        return
    _pending_save_path = selected_path
    _ask_confirmation("load")

func _pick_profile(index: int) -> void:
    if index < 0 or index >= _listed_items.size():
        return
    _selected_list = index
    _choose_list_item()


func _ask_confirmation(action: String) -> void:
    _confirm_action = action
    _refresh_text()


func _dismiss_confirmation() -> void:
    _confirm_action = ""
    _pending_save_path = ""
    _refresh_text()


func _accept_confirmation() -> void:
    var action: String = _confirm_action
    var path: String = _pending_save_path
    _confirm_action = ""
    _pending_save_path = ""
    match action:
        "delete":
            _delete_selected_profile()
        "load":
            if _load_selected_save(path):
                return
        "main":
            _return_to_main()
        "quit":
            # Exiting never writes progress. Unsaved changes are discarded.
            get_tree().quit()
    _refresh_text()


func _load_selected_save(path: String) -> bool:
    if not _load_profile(path, true):
        _list_mode = ""
        _status_message = _tr("save.load_failed")
        _refresh_text()
        return false
    _main_mode = false
    _list_mode = ""
    _set_open(false)
    return true


func _delete_selected_profile() -> void:
    if _list_mode != "characters" or _selected_list < 0 or _selected_list >= _listed_items.size():
        return
    var selected: Dictionary = _listed_items[_selected_list]
    if not bool(_save_store.call("delete_profile", str(selected.get("path", "")))):
        _list_mode = ""
        _status_message = _tr("save.delete_failed")
        return
    _listed_items = _save_store.call("list_profiles")
    _selected_list = mini(_selected_list, maxi(0, _listed_items.size() - 1))
    if _listed_items.is_empty():
        _list_mode = ""
        _selected_option = 0


func _return_to_main() -> void:
    # Explicitly leave the session without saving. The confirmation
    # warns that progress since the last save will be lost.
    _session_started = false
    _active_save_path = ""
    _profile_data.clear()
    _main_mode = true
    _settings_open = false
    _list_mode = ""
    _selected_option = 0
    _status_message = ""

func _draw_profiles() -> void:
    if _profile_list == null:
        return
    for child in _profile_list.get_children():
        _profile_list.remove_child(child)
        child.queue_free()
    if _listed_items.is_empty():
        var empty_label := _label(MIN_UI_FONT_SIZE)
        empty_label.text = _tr("save.none")
        _profile_list.add_child(empty_label)
        return
    var first: int = maxi(0, _selected_list - VISIBLE_PROFILES + 1)
    var last: int = mini(_listed_items.size(), first + VISIBLE_PROFILES)
    for i in range(first, last):
        var data: Dictionary = _listed_items[i]
        var button := _button()
        button.add_theme_font_size_override("font_size", MIN_UI_FONT_SIZE)
        button.custom_minimum_size.y = 26
        button.clip_text = true
        if _list_mode == "characters":
            button.text = str(data.get("character_name", ""))
        else:
            var label: String = str(data.get("save_name", "")).strip_edges()
            if label.is_empty():
                label = _tr("save.kind." + str(data.get("save_kind", "profile")))
            # Reserve space for the timestamp at 14px on 320x240.
            button.text = "%s  %s" % [label.substr(0, 13), _time_label(int(data.get("saved_at", 0)))]
        button.pressed.connect(_pick_profile.bind(i))
        var selected: bool = i == _selected_list
        # Same gold selection and translucent navy as the other windows.
        UiTheme.apply_button(button, selected, false, 3.0)
        _profile_list.add_child(button)
    var hint_key: String = "save.list_hint" if _list_mode == "characters" else "save.load_hint"
    _profile_hint.text = "%d/%d  %s" % [_selected_list + 1, _listed_items.size(), _tr(hint_key)]


func _time_label(timestamp_ms: int) -> String:
    if timestamp_ms <= 0:
        return "--:--"
    var time: Dictionary = Time.get_datetime_dict_from_unix_time(int(timestamp_ms / 1000))
    return "%02d.%02d %02d:%02d" % [
        int(time.get("day", 1)), int(time.get("month", 1)),
        int(time.get("hour", 0)), int(time.get("minute", 0)),
    ]

func _get_player() -> CharacterBody2D:
    var world: Node = get_tree().current_scene
    if world == null:
        return null
    return world.get_node_or_null("Player") as CharacterBody2D


func _has_valid_save() -> bool:
    var last: Dictionary = _save_store.call("last_opened_profile")
    if last.is_empty():
        return false
    var recent: Dictionary = _save_store.call("latest_save", str(last.get("profile_id", "")))
    return not recent.is_empty()


func _capture_current_game() -> Dictionary:
    # Snapshot the *live* world without writing or mutating the profile.
    # A loaded manual/quick save must not be replaced by an old profile.
    if _active_save_path.is_empty() or _profile_data.is_empty():
        return {}
    var player: CharacterBody2D = _get_player()
    if player == null:
        return {}

    var data: Dictionary = _profile_data.duplicate(true)
    data["version"] = 2
    data["path"] = _active_save_path
    data["player_position"] = [player.global_position.x, player.global_position.y]
    data["appearance"] = {}
    var avatar: Node = player.get_node_or_null("CharacterVisual")
    if avatar != null and avatar.has_method("get_save_state"):
        data["appearance"] = avatar.call("get_save_state")
    var inventory: Node = get_node_or_null("/root/SkyvalInventory")
    if inventory != null:
        data["inventory"] = inventory.call("get_save_state")
    return data


func _save_initial_profile() -> bool:
    # Exactly one automatic progress save, after character creation.
    var data: Dictionary = _capture_current_game()
    if data.is_empty():
        return false
    data["save_kind"] = "profile"
    if not bool(_save_store.call("write_profile", _active_save_path, data)):
        return false
    _profile_data = data
    return true


func _write_snapshot(kind: String, save_name: String = "") -> void:
    if not _session_started:
        _status_message = _tr("save.write_failed")
        return
    var data: Dictionary = _capture_current_game()
    if data.is_empty():
        _status_message = _tr("save.write_failed")
        return
    var path: String = str(_save_store.call("slot_path", _profile_data, kind, save_name))
    if path.is_empty():
        _status_message = _tr("save.write_failed")
        return
    data["path"] = path
    data["save_kind"] = kind
    data["save_name"] = save_name.strip_edges() if kind == "manual" else ""
    data["saved_at"] = int(Time.get_unix_time_from_system() * 1000.0)
    if bool(_save_store.call("write_profile", path, data)):
        _status_message = _tr("save.quick_done") if kind == "quick" else _tr("save.manual_done")
        if kind == "quick":
            # Close only after a successful quick save, not on write errors.
            _set_open(false)
    else:
        _status_message = _tr("save.write_failed")

func _load_profile(path: String, touch_launch: bool = true) -> bool:
    var data: Dictionary = _save_store.call("read_profile", path)
    var player: CharacterBody2D = _get_player()
    if data.is_empty() or player == null:
        return false
    var id: String = str(data.get("profile_id", ""))
    var root_data: Dictionary = {}
    for profile in _save_store.call("list_profiles"):
        if str(profile.get("profile_id", "")) == id:
            root_data = profile
            break
    if root_data.is_empty():
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
    # Loading restores world state only. It NEVER writes game progress.
    # The root profile stays as the initial save (or the player's
    # pre-upgrade checkpoint) until the user explicitly saves elsewhere.
    _active_save_path = str(root_data["path"])
    _profile_data = root_data
    _session_started = true
    if touch_launch:
        # Separate UI metadata, NOT a progress save or profile overwrite.
        if not bool(_save_store.call("remember_opened", id)):
            push_warning("Skyval: could not remember last opened character.")
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
    if _pending_manual_save:
        _pending_manual_save = false
        _write_snapshot("manual", character_name)
        _ignore_presses_before_ms = Time.get_ticks_msec() + 200
        _refresh_text()
        return
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
    _main_mode = false
    _creation_in_progress = false
    if not _save_initial_profile():
        push_warning("Skyval: first character save failed.")
        _active_save_path = old_path
        if not old_path.is_empty():
            _load_profile(old_path, false)
        else:
            _session_started = false
            _profile_data.clear()
        _set_open(true)
    else:
        _save_store.call("remember_opened", str(data.get("profile_id", "")))


func _on_name_cancelled() -> void:
    if _pending_manual_save:
        _pending_manual_save = false
        _ignore_presses_before_ms = Time.get_ticks_msec() + 200
        _refresh_text()
        return
    if not _creation_in_progress:
        return
    # B from the character-name keyboard returns to the same appearance
    # draft. Do not load an old character, show the title screen, or
    # mark creation complete. No progress save is written here.
    var editor: Node = get_parent().get_node_or_null("AppearanceEditor")
    if editor != null and editor.has_method("resume_creation"):
        editor.call("resume_creation")
    else:
        push_error("Skyval: could not reopen appearance after cancelling name entry.")
        _creation_in_progress = false
        _set_open(true)


func _on_appearance_cancelled() -> void:
    if not _creation_in_progress:
        return
    if not _active_save_path.is_empty():
        _load_profile(_active_save_path, false)
    _set_open(true)
    _creation_in_progress = false

func _change_language(_direction: int) -> void:
    if not _opened or not _settings_open:
        return
    # Keep the original left/right language selector.
    var desired: String = "en" if str(_locale.get("language")) == "uk" else "uk"
    _locale.call("set_language", desired)


func _build_interface() -> void:
    _root = Control.new()
    _root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _root.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(_root)

    # A 320x240 optimized version of the supplied 4:3 title illustration.
    _title_image = TextureRect.new()
    _title_image.name = "TitleBackground"
    _title_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _title_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _title_image.stretch_mode = TextureRect.STRETCH_SCALE
    _title_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    _title_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
    if ResourceLoader.exists(TITLE_IMAGE_PATH):
        _title_image.texture = load(TITLE_IMAGE_PATH) as Texture2D
    else:
        push_warning("Skyval: title art not bundled: " + TITLE_IMAGE_PATH)
    _root.add_child(_title_image)

    _shade = ColorRect.new()
    _shade.color = Color(0.03, 0.08, 0.10, 0.76)
    _shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.add_child(_shade)

    _panel = PanelContainer.new()
    _panel.position = Vector2(34, 8)
    _panel.custom_minimum_size = Vector2(252, 224)
    _panel.size = Vector2(252, 224)
    _root.add_child(_panel)
    _panel_style = UiTheme.panel_style(0.92, 7.0)
    _panel.add_theme_stylebox_override("panel", _panel_style)

    _title_panel_style = StyleBoxFlat.new()
    _title_panel_style.bg_color = Color(0.04, 0.06, 0.11, 0.52)
    _title_panel_style.set_corner_radius_all(4)
    _title_panel_style.set_content_margin_all(4)

    var stack := VBoxContainer.new()
    stack.add_theme_constant_override("separation", 4)
    _panel.add_child(stack)

    _heading = _label(17)
    _heading.add_theme_color_override("font_color", UiTheme.LIGHT_GOLD)
    _heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    stack.add_child(_heading)

    _divider = ColorRect.new()
    _divider.color = Color(0.84, 0.71, 0.49, 0.80)
    _divider.custom_minimum_size.y = 1
    _divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
    stack.add_child(_divider)

    _main_panel = VBoxContainer.new()
    _main_panel.add_theme_constant_override("separation", 1)
    stack.add_child(_main_panel)
    # Seven game actions share the same buttons as at most five title actions.
    for i in range(GAME_OPTIONS.size()):
        var option := _button()
        option.add_theme_font_size_override("font_size", MIN_UI_FONT_SIZE)
        option.custom_minimum_size.y = 24
        option.pressed.connect(_activate_option.bind(i))
        _main_panel.add_child(option)
        _menu_buttons.append(option)

    _settings_panel = VBoxContainer.new()
    _settings_panel.add_theme_constant_override("separation", 9)
    stack.add_child(_settings_panel)

    _language_caption = _label(15)
    _language_caption.add_theme_color_override("font_color", UiTheme.LIGHT_GOLD)
    _settings_panel.add_child(_language_caption)

    # Restore the established arrow / value / arrow language switcher.
    var language_row := HBoxContainer.new()
    language_row.add_theme_constant_override("separation", 3)
    _settings_panel.add_child(language_row)

    var previous := _button()
    previous.text = "‹"
    previous.custom_minimum_size = Vector2(25, 29)
    previous.pressed.connect(_change_language.bind(-1))
    language_row.add_child(previous)

    _language_value = _label(MIN_UI_FONT_SIZE)
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
    _profile_hint.add_theme_color_override("font_color", UiTheme.MUTED)
    _profile_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _profile_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _continue_panel.add_child(_profile_hint)

    # Confirmation alternatives are neutral, unhighlighted text with
    # Nintendo-colored A/B circles. Both are left aligned and clickable.
    _confirm_panel = VBoxContainer.new()
    _confirm_panel.add_theme_constant_override("separation", 5)
    stack.add_child(_confirm_panel)

    _confirm_message = _label(MIN_UI_FONT_SIZE)
    _confirm_message.add_theme_color_override("font_color", UiTheme.LIGHT_GOLD)
    _confirm_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _confirm_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _confirm_message.custom_minimum_size.y = 94
    _confirm_panel.add_child(_confirm_message)

    var confirm_options := VBoxContainer.new()
    confirm_options.add_theme_constant_override("separation", 4)
    confirm_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _confirm_panel.add_child(confirm_options)

    _confirm_accept = ControllerChoiceScript.new() as Control
    _confirm_accept.call("configure", "A", _tr("menu.confirm_accept"), _font)
    _confirm_accept.connect("activated", Callable(self, "_accept_confirmation"))
    confirm_options.add_child(_confirm_accept)

    _confirm_cancel = ControllerChoiceScript.new() as Control
    _confirm_cancel.call("configure", "B", _tr("menu.confirm_cancel"), _font)
    _confirm_cancel.connect("activated", Callable(self, "_dismiss_confirmation"))
    confirm_options.add_child(_confirm_cancel)

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
    UiTheme.apply_button(button)
    return button


func _is_title_menu() -> bool:
    return _main_mode and not _settings_open and _list_mode.is_empty() and _confirm_action.is_empty()


func _style_menu_layout() -> void:
    var title: bool = _is_title_menu()
    _title_image.visible = _main_mode and _title_image.texture != null
    # Title keeps its bright artwork. Subpages and the in-game menu
    # shade the underlying scene slightly instead of hiding it.
    if title and _title_image.texture != null:
        _shade.color = Color(0.03, 0.04, 0.08, 0.07)
    else:
        _shade.color = Color(0.02, 0.03, 0.07, 0.38 if _main_mode else 0.24)
    _heading.visible = not title
    _divider.visible = not title
    _panel.add_theme_stylebox_override("panel", _title_panel_style if title else _panel_style)
    if title:
        var count: int = _visible_options.size()
        var height: float = 8.0 + TITLE_BUTTON_HEIGHT * count + TITLE_BUTTON_GAP * maxi(0, count - 1)
        _panel.custom_minimum_size = Vector2(TITLE_MENU_WIDTH, height)
        _panel.size = Vector2(TITLE_MENU_WIDTH, height)
        _panel.position = Vector2((320.0 - TITLE_MENU_WIDTH) / 2.0, 240.0 - height - 9.0)
        # Keep Continue at the top and Quit at the bottom. Only anchor
        # the stack to the lower edge; do not reverse button order.
        for i in range(_menu_buttons.size()):
            _main_panel.move_child(_menu_buttons[i], i)
    else:
        # Content-aware window sizes, centered within the native 320x240.
        # Confirmations have a larger text area and TWO vertical choices.
        # Settings need less height; seven-action gameplay needs all 224px.
        var panel_size: Vector2 = Vector2(252, 224)
        if not _confirm_action.is_empty():
            panel_size = Vector2(280, 202)
        elif _settings_open:
            panel_size = Vector2(260, 155)
        elif not _list_mode.is_empty():
            panel_size = Vector2(284, 218)
        _panel.custom_minimum_size = panel_size
        _panel.size = panel_size
        _panel.position = ((Vector2(320, 240) - panel_size) * 0.5).round()


func _update_highlight() -> void:
    var is_title: bool = _is_title_menu()
    for index in range(_menu_buttons.size()):
        var button: Button = _menu_buttons[index]
        var unavailable: bool = button.disabled
        var selected: bool = index == _selected_option and not unavailable
        if not is_title:
            # Settings, in-game menu, lists and confirmations share the
            # same palette; the illustrated title buttons retain their
            # original specially translucent backdrop.
            UiTheme.apply_button(button, selected, unavailable, 1.0)
            continue
        var style := StyleBoxFlat.new()
        style.bg_color = Color(0.06, 0.10, 0.18, 0.86) if selected else Color(0.05, 0.08, 0.13, 0.45)
        style.border_color = ACTIVE_HIGHLIGHT if selected else Color(0, 0, 0, 0)
        style.set_border_width_all(1)
        style.set_content_margin_all(1)
        button.add_theme_stylebox_override("normal", style)
        button.add_theme_stylebox_override("disabled", style)
        var hover := style.duplicate() as StyleBoxFlat
        hover.bg_color = Color(0.17, 0.25, 0.34, 0.85)
        button.add_theme_stylebox_override("hover", hover)
        var pressed := style.duplicate() as StyleBoxFlat
        pressed.bg_color = Color(0.20, 0.30, 0.41, 0.95)
        button.add_theme_stylebox_override("pressed", pressed)
        var ink: Color = ACTIVE_HIGHLIGHT if selected else UiTheme.INK
        button.add_theme_color_override("font_color", ink)
        button.add_theme_color_override("font_hover_color", ink)
        button.add_theme_color_override("font_pressed_color", ink)
        button.add_theme_color_override("font_disabled_color", UiTheme.DISABLED)


func _refresh_text() -> void:
    if _heading == null:
        return
    _visible_options.clear()
    if _main_mode:
        var profiles: Array[Dictionary] = _save_store.call("list_profiles")
        if _has_valid_save():
            _visible_options.append("menu.continue")
        if not profiles.is_empty():
            _visible_options.append("menu.select_character")
        _visible_options.append_array(["menu.new_game", "menu.settings", "menu.quit"])
    else:
        _visible_options.append_array(GAME_OPTIONS)
    if _selected_option < 0 or _selected_option >= _visible_options.size():
        _selected_option = 0
    for i in range(_menu_buttons.size()):
        var button: Button = _menu_buttons[i]
        button.visible = i < _visible_options.size()
        if i < _visible_options.size():
            button.text = _tr(_visible_options[i])
            button.disabled = false
            if _visible_options[i] == "game.quick_load":
                var quick: Dictionary = _save_store.call("quick_save_for", str(_profile_data.get("profile_id", "")))
                button.disabled = quick.is_empty()
    if not _visible_options.is_empty() and _menu_buttons[_selected_option].disabled:
        _selected_option = 0

    _heading.text = _tr("menu.title") if _main_mode else _tr("game.title")
    if not _status_message.is_empty() and _confirm_action.is_empty() and _list_mode.is_empty():
        _heading.text = _status_message
    if _settings_open:
        _heading.text = _tr("settings.title")
    elif not _list_mode.is_empty():
        _heading.text = _tr("save.list_title") if _list_mode == "characters" else _tr("save.load_title")
    if not _confirm_action.is_empty():
        match _confirm_action:
            "delete":
                _heading.text = _tr("save.delete_title")
                if _selected_list >= 0 and _selected_list < _listed_items.size():
                    _confirm_message.text = _tr("save.delete_confirm") % str(_listed_items[_selected_list].get("character_name", ""))
            "load":
                _heading.text = _tr("save.load_title")
                _confirm_message.text = _tr("save.load_confirm")
            "main":
                _heading.text = _tr("game.main_menu")
                _confirm_message.text = _tr("game.main_confirm")
            "quit":
                _heading.text = _tr("game.quit")
                _confirm_message.text = _tr("game.quit_confirm")

    _language_caption.text = _tr("settings.language")
    _language_value.text = _tr("settings.language.en") if str(_locale.get("language")) == "en" else _tr("settings.language.uk")
    _confirm_accept.call("set_caption", _tr("menu.confirm_accept"))
    _confirm_cancel.call("set_caption", _tr("menu.confirm_cancel"))
    _main_panel.visible = not _settings_open and _list_mode.is_empty() and _confirm_action.is_empty()
    _settings_panel.visible = _settings_open and _confirm_action.is_empty()
    _continue_panel.visible = not _list_mode.is_empty() and _confirm_action.is_empty()
    _confirm_panel.visible = not _confirm_action.is_empty()
    if not _list_mode.is_empty():
        _draw_profiles()
    _style_menu_layout()
    _update_highlight()
