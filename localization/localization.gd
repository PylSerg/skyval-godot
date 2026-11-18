extends Node
## Skyval language and gamepad-layout preferences. Shared by every UI scene.
## Button captions always show the Nintendo action letters A/B/X/Y.
## Physical input is normalized in SkyvalInput, not in UI scenes.

signal language_changed
signal layout_changed

const STRINGS_PATH := "res://localization/strings.json"
const SETTINGS_PATH := "user://skyval_settings.cfg"
const DEFAULT_LANGUAGE := "uk"
const DEFAULT_INPUT_LAYOUT := "nintendo"
const VALID_INPUT_LAYOUTS := ["standard", "nintendo"]

var language: String = DEFAULT_LANGUAGE
var input_layout: String = DEFAULT_INPUT_LAYOUT
var _translations: Dictionary = {}


func _ready() -> void:
    var raw: String = FileAccess.get_file_as_string(STRINGS_PATH)
    var data: Variant = JSON.parse_string(raw)
    if typeof(data) == TYPE_DICTIONARY:
        _translations = data
    else:
        push_error("Skyval localization: invalid or missing strings.json")
        return

    var settings := ConfigFile.new()
    if settings.load(SETTINGS_PATH) == OK:
        var saved_language: String = str(settings.get_value("general", "language", DEFAULT_LANGUAGE))
        if _translations.has(saved_language):
            language = saved_language
        var saved_layout: String = str(settings.get_value("general", "input_layout", DEFAULT_INPUT_LAYOUT))
        if VALID_INPUT_LAYOUTS.has(saved_layout):
            input_layout = saved_layout


func t(key: String) -> String:
    var active: Dictionary = _translations.get(language, {})
    if active.has(key):
        return str(active[key])
    var fallback: Dictionary = _translations.get(DEFAULT_LANGUAGE, {})
    return str(fallback.get(key, key))


func _save_preferences() -> void:
    # Preserve all existing unrelated settings, unlike replacing the
    # entire config with a new general section on each language change.
    var settings := ConfigFile.new()
    settings.load(SETTINGS_PATH)
    settings.set_value("general", "language", language)
    settings.set_value("general", "input_layout", input_layout)
    var result: Error = settings.save(SETTINGS_PATH)
    if result != OK:
        push_warning("Skyval preferences: language/layout could not be saved.")


func set_language(next_language: String) -> void:
    if not _translations.has(next_language) or next_language == language:
        return
    language = next_language
    _save_preferences()
    language_changed.emit()


func toggle_language() -> void:
    set_language("en" if language == "uk" else "uk")


func set_input_layout(next_layout: String) -> void:
    if not VALID_INPUT_LAYOUTS.has(next_layout) or next_layout == input_layout:
        return
    input_layout = next_layout
    _save_preferences()
    layout_changed.emit()


