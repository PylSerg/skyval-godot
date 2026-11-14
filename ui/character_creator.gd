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

@onready var avatar: SkyvalCharacterVisual = get_parent().get_node("Player/CharacterVisual") as SkyvalCharacterVisual

var _opened: bool = false
var _page: int = 0
var _selected_index: int = 0
var _row_labels: Array[Label] = []
var _row_values: Array[Label] = []
var _last_press_by_key: Dictionary = {}
var _root: Control
var _title: Label
var _tab_appearance: Button
var _tab_clothes: Button
var _language_button: Button
var _close_button: Button
var _rows: VBoxContainer
var _footer: Label
var _preview_title: Label
var _preview: Control
var _missing_label: Label
var _wardrobe_button: Button
var _value_labels: Dictionary = {}
var _locale: Node

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS

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

# Handle navigation BEFORE built-in GUI key/joy focus routing. Otherwise an
# emulated D-pad plus native gamepad can navigate the UI twice.
func _input(event: InputEvent) -> void:
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

    if key != KEY_C and key != KEY_ESCAPE and key != KEY_UP and key != KEY_DOWN and key != KEY_LEFT and key != KEY_RIGHT and key != KEY_ENTER and key != KEY_KP_ENTER and key != KEY_SPACE and key != KEY_Q and key != KEY_E and key != KEY_TAB and key != KEY_T and key != KEY_R:
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
        KEY_T:
            _locale.call("toggle_language")
        KEY_R:
            _toggle_all_clothes()

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

    var header := HBoxContainer.new()
    header.add_theme_constant_override("separation", 2)
    stack.add_child(header)

    _title = _label(11)
    _title.custom_minimum_size.x = 107
    _title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(_title)

    _language_button = _button()
    _language_button.custom_minimum_size = Vector2(32, 19)
    header.add_child(_language_button)
    _language_button.pressed.connect(func() -> void:
        _locale.call("toggle_language")
    )

    _close_button = _button()
    _close_button.custom_minimum_size = Vector2(35, 19)
    header.add_child(_close_button)
    _close_button.pressed.connect(func() -> void:
        _set_open(false)
    )

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

    _footer = _label(9)
    _footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    stack.add_child(_footer)

    _preview_title = _label(10)
    _preview_title.position = Vector2(212, 10)
    _preview_title.size = Vector2(104, 16)
    _preview_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _root.add_child(_preview_title)

    _preview = PreviewScript.new() as Control
    _preview.position = Vector2(212, 30)
    _preview.size = Vector2(103, 191)
    _root.add_child(_preview)

    _missing_label = _label(9)
    _missing_label.position = Vector2(214, 164)
    _missing_label.size = Vector2(99, 45)
    _missing_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _missing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _root.add_child(_missing_label)

    # The bottom of the preview has 19 free logical pixels at 320x240.
    # Keep this action outside the dense six-row clothing form.
    _wardrobe_button = _button()
    _wardrobe_button.position = Vector2(212, 222)
    _wardrobe_button.size = Vector2(103, 16)
    _wardrobe_button.add_theme_font_size_override("font_size", 9)
    _root.add_child(_wardrobe_button)
    _wardrobe_button.pressed.connect(_toggle_all_clothes)

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
    if _title == null:
        return
    _title.text = _tr("ui.title")
    _tab_appearance.text = _tr("ui.appearance")
    _tab_clothes.text = _tr("ui.clothes")
    _language_button.text = _tr("ui.language_" + str(_locale.get("language")))
    _close_button.text = _tr("ui.close")
    _footer.text = _tr("ui.close_hint")
    _preview_title.text = _tr("ui.preview")
    _missing_label.text = _tr("ui.missing_lpc")
    _missing_label.visible = not avatar.has_lpc_character()
    _preview.set("character", avatar.get_lpc_character())
    _preview.queue_redraw()
    _refresh_wardrobe_button()
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

func _refresh_wardrobe_button() -> void:
    if _wardrobe_button == null:
        return
    _wardrobe_button.disabled = not avatar.has_lpc_character()
    _wardrobe_button.text = _tr("ui.restore_outfit") if avatar.is_lpc_fully_undressed() else _tr("ui.remove_all")

func _refresh_options() -> void:
    # Refresh live labels rather than rebuilding rows, preserving button focus.
    for option_key in _value_labels.keys():
        var field_label: Label = _value_labels[option_key] as Label
        if is_instance_valid(field_label):
            field_label.text = _localized_value(str(option_key))
    _refresh_wardrobe_button()
    _preview.queue_redraw()

func _toggle_all_clothes() -> void:
    if avatar.toggle_lpc_all_clothes():
        _refresh_options()

func _adjust(key: String, direction: int, index: int = -1) -> void:
    if index >= 0:
        _selected_index = index
        _update_row_highlight()
    if avatar.change_lpc_option(key, direction):
        _refresh_options()
