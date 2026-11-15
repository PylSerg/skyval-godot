extends VBoxContainer
## Turns localized "A: Action  X: Action" text into compact Nintendo badges.
## Preserves explicit newlines (notably the two name-entry hint rows).
## Plain error/status text without button prefixes remains readable text.
## These are informative, unhighlighted hints, not menu selection controls.

const ChoiceScript = preload("res://ui/nintendo_choice.gd")
const FONT_SIZE := 14

var _hint: String = ""
var _font: Font
var _centered: bool = true
var _pattern: RegEx


func configure(hint: String, font: Font = null, centered: bool = true) -> void:
    _hint = hint
    _font = font
    _centered = centered
    if is_node_ready():
        _rebuild()


func set_hint(hint: String) -> void:
    if _hint == hint:
        return
    _hint = hint
    if is_node_ready():
        _rebuild()


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    add_theme_constant_override("separation", 0)
    _pattern = RegEx.new()
    _pattern.compile("([ABXY]):[ \\t]*")
    _rebuild()


func _rebuild() -> void:
    for child in get_children():
        remove_child(child)
        child.queue_free()

    for line in _hint.split("\n", true):
        var row := HBoxContainer.new()
        row.mouse_filter = Control.MOUSE_FILTER_IGNORE
        row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.custom_minimum_size.y = 18
        row.alignment = BoxContainer.ALIGNMENT_CENTER if _centered else BoxContainer.ALIGNMENT_BEGIN
        row.add_theme_constant_override("separation", 4)
        add_child(row)

        var matches: Array[RegExMatch] = _pattern.search_all(line)
        if matches.is_empty():
            var plain := _label(line)
            plain.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            plain.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if _centered else HORIZONTAL_ALIGNMENT_LEFT
            plain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
            row.add_child(plain)
            continue

        var prefix: String = line.substr(0, matches[0].get_start()).strip_edges()
        if not prefix.is_empty():
            row.add_child(_label(prefix))
        for index in range(matches.size()):
            var entry: RegExMatch = matches[index]
            var finish: int = matches[index + 1].get_start() if index + 1 < matches.size() else line.length()
            var caption: String = line.substr(entry.get_end(), finish - entry.get_end()).strip_edges()
            var item: Control = ChoiceScript.new() as Control
            item.call("configure", entry.get_string(1), caption, _font, true)
            row.add_child(item)


func _label(value: String) -> Label:
    var label := Label.new()
    label.text = value
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.add_theme_font_size_override("font_size", FONT_SIZE)
    label.add_theme_color_override("font_color", Color("#f0f1ed"))
    if _font != null:
        label.add_theme_font_override("font", _font)
    return label
