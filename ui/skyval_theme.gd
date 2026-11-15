extends RefCounted
## Shared 320x240 Skyval window palette and chrome.
## All windows use the same navy translucent panels, warm gold borders
## and 14px+ high-contrast typography; no extra textures are required.
## Each call creates an independent StyleBox (never mutate shared objects).

const GOLD := Color("#e7ca86")
const LIGHT_GOLD := Color("#f9e3af")
const INK := Color("#f0f1ed")
const MUTED := Color("#c5cbd0")
const DISABLED := Color("#909ca9")


static func panel_style(opacity: float = 0.90, inset: float = 7.0) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.055, 0.085, 0.14, opacity)
    style.border_color = Color("#d6b77c")
    style.set_border_width_all(1)
    style.set_corner_radius_all(3)
    style.set_content_margin_all(inset)
    return style


static func item_style(selected: bool = false, disabled: bool = false, inset: float = 3.0) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    if disabled:
        style.bg_color = Color(0.08, 0.11, 0.17, 0.68)
        style.border_color = Color(0.36, 0.41, 0.47, 0.57)
    else:
        style.bg_color = Color(0.18, 0.26, 0.38, 0.88) if selected else Color(0.08, 0.13, 0.20, 0.74)
        style.border_color = GOLD if selected else Color(0.40, 0.49, 0.58, 0.66)
    style.set_border_width_all(1)
    style.set_corner_radius_all(2)
    style.set_content_margin_all(inset)
    return style


static func apply_button(button: Button, selected: bool = false, disabled: bool = false, inset: float = 3.0) -> void:
    var normal: StyleBoxFlat = item_style(selected, disabled, inset)
    var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
    var pressed: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
    hover.bg_color = Color(0.27, 0.37, 0.49, 0.95) if not disabled else normal.bg_color
    pressed.bg_color = Color(0.34, 0.44, 0.56, 0.96) if not disabled else normal.bg_color
    button.add_theme_stylebox_override("normal", normal)
    button.add_theme_stylebox_override("hover", hover)
    button.add_theme_stylebox_override("pressed", pressed)
    button.add_theme_stylebox_override("disabled", item_style(false, true, inset))
    var ink: Color = GOLD if selected and not disabled else INK
    button.add_theme_color_override("font_color", ink)
    button.add_theme_color_override("font_hover_color", ink)
    button.add_theme_color_override("font_pressed_color", ink)
    button.add_theme_color_override("font_focus_color", ink)
    button.add_theme_color_override("font_disabled_color", DISABLED)
