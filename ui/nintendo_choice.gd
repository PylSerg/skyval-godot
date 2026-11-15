extends HBoxContainer
## Controller-action hint for a 320x240 UI.
## The A/B/X/Y badge uses the Super Famicom/Nintendo button colors:
## A red, B yellow, X blue, Y green. Neither row is highlighted.
## A large invisible hit area makes the text clickable without a button box.

signal activated

const FONT_SIZE := 14
const ICON_SIZE := 20.0
const BUTTON_COLORS := {
    "A": Color("#dd4a4a"),
    "B": Color("#e8c74e"),
    "X": Color("#4285cd"),
    "Y": Color("#47a764"),
}

var _letter: String = "A"
var _caption_text: String = ""
var _compact: bool = false
var _font: Font
var _caption: Label


func configure(letter: String, caption: String, font: Font = null, compact: bool = false) -> void:
    _letter = letter.to_upper()
    _caption_text = caption
    _font = font
    _compact = compact
    if is_node_ready():
        _update_content()


func set_caption(caption: String) -> void:
    _caption_text = caption
    if is_instance_valid(_caption):
        _caption.text = caption


func _ready() -> void:
    # Compact chips fit multiple hints on a single 320x240 row.
    # Only full-sized confirmation rows are clickable.
    mouse_filter = Control.MOUSE_FILTER_IGNORE if _compact else Control.MOUSE_FILTER_STOP
    size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if _compact else Control.SIZE_EXPAND_FILL
    custom_minimum_size.y = 18.0 if _compact else 23.0
    add_theme_constant_override("separation", 2 if _compact else 6)
    var circle_size: float = 17.0 if _compact else ICON_SIZE

    var icon := PanelContainer.new()
    icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    icon.custom_minimum_size = Vector2(circle_size, circle_size)
    icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER

    var circle := StyleBoxFlat.new()
    circle.bg_color = BUTTON_COLORS.get(_letter, Color("#7c879b"))
    circle.set_corner_radius_all(int(ceilf(circle_size / 2.0)))
    circle.set_content_margin_all(0.0)
    icon.add_theme_stylebox_override("panel", circle)
    add_child(icon)

    var letter_label := Label.new()
    letter_label.text = _letter
    letter_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    letter_label.custom_minimum_size = Vector2(circle_size, circle_size)
    letter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    letter_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    letter_label.add_theme_font_size_override("font_size", FONT_SIZE)
    letter_label.add_theme_color_override("font_color", Color("#243046") if _letter == "B" else Color.WHITE)
    if _font != null:
        letter_label.add_theme_font_override("font", _font)
    icon.add_child(letter_label)

    _caption = Label.new()
    _caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _caption.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if _compact else Control.SIZE_EXPAND_FILL
    _caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    _caption.clip_text = not _compact
    _caption.add_theme_font_size_override("font_size", FONT_SIZE)
    _caption.add_theme_color_override("font_color", Color("#f0f1ed"))
    if _font != null:
        _caption.add_theme_font_override("font", _font)
    add_child(_caption)

    _update_content()


func _update_content() -> void:
    if is_instance_valid(_caption):
        _caption.text = _caption_text


func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        var click: InputEventMouseButton = event as InputEventMouseButton
        if click.button_index == MOUSE_BUTTON_LEFT and click.pressed:
            activated.emit()
            accept_event()
