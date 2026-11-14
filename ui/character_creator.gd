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
# Use only native joypad buttons and axes; avoid GUI double input.
const NAV_DEBOUNCE_MS := 100
const LEFT_STICK_PRESS := 0.65
const LEFT_STICK_RELEASE := 0.42
const RIGHT_STICK_PRESS := 0.65
const RIGHT_STICK_RELEASE := 0.35

@onready var avatar: SkyvalCharacterVisual = get_parent().get_node("Player/CharacterVisual") as SkyvalCharacterVisual

var _opened: bool = false
var _page: int = 0
var _selected_index: int = 0
var _row_labels: Array[Label] = []
var _row_values: Array[Label] = []
var _row_scroll: ScrollContainer
var _ui_font: FontFile
var _held_joy_buttons: Dictionary = {}
var _joy_axis_direction: Dictionary = {}
var _right_stick_latched: Dictionary = {}
var _last_navigation_ms: int = -10000
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
    _load_cascadia_font()
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

func _load_cascadia_font() -> void:
    # Project-local copy works in the exported PortMaster PCK.
    # In the desktop checkout, reuse the user's external asset library.
    var bundled_path: String = "res://assets/fonts/Cascadia.ttf"
    if ResourceLoader.exists(bundled_path):
        _ui_font = load(bundled_path) as FontFile
        if _ui_font != null:
            _ui_font = _ui_font.duplicate() as FontFile

    if _ui_font == null:
        var home: String = OS.get_environment("HOME")
        var candidates: PackedStringArray = [
            home.path_join("Godot/res/assets/fonts/Cascadia.ttf"),
            home.path_join("Godot/res/addons/Godot_LPC_Spritesheet/assets/fonts/Cascadia.ttf"),
        ]
        for path in candidates:
            if not FileAccess.file_exists(path):
                continue
            var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
            if bytes.is_empty():
                continue
            _ui_font = FontFile.new()
            _ui_font.data = bytes
            break

    if _ui_font != null:
        # Use Godot 4.7's supported hinting enum and whole-pixel positioning.
        _ui_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
        _ui_font.hinting = TextServer.HINTING_NORMAL
        _ui_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
        _ui_font.force_autohinter = true

        # This supplied Cascadia TTF lacks Cyrillic glyphs. Preserve
        # Ukrainian labels with the built-in theme font as fallback.
        var fallback: Font = ThemeDB.fallback_font
        if fallback != null and not _ui_font.get_supported_chars().contains("і"):
            var fallback_copy: Font = fallback.duplicate() as Font
            if fallback_copy is FontFile:
                var fallback_file: FontFile = fallback_copy as FontFile
                fallback_file.antialiasing = TextServer.FONT_ANTIALIASING_NONE
                fallback_file.hinting = TextServer.HINTING_NORMAL
                fallback_file.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
            _ui_font.fallbacks = [fallback_copy]
            push_warning("Skyval UI: Cascadia lacks Ukrainian glyphs; using built-in fallback for Cyrillic.")
        print("Skyval UI: Cascadia font ready")
    else:
        push_warning("Skyval UI: Cascadia.ttf not found; falling back to Godot's default font.")

# Capture native gamepad input before Godot GUI focus routing.
# Keyboard events are deliberately ignored by all gameplay menus.
func _input(event: InputEvent) -> void:
    if event is InputEventJoypadButton:
        _handle_joy_button(event as InputEventJoypadButton)
    elif event is InputEventJoypadMotion:
        _handle_joy_axis(event as InputEventJoypadMotion)

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
        # World shortcut: D-pad Down opens the creator.
        # Start and X are freed for future world-level actions.
        if event.button_index == JOY_BUTTON_DPAD_DOWN:
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
    # One 90-degree step per right-stick horizontal tilt. The stick must
    # return near the center before another step, including opposite tilts.
    if event.axis == JOY_AXIS_RIGHT_X:
        var x: float = event.axis_value
        if absf(x) <= RIGHT_STICK_RELEASE:
            _right_stick_latched.erase(event.device)
        elif absf(x) >= RIGHT_STICK_PRESS and not _right_stick_latched.has(event.device):
            _right_stick_latched[event.device] = true
            _preview.call("rotate_step", 1 if x > 0.0 else -1)
        get_viewport().set_input_as_handled()
        return
    if event.axis == JOY_AXIS_RIGHT_Y:
        # Vertical right-stick motion has no action in the creator.
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

func _can_navigate() -> bool:
    # Shared debounce protects against some devices reporting D-pad twice
    # (as buttons and as a left-axis motion).
    var now: int = Time.get_ticks_msec()
    if now - _last_navigation_ms < NAV_DEBOUNCE_MS:
        return false
    _last_navigation_ms = now
    return true

func _move_selection(amount: int) -> void:
    if not _can_navigate():
        return
    var fields: Array = APPEARANCE_FIELDS if _page == 0 else CLOTHING_FIELDS
    if fields.is_empty():
        return
    _selected_index = posmod(_selected_index + amount, fields.size())
    _update_row_highlight()
    _reveal_selected_row()

func _adjust_selected(direction: int) -> void:
    if not _can_navigate():
        return
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
        _last_navigation_ms = -10000
        # Re-arm both sticks only on opening the menu.
        _joy_axis_direction.clear()
        _right_stick_latched.clear()
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

    # Six clothing fields do not fit at a readable size. Only the left
    # field list scrolls, while the right-side portrait stays fixed.
    _row_scroll = ScrollContainer.new()
    _row_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _row_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _row_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    _row_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
    stack.add_child(_row_scroll)

    _rows = VBoxContainer.new()
    _rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _rows.add_theme_constant_override("separation", 2)
    _row_scroll.add_child(_rows)

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
    # Gamepad selection is owned by _input(), not GUI focus traversal.
    # Mouse/touch button clicks still work normally.
    button.focus_mode = Control.FOCUS_NONE
    button.add_theme_font_size_override("font_size", 11)
    if _ui_font != null:
        button.add_theme_font_override("font", _ui_font)
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
    if _ui_font != null:
        label.add_theme_font_override("font", _ui_font)
    label.add_theme_color_override("font_color", Color("#f0f1ed"))
    label.clip_text = true
    return label

func _set_page(next_page: int) -> void:
    _page = next_page
    _selected_index = 0
    _row_scroll.scroll_vertical = 0
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

        # Each property gets its own full-width label and selector row.
        var field_box := VBoxContainer.new()
        field_box.custom_minimum_size.y = 35
        field_box.add_theme_constant_override("separation", 1)
        _rows.add_child(field_box)

        var name_label := _label(11)
        name_label.text = _tr("field." + key)
        name_label.custom_minimum_size.y = 13
        field_box.add_child(name_label)
        _row_labels.append(name_label)

        var choice_row := HBoxContainer.new()
        choice_row.custom_minimum_size.y = 21
        choice_row.add_theme_constant_override("separation", 2)
        field_box.add_child(choice_row)

        var previous := _button()
        previous.text = _tr("ui.previous")
        previous.custom_minimum_size = Vector2(22, 21)
        previous.disabled = not avatar.has_lpc_character()
        choice_row.add_child(previous)
        previous.pressed.connect(_adjust.bind(key, -1, index))

        var value_label := _label(11)
        value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        value_label.text = _localized_value(key)
        choice_row.add_child(value_label)
        _value_labels[key] = value_label
        _row_values.append(value_label)

        var following := _button()
        following.text = _tr("ui.next")
        following.custom_minimum_size = Vector2(22, 21)
        following.disabled = not avatar.has_lpc_character()
        choice_row.add_child(following)
        following.pressed.connect(_adjust.bind(key, 1, index))

    _update_row_highlight()
    _reveal_selected_row()

func _reveal_selected_row() -> void:
    # ScrollContainer can reveal newly created children only after layout.
    var intended_index: int = _selected_index
    await get_tree().process_frame
    if not _opened or not is_instance_valid(_row_scroll) or not is_instance_valid(_rows):
        return
    if intended_index != _selected_index:
        return
    if intended_index >= 0 and intended_index < _rows.get_child_count():
        _row_scroll.ensure_control_visible(_rows.get_child(intended_index) as Control)

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
        _reveal_selected_row()
    if avatar.change_lpc_option(key, direction):
        _refresh_options()
