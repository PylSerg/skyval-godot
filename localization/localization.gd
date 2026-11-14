extends Node
## Skyval localization service.
## Every displayed string is read from res://localization/strings.json.
## Add new languages to that JSON; no menu source changes are required.

signal language_changed

const STRINGS_PATH := "res://localization/strings.json"
const SETTINGS_PATH := "user://skyval_settings.cfg"
const DEFAULT_LANGUAGE := "uk"

var language: String = DEFAULT_LANGUAGE
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
        var saved: String = str(settings.get_value("general", "language", DEFAULT_LANGUAGE))
        if _translations.has(saved):
            language = saved

func t(key: String) -> String:
    var active: Dictionary = _translations.get(language, {})
    if active.has(key):
        return str(active[key])
    var fallback: Dictionary = _translations.get(DEFAULT_LANGUAGE, {})
    return str(fallback.get(key, key))

func set_language(next_language: String) -> void:
    if not _translations.has(next_language) or next_language == language:
        return
    language = next_language
    var settings := ConfigFile.new()
    settings.set_value("general", "language", language)
    var result: Error = settings.save(SETTINGS_PATH)
    if result != OK:
        push_warning("Skyval localization: language preference was not saved.")
    language_changed.emit()

func toggle_language() -> void:
    set_language("en" if language == "uk" else "uk")
