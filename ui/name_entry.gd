extends CanvasLayer
## Controller-only name entry designed for a 320x240 logical viewport.

signal accepted(character_name: String)
signal cancelled

const LocaleScript = preload("res://localization/localization.gd")
const FONT_PATH := "res://assets/fonts/CascadiaMono-Regular.ttf"
const CREATION_BACKGROUND := "res://assets/images/create_hero_bg.jpg"
const UiTheme = preload("res://ui/skyval_theme.gd")
const FONT_SIZE := 14
const GRID_COLUMNS := 8
const NAME_WIDTH := 264.0
const NAME_SPACING := 2
const ACTIVE := Color("#e7ca86")
const PRESS_THRESHOLD := 0.65
const RELEASE_THRESHOLD := 0.40
const NAV_DEBOUNCE_MS := 90

var _locale: Node
var _font: FontFile
var _root: Control
var _background: TextureRect
var _shade: ColorRect
var _entry_panel_style: StyleBoxFlat
var _title: Label
var _hint: Label
var _name_row: HBoxContainer
var _keys: Array[String] = []
var _key_buttons: Array[Button] = []
var _slots: Array[Label] = []
var _name: String = ""
var _selected: int = 0
var _max_length: int = 0
var _slot_width: float = 0.0
var _body_type: String = "male"
var _purpose: String = "character"
var _opened: bool = false
var _confirmation: String = ""
var _confirm_overlay: Control
var _confirm_message: Label
var _confirm_accept: Button
var _confirm_cancel: Button
var _held_buttons: Dictionary = {}
var _axis_latches: Dictionary = {}
var _last_nav_ms: int = -10000
var _ignore_buttons_until: int = 0


func _ready() -> void:
    # When this CanvasLayer is inserted while its parent is entering the
    # scene, another UI can call open_entry before Godot dispatches _ready.
    # Initialization is deliberately idempotent and can be requested early.
    ensure_initialized()


func ensure_initialized() -> void:
    if is_instance_valid(_root):
        return
    process_mode = Node.PROCESS_MODE_ALWAYS
    _locale = get_node_or_null("/root/SkyvalLocale")
    if _locale == null:
        _locale = LocaleScript.new()
        _locale.name = "NameEntryLocale"
        add_child(_locale)
    if ResourceLoader.exists(FONT_PATH):
        _font = load(FONT_PATH) as FontFile
        if _font != null:
            _font = _font.duplicate() as FontFile
            _font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
            _font.hinting = TextServer.HINTING_NORMAL
    # Label's true minimum includes the glyph width; dividing the full
    # row by the raw width of only "Щ" produced too many name slots,
    # expanding the parent PanelContainer beyond the 320px viewport.
    # Use the widest displayed glyph, round UP to whole pixels and reserve
    # 1px of slack per slot for fonts and Godot's container rounding.
    var glyph_width: float = 9.0
    if _font != null:
        for symbol in ["_", "Щ", "W", "М"]:
            glyph_width = maxf(glyph_width, _font.get_string_size(symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)
    _slot_width = ceilf(glyph_width) + 1.0
    _max_length = maxi(1, int(floor((NAME_WIDTH + NAME_SPACING) / (_slot_width + NAME_SPACING))))
    _build_interface()
    _root.hide()


func is_open() -> bool:
    return _opened


func open_entry(body_type: String = "male") -> void:
    _purpose = "character"
    _body_type = body_type
    _begin_entry()


func open_save_entry() -> void:
    # Manual saves reuse the same 14px controller keyboard.
    _purpose = "save"
    _begin_entry()


func _begin_entry() -> void:
    if not is_inside_tree():
        push_error("Skyval NameEntry: cannot open a detached UI layer.")
        return
    ensure_initialized()
    _name = ""
    _selected = 0
    _confirmation = ""
    _held_buttons.clear()
    _axis_latches.clear()
    _last_nav_ms = -10000
    _ignore_buttons_until = Time.get_ticks_msec() + 180
    _rebuild_keyboard()
    _refresh_slots()
    _apply_purpose_style()
    _confirm_overlay.hide()
    _set_open(true)


func _apply_purpose_style() -> void:
    # Character naming is the next step of the illustrated creation
    # sequence. Manual save naming stays a neutral utility window.
    var scenic: bool = _purpose == "character" and _background.texture != null
    _background.visible = scenic
    # Character naming keeps its artwork; manual Save overlays the game.
    # Both use the same gold-rimmed panel with enough opacity for 14px.
    _shade.color = Color(0.02, 0.03, 0.07, 0.17 if scenic else 0.23)
    _entry_panel_style.bg_color = Color(0.055, 0.085, 0.14, 0.86 if scenic else 0.93)
    _entry_panel_style.border_color = Color("#d6b77c")
    _title.add_theme_color_override("font_color", UiTheme.LIGHT_GOLD)


func _hint_key() -> String:
    return "save.name_hint" if _purpose == "save" else "name.hint"


func _tr(key: String) -> String:
    return str(_locale.call("t", key))


func _set_open(next_open: bool) -> void:
    if _opened == next_open:
        return
    if not is_inside_tree():
        push_error("Skyval NameEntry: cannot change UI visibility before entering SceneTree.")
        return
    _opened = next_open
    _root.visible = next_open
    var pause_manager: Node = get_node_or_null("/root/SkyvalUiPause")
    if pause_manager != null:
        pause_manager.call("set_open", self, next_open)
    else:
        get_tree().paused = next_open


func _input(event: InputEvent) -> void:
    if not _opened:
        return
    if event is InputEventJoypadButton:
        var button: InputEventJoypadButton = event
        var button_id: String = "%s:%s" % [button.device, button.button_index]
        if not button.pressed:
            _held_buttons.erase(button_id)
            return
        if _held_buttons.has(button_id):
            return
        _held_buttons[button_id] = true
        if Time.get_ticks_msec() < _ignore_buttons_until:
            get_viewport().set_input_as_handled()
            return
        if not _confirmation.is_empty():
            if button.button_index == JOY_BUTTON_A:
                _complete_confirmation()
            elif button.button_index == JOY_BUTTON_B:
                _close_confirmation()
        else:
            match button.button_index:
                JOY_BUTTON_DPAD_LEFT:
                    _move(-1, 0)
                JOY_BUTTON_DPAD_RIGHT:
                    _move(1, 0)
                JOY_BUTTON_DPAD_UP:
                    _move(0, -1)
                JOY_BUTTON_DPAD_DOWN:
                    _move(0, 1)
                JOY_BUTTON_A:
                    _select_key(_selected)
                JOY_BUTTON_B:
                    if _purpose == "character":
                        # Go back to the existing appearance draft, not to
                        # the title screen. No character save exists yet.
                        _set_open(false)
                        cancelled.emit()
                    else:
                        # Manual save naming keeps its own exit dialog.
                        _show_confirmation("exit")
                JOY_BUTTON_X:
                    if not _name.strip_edges().is_empty():
                        _show_confirmation("accept")
                    else:
                        _hint.text = _tr("save.name_empty" if _purpose == "save" else "name.empty")
                JOY_BUTTON_Y:
                    _randomize_name()
        get_viewport().set_input_as_handled()
    elif event is InputEventJoypadMotion:
        var motion: InputEventJoypadMotion = event
        if motion.axis not in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]:
            get_viewport().set_input_as_handled()
            return
        var axis_id: String = "%s:%s" % [motion.device, motion.axis]
        var previous: int = int(_axis_latches.get(axis_id, 0))
        var direction: int = 0
        if motion.axis_value >= PRESS_THRESHOLD:
            direction = 1
        elif motion.axis_value <= -PRESS_THRESHOLD:
            direction = -1
        elif absf(motion.axis_value) > RELEASE_THRESHOLD:
            direction = previous
        if direction != previous:
            _axis_latches[axis_id] = direction
            if direction != 0 and _confirmation.is_empty():
                if motion.axis == JOY_AXIS_LEFT_X or motion.axis == JOY_AXIS_RIGHT_X:
                    _move(direction, 0)
                else:
                    _move(0, direction)
        get_viewport().set_input_as_handled()


func _move(dx: int, dy: int) -> void:
    var now: int = Time.get_ticks_msec()
    if now - _last_nav_ms < NAV_DEBOUNCE_MS:
        return
    _last_nav_ms = now
    var column: int = _selected % GRID_COLUMNS
    var row: int = _selected / GRID_COLUMNS
    var next: int = (row + dy) * GRID_COLUMNS + column + dx
    if dx != 0 and (column + dx < 0 or column + dx >= GRID_COLUMNS):
        return
    if next >= 0 and next < _keys.size():
        _selected = next
        _update_key_highlight()


func _rebuild_keyboard() -> void:
    var grid: GridContainer = _root.get_node("Panel/Stack/KeyboardCenter/Grid") as GridContainer
    for button in _key_buttons:
        grid.remove_child(button)
        button.queue_free()
    _key_buttons.clear()
    _keys.clear()
    var alphabet: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    if str(_locale.get("language")) == "uk":
        alphabet = "АБВГҐДЕЄЖЗИІЇЙКЛМНОПРСТУФХЦЧШЩЬЮЯ"
    for i in range(alphabet.length()):
        _keys.append(alphabet.substr(i, 1))
    _keys.append(" ")
    _keys.append("<")
    for i in range(_keys.size()):
        var button := Button.new()
        button.focus_mode = Control.FOCUS_NONE
        button.custom_minimum_size = Vector2(31, 23)
        button.text = "␣" if _keys[i] == " " else ("←" if _keys[i] == "<" else _keys[i])
        button.add_theme_font_size_override("font_size", FONT_SIZE)
        if _font != null:
            button.add_theme_font_override("font", _font)
        UiTheme.apply_button(button, false, false, 1.0)
        button.pressed.connect(_select_key.bind(i))
        grid.add_child(button)
        _key_buttons.append(button)
    _title.text = _tr("save.name_title" if _purpose == "save" else "name.title")
    _hint.text = _tr(_hint_key())
    _update_key_highlight()


func _update_key_highlight() -> void:
    for i in range(_key_buttons.size()):
        # The controller cursor matches the same gold selection as every
        # menu, chest and equipment field; keyboard geometry is unchanged.
        UiTheme.apply_button(_key_buttons[i], i == _selected, false, 1.0)


func _select_key(index: int) -> void:
    if not _opened or not _confirmation.is_empty() or index < 0 or index >= _keys.size():
        return
    var symbol: String = _keys[index]
    if symbol == "<":
        if not _name.is_empty():
            _name = _name.substr(0, _name.length() - 1)
    elif symbol == " ":
        if not _name.is_empty() and not _name.ends_with(" ") and _name.length() < _max_length:
            _name += " "
    elif _name.length() < _max_length:
        _name += symbol.to_upper() if _name.is_empty() or _name.ends_with(" ") else symbol.to_lower()
    _refresh_slots()
    _hint.text = _tr(_hint_key())


func _randomize_name() -> void:
    var ukrainian: bool = str(_locale.get("language")) == "uk"
    if _purpose == "save":
        var titles: Array[String] = ["Пригода", "Подорож", "Нова глава", "На роздоріжжі", "Відпочинок"]
        if not ukrainian:
            titles = ["Adventure", "New chapter", "Journey", "Rest", "Before quest"]
        _name = titles.pick_random().substr(0, _max_length)
        _refresh_slots()
        _hint.text = _tr(_hint_key())
        return
    var male_names: Array[String] = ["Олександр", "Андрій", "Максим", "Богдан", "Тарас", "Данило", "Сергій", "Ярослав"]
    var female_names: Array[String] = ["Олена", "Марія", "Софія", "Дарина", "Соломія", "Катерина", "Аліна", "Оксана"]
    if not ukrainian:
        male_names = ["Alexander", "Daniel", "Arthur", "Oliver", "Thomas", "Max", "Leo", "James"]
        female_names = ["Alice", "Emma", "Sophia", "Olivia", "Amelia", "Nora", "Luna", "Mia"]
    var options: Array[String] = female_names if _body_type == "female" else male_names
    _name = options.pick_random().substr(0, _max_length)
    _refresh_slots()
    _hint.text = _tr(_hint_key())


func _refresh_slots() -> void:
    for i in range(_slots.size()):
        var slot: Label = _slots[i]
        slot.text = _name.substr(i, 1) if i < _name.length() else "_"
        slot.add_theme_color_override("font_color", ACTIVE if i < _name.length() else Color("#9ba9bb"))


func _show_confirmation(action: String) -> void:
    _confirmation = action
    if _purpose == "save":
        _confirm_message.text = _tr("save.name_exit") if action == "exit" else _tr("save.name_confirm") % _name.strip_edges()
    else:
        _confirm_message.text = _tr("name.confirm_exit") if action == "exit" else _tr("name.confirm_accept") % _name.strip_edges()
    _confirm_accept.text = _tr("menu.confirm_accept")
    _confirm_cancel.text = _tr("menu.confirm_cancel")
    _confirm_overlay.show()


func _close_confirmation() -> void:
    _confirmation = ""
    _confirm_overlay.hide()


func _complete_confirmation() -> void:
    var action: String = _confirmation
    _close_confirmation()
    if action == "exit":
        cancelled.emit()
        _set_open(false)
    elif action == "accept":
        var final_name: String = _name.strip_edges()
        if not final_name.is_empty():
            accepted.emit(final_name)
            _set_open(false)


func _new_label(size: int) -> Label:
    var label := Label.new()
    label.add_theme_font_size_override("font_size", maxi(size, FONT_SIZE))
    if _font != null:
        label.add_theme_font_override("font", _font)
    label.add_theme_color_override("font_color", Color("#f0f1ed"))
    return label


func _build_interface() -> void:
    _root = Control.new()
    _root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _root.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(_root)

    _background = TextureRect.new()
    _background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _background.stretch_mode = TextureRect.STRETCH_SCALE
    _background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    _background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    if ResourceLoader.exists(CREATION_BACKGROUND):
        _background.texture = load(CREATION_BACKGROUND) as Texture2D
    _root.add_child(_background)

    _shade = ColorRect.new()
    _shade.color = Color(0.02, 0.04, 0.08, 0.90)
    _shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.add_child(_shade)

    var panel := PanelContainer.new()
    panel.name = "Panel"
    # 10px safe margins in the 320px game viewport.
    panel.position = Vector2(10, 4)
    panel.custom_minimum_size = Vector2(300, 232)
    panel.size = Vector2(300, 232)
    _entry_panel_style = UiTheme.panel_style(0.90, 5.0)
    panel.add_theme_stylebox_override("panel", _entry_panel_style)
    _root.add_child(panel)

    var stack := VBoxContainer.new()
    stack.name = "Stack"
    stack.add_theme_constant_override("separation", 4)
    panel.add_child(stack)

    _title = _new_label(16)
    _title.add_theme_color_override("font_color", UiTheme.LIGHT_GOLD)
    _title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _title.custom_minimum_size.y = 18
    stack.add_child(_title)

    _name_row = HBoxContainer.new()
    _name_row.add_theme_constant_override("separation", NAME_SPACING)
    _name_row.alignment = BoxContainer.ALIGNMENT_CENTER
    _name_row.custom_minimum_size.y = 22
    _name_row.clip_contents = true
    stack.add_child(_name_row)
    for i in range(_max_length):
        var slot := _new_label(FONT_SIZE)
        slot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        slot.custom_minimum_size = Vector2(_slot_width, 20)
        _name_row.add_child(slot)
        _slots.append(slot)

    # Center the entire keyboard without stretching its eight columns.
    var keyboard_center := CenterContainer.new()
    keyboard_center.name = "KeyboardCenter"
    keyboard_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    stack.add_child(keyboard_center)

    var grid := GridContainer.new()
    grid.name = "Grid"
    grid.columns = GRID_COLUMNS
    grid.add_theme_constant_override("h_separation", 4)
    grid.add_theme_constant_override("v_separation", 3)
    keyboard_center.add_child(grid)

    _hint = _new_label(FONT_SIZE)
    _hint.add_theme_color_override("font_color", UiTheme.MUTED)
    _hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _hint.custom_minimum_size.y = 33
    stack.add_child(_hint)

    _confirm_overlay = Control.new()
    _confirm_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _confirm_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    _root.add_child(_confirm_overlay)
    var confirmation_shade := ColorRect.new()
    confirmation_shade.color = Color(0.02, 0.03, 0.07, 0.50)
    confirmation_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    confirmation_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _confirm_overlay.add_child(confirmation_shade)
    var confirmation_panel := PanelContainer.new()
    # Centered confirmation, with space for long names and two full
    # vertical choices. No overlapping controller hint text.
    confirmation_panel.position = Vector2(20, 40)
    confirmation_panel.custom_minimum_size = Vector2(280, 160)
    confirmation_panel.size = Vector2(280, 160)
    var confirm_style: StyleBoxFlat = UiTheme.panel_style(0.97, 8.0)
    confirmation_panel.add_theme_stylebox_override("panel", confirm_style)
    _confirm_overlay.add_child(confirmation_panel)
    var confirmation_stack := VBoxContainer.new()
    confirmation_stack.add_theme_constant_override("separation", 5)
    confirmation_panel.add_child(confirmation_stack)

    _confirm_message = _new_label(FONT_SIZE)
    _confirm_message.add_theme_color_override("font_color", UiTheme.LIGHT_GOLD)
    _confirm_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _confirm_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _confirm_message.custom_minimum_size.y = 69
    confirmation_stack.add_child(_confirm_message)

    var choices := VBoxContainer.new()
    choices.add_theme_constant_override("separation", 4)
    choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    confirmation_stack.add_child(choices)

    _confirm_accept = Button.new()
    _confirm_accept.focus_mode = Control.FOCUS_NONE
    _confirm_accept.custom_minimum_size.y = 25
    _confirm_accept.add_theme_font_size_override("font_size", FONT_SIZE)
    if _font != null:
        _confirm_accept.add_theme_font_override("font", _font)
    UiTheme.apply_button(_confirm_accept)
    _confirm_accept.pressed.connect(_complete_confirmation)
    choices.add_child(_confirm_accept)

    _confirm_cancel = Button.new()
    _confirm_cancel.focus_mode = Control.FOCUS_NONE
    _confirm_cancel.custom_minimum_size.y = 25
    _confirm_cancel.add_theme_font_size_override("font_size", FONT_SIZE)
    if _font != null:
        _confirm_cancel.add_theme_font_override("font", _font)
    UiTheme.apply_button(_confirm_cancel)
    _confirm_cancel.pressed.connect(_close_confirmation)
    choices.add_child(_confirm_cancel)
    _confirm_overlay.hide()
