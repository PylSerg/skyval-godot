extends CanvasLayer
## Shared character UI: tabbed backpack plus standalone appearance creation.
## Text lives exclusively in localization/strings.json.

const PreviewScript = preload("res://ui/character_preview.gd")
const LocaleScript = preload("res://localization/localization.gd")
const UiTheme = preload("res://ui/skyval_theme.gd")
const ControllerChoiceScript = preload("res://ui/nintendo_choice.gd")
const APPEARANCE_BG_PATH := "res://assets/images/create_hero_bg.jpg"
const APPEARANCE_FIELDS := ["body_type", "skin_variant", "eye_variant", "hair_style", "hair_variant"]
# Both equipment categories share the same five body areas. Empty
# categories are shown as None until their items are actually earned.
const CLOTHING_FIELDS := [
    "clothes_head", "clothes_top", "clothes_bottom",
    "clothes_hands", "clothes_feet",
]
const ARMOR_FIELDS := [
    "armor_head", "armor_top", "armor_bottom",
    "armor_hands", "armor_feet",
]
const BACKPACK_TABS := ["ui.clothes", "inventory.tab.armor", "inventory.tab.weapons"]
const TAB_SLIDE_SECONDS := 0.18
const TAB_HORIZONTAL_PADDING := 8
# Use only native joypad buttons and axes; avoid GUI double input.
const NAV_DEBOUNCE_MS := 100
const LEFT_STICK_PRESS := 0.65
const LEFT_STICK_RELEASE := 0.42
const RIGHT_STICK_PRESS := 0.65
const RIGHT_STICK_RELEASE := 0.35

# Shared across the standalone Appearance window and all backpack tabs
# to preserve the small-screen insets and row spacing.
const MIN_UI_FONT_SIZE := 14
const ACTIVE_HIGHLIGHT := Color("#e7ca86")
const PANEL_INSET := 7
const FIELD_GROUP_SPACING := 12
const FIELD_CONTENT_PADDING := FIELD_GROUP_SPACING
const FIELD_INNER_SPACING := 5
# Compact chevrons preserve the 14px minimum glyph size and free 16px
# of horizontal space for long item names in the 320px layout.
const SELECTOR_ARROW_WIDTH := 14.0
const SELECTOR_ARROW_GAP := 2.0
# This script is instantiated twice: the tabbed backpack in the scene,
# and appearance as an independent, reusable window.
@export var appearance_window: bool = false

signal confirmed
signal cancelled

@onready var avatar: SkyvalCharacterVisual = get_parent().get_node("Player/CharacterVisual") as SkyvalCharacterVisual

var _opened: bool = false
var _creation_mode: bool = false
var _confirmation_open: bool = false
var _edit_snapshot: Dictionary = {}
var _selected_index: int = 0
var _active_tab: int = 0
var _tab_scroll: ScrollContainer
var _tab_buttons: Array[Button] = []
var _page_tween: Tween
var _row_labels: Array[Label] = []
var _row_panels: Array[PanelContainer] = []
var _row_values: Array[Label] = []
var _row_counters: Dictionary = {}
# Inventory only: candidate item per field. Browsing does not equip it.
var _equipment_preview: Dictionary = {}
# Temporary LPC appearance for visual try-on; inventory stays untouched
# until A confirms. Never let a trial outfit enter a save checkpoint.
var _try_on_original_lpc: Dictionary = {}
var _try_on_visual_key: String = ""
var _row_scroll: ScrollContainer
var _page_clip: Control
var _action_hint: Label
var _confirmation_overlay: Control
var _confirmation_message: Label
var _confirmation_accept: Control
var _confirmation_cancel: Control
var _ui_font: FontFile
var _held_joy_buttons: Dictionary = {}
var _joy_axis_direction: Dictionary = {}
var _right_stick_latched: Dictionary = {}
var _last_navigation_ms: int = -10000
var _ignore_presses_before_ms: int = 0
var _root: Control
var _appearance_bg: TextureRect
var _compact_choice_panel: PanelContainer
var _compact_choice_window: Control
var _compact_choice_value: Label
var _compact_prev: Button
var _compact_next: Button
var _equip_hint: Label
var _title_label: Label
var _rows: VBoxContainer
var _preview: Control
var _preview_refresh_pending: bool = false
var _backpack_open_generation: int = 0
var _armor_class_label: Label
var _armor_value_label: Label
var _missing_label: Label
var _value_labels: Dictionary = {}
var _value_windows: Dictionary = {}
var _value_marquees: Dictionary = {}
var _inventory: Node
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
    _inventory = get_node_or_null("/root/SkyvalInventory")
    if _inventory != null:
        _inventory.connect("changed", Callable(self, "_on_inventory_changed"))
    _build_interface()
    _root.hide()

func _tr(key: String) -> String:
    return str(_locale.call("t", key))

func _load_cascadia_font() -> void:
    # Project-local copy works in the exported PortMaster PCK.
    # In the desktop checkout, reuse the user's external asset library.
    var bundled_path: String = "res://assets/fonts/CascadiaMono-Regular.ttf"
    if ResourceLoader.exists(bundled_path):
        _ui_font = load(bundled_path) as FontFile
        if _ui_font != null:
            _ui_font = _ui_font.duplicate() as FontFile

    if _ui_font == null:
        var home: String = OS.get_environment("HOME")
        var candidates: PackedStringArray = [
            home.path_join("Downloads/Cascadia_Mono/static/CascadiaMono-Regular.ttf"),
            home.path_join("Cascadia_Mono/static/CascadiaMono-Regular.ttf"),
            home.path_join("Godot/res/assets/fonts/CascadiaMono-Regular.ttf"),
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
        # Cascadia Mono is a vector font, not a bitmap pixel font.
        # Render glyph edges in grayscale at the 320x240 logical viewport.
        # Without antialiasing, 2x integer scaling turns diagonal edges into
        # heavy staircase pixels. Keep normal hinting for small-text clarity.
        _ui_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
        _ui_font.hinting = TextServer.HINTING_NORMAL
        _ui_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
        _ui_font.force_autohinter = false

        # Only use a Cyrillic fallback when a concrete font lacks Ukrainian.
        # Static Cascadia Mono can render Ukrainian itself if it has the glyphs.
        var has_ukrainian: bool = true
        var supported_chars: String = _ui_font.get_supported_chars()
        for letter in ["і", "ї", "є", "ґ", "І", "Ї", "Є", "Ґ"]:
            if not supported_chars.contains(letter):
                has_ukrainian = false
                break
        var fallback: Font = ThemeDB.fallback_font
        if fallback != null and not has_ukrainian:
            var fallback_copy: Font = fallback.duplicate() as Font
            if fallback_copy is FontFile:
                var fallback_file: FontFile = fallback_copy as FontFile
                fallback_file.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
                fallback_file.hinting = TextServer.HINTING_NORMAL
                fallback_file.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
            _ui_font.fallbacks = [fallback_copy]
            push_warning("Skyval UI: Cascadia Mono lacks some Ukrainian glyphs; using a built-in fallback.")
        print("Skyval UI: Cascadia Mono ready, Ukrainian glyphs=", has_ukrainian)
    else:
        push_warning("Skyval UI: CascadiaMono-Regular.ttf not found; using Godot default font.")

# Capture native gamepad input before Godot GUI focus routing.
# Keyboard events are deliberately ignored by all gameplay menus.
func _input(event: InputEvent) -> void:
    if appearance_window and not _opened:
        return
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
    if _opened and Time.get_ticks_msec() < _ignore_presses_before_ms:
        return

    if not _opened:
        # Wardrobe is available only during gameplay, never over startup
        # menus or a standalone appearance creation session.
        if not appearance_window and (event.button_index == JOY_BUTTON_BACK or event.button_index == JOY_BUTTON_LEFT_STICK):
            var game_menu: Node = get_parent().get_node_or_null("GameMenu")
            var appearance_editor: Node = get_parent().get_node_or_null("AppearanceEditor")
            if game_menu != null and (bool(game_menu.call("is_open")) or not bool(game_menu.call("has_started_session"))):
                return
            if appearance_editor != null and bool(appearance_editor.call("is_open")):
                return
            for chest_name in ["TestChest", "ArmorChest"]:
                var chest: Node = get_parent().get_node_or_null(chest_name)
                if chest != null and bool(chest.call("is_open")):
                    return
            _set_open(true)
            get_viewport().set_input_as_handled()
        return

    if appearance_window and _confirmation_open:
        # Appearance edits retain their own optional confirmation.
        # New-character creation advances directly with X, never A.
        if not _creation_mode:
            match event.button_index:
                JOY_BUTTON_A:
                    _accept_appearance()
                JOY_BUTTON_B:
                    _dismiss_confirmation()
        else:
            _dismiss_confirmation()
        get_viewport().set_input_as_handled()
        return

    # Start/R3 belongs to GameMenu, except while creating a new character.
    if event.button_index == JOY_BUTTON_START or event.button_index == JOY_BUTTON_RIGHT_STICK:
        return

    match event.button_index:
        JOY_BUTTON_BACK, JOY_BUTTON_LEFT_STICK:
            if not appearance_window:
                _set_open(false)
            else:
                return
        JOY_BUTTON_B:
            if appearance_window:
                _cancel_appearance()
            else:
                _set_open(false)
        JOY_BUTTON_A:
            # A deliberately has no function in appearance creation.
            # In the inventory it still confirms the highlighted gear.
            if not appearance_window:
                _confirm_equipment_selection()
        JOY_BUTTON_X:
            if appearance_window:
                if _creation_mode:
                    _accept_appearance()
                else:
                    _show_confirmation()
        JOY_BUTTON_Y:
            if appearance_window and _creation_mode:
                _randomize_appearance()
        JOY_BUTTON_LEFT_SHOULDER:
            if not appearance_window:
                _set_tab(_active_tab - 1)
        JOY_BUTTON_RIGHT_SHOULDER:
            if not appearance_window:
                _set_tab(_active_tab + 1)
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
    if appearance_window and _confirmation_open:
        get_viewport().set_input_as_handled()
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
    var option_count: int = _current_fields().size()
    if option_count == 0:
        return
    # Row navigation is bounded. Cyclic movement belongs only to item
    # variants inside gear selectors, not to menus or parameter lists.
    var next_index: int = clampi(_selected_index + amount, 0, option_count - 1)
    if next_index == _selected_index:
        return
    _selected_index = next_index
    _update_row_highlight()
    _update_compact_choice()
    _reveal_selected_row()

func _adjust_selected(direction: int) -> void:
    if not _can_navigate():
        return
    var fields: Array = _current_fields()
    if _selected_index < 0 or _selected_index >= fields.size():
        return
    if appearance_window:
        _adjust(str(fields[_selected_index]), direction, _selected_index)
    else:
        # D-pad, left stick and on-screen arrows only browse candidates.
        _browse_equipment(direction)

func _selected_equipment_id(field: String) -> String:
    if _inventory == null:
        return ""
    var options: Array[String] = _inventory.call("get_equipment_choices", field)
    var slot: String = str(_inventory.call("get_equipment_slot", field))
    var equipped_id: String = str(_inventory.call("get_equipped", slot))
    var candidate_id: String = str(_equipment_preview.get(field, equipped_id))
    if not options.has(candidate_id):
        candidate_id = equipped_id if options.has(equipped_id) else ""
    _equipment_preview[field] = candidate_id
    return candidate_id


func _browse_equipment(direction: int) -> void:
    if _inventory == null or appearance_window:
        return
    var fields: Array = _current_fields()
    if _selected_index < 0 or _selected_index >= fields.size():
        return
    var field: String = str(fields[_selected_index])
    var options: Array[String] = _inventory.call("get_equipment_choices", field)
    if options.size() <= 1:
        return

    var current: String = _selected_equipment_id(field)
    var index: int = options.find(current)
    if index < 0:
        index = 0
    var next_index: int = posmod(index + (1 if direction >= 0 else -1), options.size())
    _equipment_preview[field] = options[next_index]
    var counter: Label = _row_counters.get(field) as Label
    if is_instance_valid(counter):
        counter.text = _field_counter(field)
    _update_compact_choice()


func _restore_equipment_try_on() -> void:
    if _try_on_original_lpc.is_empty():
        return
    var lpc: Node2D = avatar.get_lpc_character()
    if lpc != null:
        if not bool(lpc.call("apply_appearance_state", _try_on_original_lpc)):
            push_warning("Skyval: couldn't restore the original outfit after preview.")
    _try_on_original_lpc.clear()
    _try_on_visual_key = ""
    if is_instance_valid(_preview) and _preview.has_method("clear_frame_cache"):
        _preview.call("clear_frame_cache")


func _preview_equipment_on_character(field: String) -> void:
    if appearance_window or _inventory == null or not avatar.has_lpc_character():
        return
    var slot: String = str(_inventory.call("get_equipment_slot", field))
    var candidate_id: String = _selected_equipment_id(field)
    var actual_id: String = str(_inventory.call("get_equipped", slot))
    if slot.is_empty() or candidate_id == actual_id:
        _restore_equipment_try_on()
        return

    var item: Dictionary = _inventory.call("get_item", candidate_id)
    # Unknown or unsupported equipment locations have no LPC layer yet.
    if not candidate_id.is_empty() and item.is_empty():
        _restore_equipment_try_on()
        return
    if slot not in ["armor", "shirt", "pants", "footwear"]:
        _restore_equipment_try_on()
        return

    var lpc: Node2D = avatar.get_lpc_character()
    if lpc == null or not lpc.has_method("export_appearance_state"):
        return
    if _try_on_original_lpc.is_empty():
        _try_on_original_lpc = lpc.call("export_appearance_state")

    var key: String = "%s:%s" % [field, candidate_id]
    if key == _try_on_visual_key:
        return

    # Always build from the actual worn outfit, rather than accumulating
    # previous trial changes. This also restores the shirt when leaving
    # an armor preview without pressing A.
    var desired: Dictionary = _try_on_original_lpc.duplicate(true)
    var style: String = "none" if candidate_id.is_empty() else str(item.get("style", "none"))
    match slot:
        "armor":
            desired["armor_style"] = style
            if not candidate_id.is_empty():
                desired["shirt_style"] = "none"
        "shirt":
            desired["shirt_style"] = style
            if not candidate_id.is_empty():
                desired["shirt_variant"] = str(item.get("variant", desired.get("shirt_variant", "blue")))
                desired["armor_style"] = "none"
        "pants":
            desired["pants_style"] = style
            if not candidate_id.is_empty():
                desired["pants_variant"] = str(item.get("variant", desired.get("pants_variant", "charcoal")))
        "footwear":
            desired["footwear_style"] = style
            if not candidate_id.is_empty():
                desired["boots_variant"] = str(item.get("variant", desired.get("boots_variant", "brown")))

    # Rendering only: no InventoryState mutation, changed signal or save.
    # The LPC renderer validates all required atlas files before swapping
    # sprites, so a missing armor sheet won't corrupt the existing outfit.
    if not bool(lpc.call("apply_appearance_state", desired)):
        _restore_equipment_try_on()
        return
    _try_on_visual_key = key
    if is_instance_valid(_preview) and _preview.has_method("clear_frame_cache"):
        _preview.call("clear_frame_cache")


func _confirm_equipment_selection() -> void:
    if _inventory == null or appearance_window:
        return
    var fields: Array = _current_fields()
    if _selected_index < 0 or _selected_index >= fields.size():
        return
    var field: String = str(fields[_selected_index])
    var slot: String = str(_inventory.call("get_equipment_slot", field))
    if slot.is_empty():
        return

    var candidate_id: String = _selected_equipment_id(field)
    var equipped_id: String = str(_inventory.call("get_equipped", slot))
    if candidate_id == equipped_id:
        return
    # Restore the real LPC layers BEFORE invoking InventoryState.equip().
    # Otherwise a visual-only try-on could leak into a persisted outfit.
    _restore_equipment_try_on()
    # Ownership and LPC art are validated by InventoryState before
    # actually changing the character. Browsing alone never reaches here.
    var changed: bool = false
    if candidate_id.is_empty():
        changed = bool(_inventory.call("unequip", slot, avatar))
    else:
        changed = bool(_inventory.call("equip", candidate_id, avatar))
    if changed:
        # Equip/unequip refresh the live avatar and inventory only.
        # Progress is saved exclusively by the Save / Quick Save commands.
        _update_compact_choice()


func _update_row_highlight() -> void:
    # Highlight the complete field (name, counter and selector) by its
    # background, not by changing the name/value text color.
    for index in range(_row_panels.size()):
        var field_panel: PanelContainer = _row_panels[index]
        if not is_instance_valid(field_panel):
            continue
        var selected: bool = index == _selected_index
        var style := StyleBoxFlat.new()
        style.bg_color = Color(0.18, 0.26, 0.38, 0.78) if selected else Color(0.05, 0.08, 0.14, 0.19)
        style.border_color = ACTIVE_HIGHLIGHT if selected else Color(0, 0, 0, 0)
        style.set_border_width_all(1)
        style.set_corner_radius_all(2)
        # Compact rows free room for all five categories and their shared
        # selector; inventory and appearance use identical highlighting.
        style.set_content_margin_all(3)
        field_panel.add_theme_stylebox_override("panel", style)
        if index < _row_labels.size():
            var name: Label = _row_labels[index]
            if is_instance_valid(name):
                name.add_theme_color_override("font_color", ACTIVE_HIGHLIGHT if selected else Color("#f0f1ed"))


func _current_fields() -> Array:
    if appearance_window:
        return APPEARANCE_FIELDS
    if _active_tab == 0:
        return CLOTHING_FIELDS
    if _active_tab == 1:
        return ARMOR_FIELDS
    return []


func is_open() -> bool:
    return _opened


func begin_creation() -> void:
    if not appearance_window:
        return
    _creation_mode = true
    _edit_snapshot.clear()
    _selected_index = 0
    _set_open(true)


# The name-entry B action returns to the SAME unfinished creation
# draft. Do not reset the LPC appearance, counters, or selection, and do
# not allocate a profile or save until the character name is confirmed.
func resume_creation() -> void:
    if not appearance_window or _opened:
        return
    _creation_mode = true
    _confirmation_open = false
    _edit_snapshot.clear()
    _set_open(true)


func open_for_edit() -> void:
    # Public entrypoint for future NPC/dialogue or other character services.
    if not appearance_window or _opened:
        return
    var menu: Node = get_parent().get_node_or_null("GameMenu")
    var wardrobe: Node = get_parent().get_node_or_null("CharacterCreator")
    if menu != null and bool(menu.call("is_open")):
        return
    if wardrobe != null and bool(wardrobe.call("is_open")):
        return
    _creation_mode = false
    _edit_snapshot = avatar.get_save_state()
    _selected_index = 0
    _set_open(true)


func _randomize_appearance() -> void:
    # Generate the complete LPC appearance in one validated operation.
    # Randomization only affects the unsaved creation draft. The inventory
    # remains untouched unless we successfully apply a valid appearance.
    if not appearance_window or not _opened or not _creation_mode or not avatar.has_lpc_character():
        return
    var lpc: Node2D = avatar.get_lpc_character()
    if lpc == null or not lpc.has_method("apply_appearance_state"):
        return

    var original: Dictionary = lpc.call("export_appearance_state")
    for attempt in range(8):
        var candidate: Dictionary = original.duplicate(true)
        var changed: bool = false
        for field in APPEARANCE_FIELDS:
            var variants: Array[String] = avatar.get_lpc_option_choices(field)
            if variants.is_empty():
                continue
            var picked: String = variants.pick_random()
            if str(candidate.get(field, "")) != picked:
                changed = true
            candidate[field] = picked
        if not changed:
            continue

        # A different body type may need different clothing sprites.
        # Keep the same gender-based starting outfit as a new character.
        var candidate_body: String = str(candidate.get("body_type", "male"))
        candidate["shirt_style"] = "shortsleeve/tshirt" if candidate_body == "female" else "none"
        candidate["pants_style"] = "formal"
        candidate["footwear_style"] = "none"
        if bool(lpc.call("apply_appearance_state", candidate)):
            if _inventory != null:
                _inventory.call("set_starter_equipment", candidate_body)
            _refresh_options()
            return

    # Some handheld LPC packages contain only a subset of skins or hair
    # sprites. In that case, randomize a supported single field instead
    # of leaving Y entirely unresponsive.
    var fallback_fields: Array = APPEARANCE_FIELDS.duplicate()
    fallback_fields.shuffle()
    for field in fallback_fields:
        var direction: int = 1 if randi_range(0, 1) == 0 else -1
        if not avatar.change_lpc_option(str(field), direction):
            continue
        if field == "body_type":
            avatar.apply_starter_outfit()
            if _inventory != null:
                _inventory.call("set_starter_equipment", avatar.get_lpc_option("body_type"))
        _refresh_options()
        return
    push_warning("Skyval: no usable alternate LPC appearance found.")


func _accept_appearance() -> void:
    if not appearance_window or not _opened:
        return
    if not _creation_mode and not _confirmation_open:
        return
    _confirmation_open = false
    _confirmation_overlay.hide()
    confirmed.emit()
    _creation_mode = false
    _edit_snapshot.clear()
    _set_open(false)


func _cancel_appearance() -> void:
    if not appearance_window or not _opened:
        return
    _confirmation_open = false
    _confirmation_overlay.hide()
    if not _creation_mode and not _edit_snapshot.is_empty():
        avatar.apply_save_state(_edit_snapshot)
    # Emit while paused so the calling menu can claim pause ownership.
    cancelled.emit()
    _creation_mode = false
    _edit_snapshot.clear()
    _set_open(false)


func close_for_menu() -> void:
    # The global menu takes pause ownership before closing a sibling window.
    if not _opened:
        return
    if appearance_window:
        _cancel_appearance()
    else:
        _set_open(false)


func _set_open(next_open: bool) -> void:
    if _opened == next_open:
        return
    if not next_open and not appearance_window:
        # Restore trial sprites before returning to the world or opening
        # another menu. A preview must never become the live outfit.
        _restore_equipment_try_on()
    _opened = next_open
    # Invalidate any unfinished layout operation if the window closes
    # or reopens while the previous layout is being initialized.
    _backpack_open_generation += 1
    _confirmation_open = false
    if _confirmation_overlay != null:
        _confirmation_overlay.hide()
    _root.visible = next_open
    _set_ui_pause(next_open)
    if next_open:
        if not appearance_window:
            # Every opening of Backpack starts at Clothing / Head, even
            # after leaving while Armor or Weapons was selected.
            if _page_tween != null and _page_tween.is_valid():
                _page_tween.kill()
            _page_tween = null
            for old_page in _page_clip.get_children():
                if old_page != _row_scroll:
                    _page_clip.remove_child(old_page)
                    old_page.queue_free()
            _active_tab = 0
            _selected_index = 0
            _equipment_preview.clear()
            # Avoid showing the stale, wrongly sized first-page content
            # during the two short layout passes used for initialization.
            _page_clip.modulate.a = 0.0
            _row_scroll.position = Vector2.ZERO
            _row_scroll.scroll_vertical = 0
            if _tab_scroll != null:
                _tab_scroll.scroll_horizontal = 0
        _last_navigation_ms = -10000
        # Ignore the input event that launched this modal window.
        _ignore_presses_before_ms = Time.get_ticks_msec() + 150
        # Re-arm both sticks only on opening the menu.
        _joy_axis_direction.clear()
        _right_stick_latched.clear()
        _refresh_text()
        if _preview != null and _preview.has_method("clear_frame_cache"):
            _preview.call("clear_frame_cache")
        _update_row_highlight()
        if not appearance_window:
            _initialize_backpack_page_after_layout(_backpack_open_generation)
    else:
        # Infinite marquee tweens should not consume CPU while this
        # overlay is closed (especially on the R36H).
        _stop_value_marquees()
        get_viewport().gui_release_focus()


# The original backpack page is built while _root is hidden. At that
# point the VBox/ScrollContainer has no final width, so long labels can
# make its content overflow: the counter and right arrow disappear.
# New pages created by L1/R1 work because the parent has already laid
# out. Recreate the first page in exactly that stable state, one frame
# after making the window visible.
func _initialize_backpack_page_after_layout(generation: int) -> void:
    await get_tree().process_frame
    if not _opened or appearance_window or generation != _backpack_open_generation:
        return
    if _page_clip.size.x <= 0.0 or _page_clip.size.y <= 0.0:
        # Another layout pass may be necessary when opening after startup.
        await get_tree().process_frame
        if not _opened or generation != _backpack_open_generation:
            return

    var previous_page: ScrollContainer = _row_scroll
    if is_instance_valid(previous_page):
        _page_clip.remove_child(previous_page)
        previous_page.queue_free()

    _row_scroll = _create_page_scroll()
    _page_clip.add_child(_row_scroll)
    _row_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _row_scroll.position = Vector2.ZERO
    _active_tab = 0
    _selected_index = 0
    _refresh_text()

    # Scroll after the new field panels have received their actual width.
    await get_tree().process_frame
    if not _opened or generation != _backpack_open_generation:
        return
    _row_scroll.scroll_vertical = 0
    if _tab_scroll != null:
        _tab_scroll.scroll_horizontal = 0
    _page_clip.modulate.a = 1.0


func _set_ui_pause(should_pause: bool) -> void:
    var pause_manager: Node = get_node_or_null("/root/SkyvalUiPause")
    if pause_manager != null:
        pause_manager.call("set_open", self, should_pause)
    else:
        # Fallback for an editor that has not reloaded project.godot yet.
        get_tree().paused = should_pause


func _build_interface() -> void:
    _root = Control.new()
    _root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _root.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(_root)

    if appearance_window:
        _appearance_bg = TextureRect.new()
        _appearance_bg.name = "CreationBackground"
        _appearance_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        _appearance_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        _appearance_bg.stretch_mode = TextureRect.STRETCH_SCALE
        _appearance_bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
        _appearance_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
        if ResourceLoader.exists(APPEARANCE_BG_PATH):
            _appearance_bg.texture = load(APPEARANCE_BG_PATH) as Texture2D
        else:
            push_warning("Skyval: creation background not bundled: " + APPEARANCE_BG_PATH)
        _root.add_child(_appearance_bg)

    var shade := ColorRect.new()
    # Inventory overlays the paused game world. Do not replace it with
    # creation art or hide it under the old nearly opaque shade.
    if not appearance_window:
        shade.color = Color(0.02, 0.03, 0.07, 0.18)
    elif _appearance_bg.texture != null:
        shade.color = Color(0.02, 0.03, 0.07, 0.12)
    else:
        shade.color = Color(0.03, 0.08, 0.10, 0.76)
    shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _root.add_child(shade)

    var panel := PanelContainer.new()
    panel.position = Vector2(6, 6)
    panel.custom_minimum_size = Vector2(202, 228)
    panel.size = panel.custom_minimum_size
    _root.add_child(panel)
    # Keep the approved character/inventory proportions unchanged.
    var panel_style: StyleBoxFlat = UiTheme.panel_style(0.86, 6.0)
    panel.add_theme_stylebox_override("panel", panel_style)

    var stack := VBoxContainer.new()
    stack.add_theme_constant_override("separation", 4)
    panel.add_child(stack)

    # Appearance stays a standalone window. The backpack restores
    # its category strip with automatic horizontal scrolling.
    _title_label = _label(16)
    _title_label.custom_minimum_size.y = 23
    _title_label.add_theme_color_override("font_color", Color("#f9e3af"))
    _title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    # Backpack tabs identify the screen; the redundant "Рюкзак" header
    # would steal one full row on the tiny 320x240 viewport.
    _title_label.visible = appearance_window
    stack.add_child(_title_label)

    if appearance_window:
        # Always-visible instruction, outside the scrollable parameter list.
        _action_hint = _label(MIN_UI_FONT_SIZE)
        _action_hint.custom_minimum_size.y = 17
        _action_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        stack.add_child(_action_hint)

    if not appearance_window:
        _tab_scroll = ScrollContainer.new()
        _tab_scroll.custom_minimum_size.y = 25
        _tab_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
        _tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
        stack.add_child(_tab_scroll)

        var tabs := HBoxContainer.new()
        tabs.add_theme_constant_override("separation", 2)
        _tab_scroll.add_child(tabs)
        for index in range(BACKPACK_TABS.size()):
            var tab: Button = _button()
            tab.add_theme_font_size_override("font_size", MIN_UI_FONT_SIZE)
            tab.custom_minimum_size.y = 21
            tab.size_flags_horizontal = Control.SIZE_FILL
            tab.pressed.connect(_set_tab.bind(index))
            tabs.add_child(tab)
            _tab_buttons.append(tab)

    # Keep the scrollable single-column fields inside the left panel.
    _page_clip = Control.new()
    _page_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _page_clip.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _page_clip.clip_contents = true
    stack.add_child(_page_clip)

    _row_scroll = _create_page_scroll()
    _page_clip.add_child(_row_scroll)
    _row_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    # Both the creation editor and inventory use the same compact,
    # single-value selector, preserving room for five visible fields.
    _compact_choice_panel = PanelContainer.new()
    _compact_choice_panel.custom_minimum_size.y = 25
    var choice_style := StyleBoxFlat.new()
    choice_style.bg_color = Color(0.11, 0.17, 0.25, 0.84)
    choice_style.border_color = ACTIVE_HIGHLIGHT
    choice_style.set_border_width_all(1)
    choice_style.set_corner_radius_all(2)
    choice_style.set_content_margin_all(2)
    _compact_choice_panel.add_theme_stylebox_override("panel", choice_style)
    stack.add_child(_compact_choice_panel)

    var choice_row := HBoxContainer.new()
    choice_row.add_theme_constant_override("separation", 3)
    _compact_choice_panel.add_child(choice_row)

    _compact_prev = _selector_arrow_button()
    _compact_prev.text = _tr("ui.previous")
    _compact_prev.custom_minimum_size = Vector2(SELECTOR_ARROW_WIDTH, 20)
    _compact_prev.pressed.connect(_adjust_selected.bind(-1))
    choice_row.add_child(_compact_prev)

    _compact_choice_window = Control.new()
    _compact_choice_window.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _compact_choice_window.custom_minimum_size = Vector2(60, 20)
    _compact_choice_window.clip_contents = true
    _compact_choice_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
    choice_row.add_child(_compact_choice_window)

    _compact_choice_value = _label(MIN_UI_FONT_SIZE)
    _compact_choice_value.clip_text = false
    _compact_choice_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _compact_choice_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _compact_choice_window.add_child(_compact_choice_value)

    _compact_next = _selector_arrow_button()
    _compact_next.text = _tr("ui.next")
    _compact_next.custom_minimum_size = Vector2(SELECTOR_ARROW_WIDTH, 20)
    _compact_next.pressed.connect(_adjust_selected.bind(1))
    choice_row.add_child(_compact_next)

    if not appearance_window:
        _equip_hint = _label(MIN_UI_FONT_SIZE)
        _equip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _equip_hint.custom_minimum_size.y = 17
        _equip_hint.add_theme_color_override("font_color", Color("#d6b77c"))
        stack.add_child(_equip_hint)

    # Use the full right column; the portrait itself is drawn at 3×.
    _preview = PreviewScript.new() as Control
    _preview.position = Vector2(210, 8)
    _preview.size = Vector2(104, 224)
    _preview.set("scenic_mode", appearance_window)
    _preview.set("framed_mode", not appearance_window)
    _root.add_child(_preview)

    if not appearance_window:
        # Two status lines in the space below the raised portrait divider.
        _armor_class_label = _label(MIN_UI_FONT_SIZE)
        _armor_class_label.position = Vector2(1, 172)
        _armor_class_label.size = Vector2(101, 20)
        _armor_class_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _preview.add_child(_armor_class_label)

        _armor_value_label = _label(MIN_UI_FONT_SIZE)
        _armor_value_label.position = Vector2(1, 194)
        _armor_value_label.size = Vector2(101, 20)
        _armor_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _preview.add_child(_armor_value_label)

    _missing_label = _label(MIN_UI_FONT_SIZE)
    _missing_label.position = Vector2(211, 94)
    _missing_label.size = Vector2(102, 46)
    _missing_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _missing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _root.add_child(_missing_label)

    if appearance_window:
        _build_confirmation_overlay()

    _refresh_text()


func _set_tab(next_tab: int) -> void:
    if appearance_window or not _opened:
        return
    if next_tab < 0 or next_tab >= BACKPACK_TABS.size() or next_tab == _active_tab:
        return
    if _page_tween != null and _page_tween.is_running():
        return

    # A pending try-on belongs to the previous tab, not to the avatar.
    _restore_equipment_try_on()
    # Reuse the same field/portrait system. Only the left scroll page slides;
    # the 3x character preview never moves.
    var outgoing: ScrollContainer = _row_scroll
    var width: float = _page_clip.size.x
    var travel: float = -1.0 if next_tab > _active_tab else 1.0
    _active_tab = next_tab
    _selected_index = 0
    _equipment_preview.clear()

    _row_scroll = _create_page_scroll()
    _page_clip.add_child(_row_scroll)
    _row_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _refresh_text()

    if width <= 0.0:
        outgoing.queue_free()
        return
    _row_scroll.position.x = -travel * width
    _page_tween = create_tween()
    _page_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
    _page_tween.set_trans(Tween.TRANS_CUBIC)
    _page_tween.set_ease(Tween.EASE_OUT)
    _page_tween.tween_property(outgoing, "position:x", travel * width, TAB_SLIDE_SECONDS)
    _page_tween.parallel().tween_property(_row_scroll, "position:x", 0.0, TAB_SLIDE_SECONDS)
    _page_tween.finished.connect(outgoing.queue_free)


func _update_tab_styles() -> void:
    for index in range(_tab_buttons.size()):
        var tab: Button = _tab_buttons[index]
        var selected: bool = index == _active_tab
        var style := StyleBoxFlat.new()
        style.bg_color = Color(0.22, 0.31, 0.44, 0.90) if selected else Color(0.06, 0.10, 0.16, 0.68)
        style.border_color = ACTIVE_HIGHLIGHT if selected else Color("#72869a")
        style.set_border_width_all(1)
        style.set_content_margin_all(2)
        style.set_content_margin(SIDE_LEFT, TAB_HORIZONTAL_PADDING)
        style.set_content_margin(SIDE_RIGHT, TAB_HORIZONTAL_PADDING)
        tab.add_theme_stylebox_override("normal", style)
        var hover := style.duplicate() as StyleBoxFlat
        hover.bg_color = Color(0.29, 0.40, 0.53, 0.95) if selected else Color(0.16, 0.24, 0.34, 0.86)
        tab.add_theme_stylebox_override("hover", hover)
        var tab_text: Color = ACTIVE_HIGHLIGHT if selected else Color("#edf1f5")
        tab.add_theme_color_override("font_color", tab_text)
        tab.add_theme_color_override("font_hover_color", tab_text)
        tab.add_theme_color_override("font_pressed_color", tab_text)


func _reveal_active_tab() -> void:
    var intended_tab: int = _active_tab
    await get_tree().process_frame
    if appearance_window or _tab_scroll == null or intended_tab != _active_tab:
        return
    if intended_tab >= 0 and intended_tab < _tab_buttons.size():
        _tab_scroll.ensure_control_visible(_tab_buttons[intended_tab])




func _show_confirmation() -> void:
    if not appearance_window or not _opened or _confirmation_open or _creation_mode:
        return
    _confirmation_open = true
    _confirmation_message.text = _tr("ui.confirm_create_question") if _creation_mode else _tr("ui.confirm_edit_question")
    _confirmation_accept.call("set_caption", _tr("menu.confirm_accept"))
    _confirmation_cancel.call("set_caption", _tr("menu.confirm_cancel"))
    _confirmation_overlay.show()


func _dismiss_confirmation() -> void:
    _confirmation_open = false
    if _confirmation_overlay != null:
        _confirmation_overlay.hide()


func _build_confirmation_overlay() -> void:
    _confirmation_overlay = Control.new()
    _confirmation_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _confirmation_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    _root.add_child(_confirmation_overlay)

    var backdrop := ColorRect.new()
    backdrop.color = Color(0.02, 0.03, 0.07, 0.49)
    backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _confirmation_overlay.add_child(backdrop)

    var panel := PanelContainer.new()
    panel.position = Vector2(25, 40)
    panel.custom_minimum_size = Vector2(270, 160)
    panel.size = Vector2(270, 160)
    _confirmation_overlay.add_child(panel)

    panel.add_theme_stylebox_override("panel", UiTheme.panel_style(0.97, 8.0))

    var content := VBoxContainer.new()
    content.add_theme_constant_override("separation", 5)
    panel.add_child(content)

    _confirmation_message = _label(MIN_UI_FONT_SIZE)
    _confirmation_message.add_theme_color_override("font_color", UiTheme.LIGHT_GOLD)
    _confirmation_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _confirmation_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _confirmation_message.clip_text = false
    _confirmation_message.custom_minimum_size.y = 69
    content.add_child(_confirmation_message)

    var choices := VBoxContainer.new()
    choices.add_theme_constant_override("separation", 4)
    choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    content.add_child(choices)

    _confirmation_accept = ControllerChoiceScript.new() as Control
    _confirmation_accept.call("configure", "A", _tr("menu.confirm_accept"), _ui_font)
    _confirmation_accept.connect("activated", Callable(self, "_accept_appearance"))
    choices.add_child(_confirmation_accept)

    _confirmation_cancel = ControllerChoiceScript.new() as Control
    _confirmation_cancel.call("configure", "B", _tr("menu.confirm_cancel"), _ui_font)
    _confirmation_cancel.connect("activated", Callable(self, "_dismiss_confirmation"))
    choices.add_child(_confirmation_cancel)

    _confirmation_overlay.hide()

func _create_page_scroll() -> ScrollContainer:
    var scroll := ScrollContainer.new()
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    # Scrolling remains available, but the vertical bar is hidden.
    scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER

    _rows = VBoxContainer.new()
    _rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _rows.add_theme_constant_override("separation", 2)
    scroll.add_child(_rows)
    return scroll


func _button() -> Button:
    var button := Button.new()
    # Controller navigation stays inside _input, not GUI focus.
    button.focus_mode = Control.FOCUS_NONE
    button.add_theme_font_size_override("font_size", 18)
    if _ui_font != null:
        button.add_theme_font_override("font", _ui_font)
    UiTheme.apply_button(button, false, false, 2.0)
    return button


func _selector_arrow_button() -> Button:
    # The regular button has 18px text and padded styleboxes. Override
    # only the small selector arrows: keep a readable 14px chevron while
    # removing padding that would otherwise impose a >14px minimum width.
    var button: Button = _button()
    button.add_theme_font_size_override("font_size", MIN_UI_FONT_SIZE)
    for style_name in ["normal", "hover", "pressed"]:
        var style: StyleBoxFlat = button.get_theme_stylebox(style_name) as StyleBoxFlat
        if style != null:
            style.set_content_margin_all(0)
    button.add_theme_stylebox_override("disabled", UiTheme.item_style(false, true, 0.0))
    return button


func _label(font_size: int) -> Label:
    var label := Label.new()
    label.add_theme_font_size_override("font_size", maxi(font_size, MIN_UI_FONT_SIZE))
    if _ui_font != null:
        label.add_theme_font_override("font", _ui_font)
    label.add_theme_color_override("font_color", Color("#f0f1ed"))
    label.clip_text = true
    return label

func _refresh_text() -> void:
    if _title_label == null:
        return
    _title_label.text = _tr("ui.create_hero") if appearance_window and _creation_mode else (_tr("ui.appearance") if appearance_window else _tr("inventory.title"))
    if appearance_window:
        _action_hint.text = _tr("ui.hint_create_x") if _creation_mode else _tr("ui.hint_edit_x")
        _confirmation_message.text = _tr("ui.confirm_create_question") if _creation_mode else _tr("ui.confirm_edit_question")
        _confirmation_accept.call("set_caption", _tr("menu.confirm_accept"))
        _confirmation_cancel.call("set_caption", _tr("menu.confirm_cancel"))
    if not appearance_window:
        _equip_hint.text = _tr("inventory.equip_hint")
        for index in range(_tab_buttons.size()):
            _tab_buttons[index].text = _tr(str(BACKPACK_TABS[index]))
        _update_tab_styles()
        _reveal_active_tab()
    _missing_label.text = _tr("ui.missing_lpc")
    _missing_label.visible = not avatar.has_lpc_character()
    _preview.set("character", avatar.get_lpc_character())
    _preview.queue_redraw()
    _refresh_armor_status()
    _rebuild_rows()

func _rebuild_rows() -> void:
    _stop_value_marquees()
    _value_windows.clear()
    _value_labels.clear()
    _row_counters.clear()
    _row_labels.clear()
    _row_panels.clear()
    _row_values.clear()
    for child in _rows.get_children():
        _rows.remove_child(child)
        child.queue_free()

    var fields: Array = _current_fields()
    _compact_choice_panel.visible = not fields.is_empty()
    if not appearance_window:
        _equip_hint.visible = not fields.is_empty()
    if fields.is_empty():
        # Weapons currently have no equipment fields. Keep their tab and
        # empty-state text without an inert selector.
        var placeholder := VBoxContainer.new()
        placeholder.add_theme_constant_override("separation", 9)
        _rows.add_child(placeholder)
        var empty_text := _label(MIN_UI_FONT_SIZE)
        empty_text.text = _tr("inventory.empty_category")
        empty_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        empty_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        empty_text.custom_minimum_size.y = 52
        placeholder.add_child(empty_text)
    else:
        _build_compact_field_list(fields)

    _update_row_highlight()
    _update_compact_choice()
    _reveal_selected_row()


func _build_compact_field_list(fields: Array) -> void:
    for field_key in fields:
        var index: int = _row_panels.size()
        var key: String = str(field_key)

        var field_panel := PanelContainer.new()
        field_panel.name = "Field_" + key
        field_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        field_panel.custom_minimum_size.y = 23
        field_panel.mouse_filter = Control.MOUSE_FILTER_PASS
        field_panel.gui_input.connect(_on_compact_row_input.bind(index))
        _rows.add_child(field_panel)
        _row_panels.append(field_panel)

        var line := HBoxContainer.new()
        line.mouse_filter = Control.MOUSE_FILTER_IGNORE
        line.add_theme_constant_override("separation", 3)
        field_panel.add_child(line)

        var caption: Label = _label(MIN_UI_FONT_SIZE)
        caption.text = _tr("field." + key)
        caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
        caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        caption.clip_text = true
        line.add_child(caption)
        _row_labels.append(caption)

        var counter: Label = _label(MIN_UI_FONT_SIZE)
        counter.text = _field_counter(key)
        counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
        counter.custom_minimum_size.x = 36
        counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        counter.add_theme_color_override("font_color", Color("#cfbf99"))
        line.add_child(counter)
        _row_counters[key] = counter


func _on_compact_row_input(event: InputEvent, index: int) -> void:
    if not _opened or _confirmation_open:
        return
    if event is InputEventMouseButton:
        var click: InputEventMouseButton = event as InputEventMouseButton
        if click.button_index == MOUSE_BUTTON_LEFT and click.pressed:
            _selected_index = index
            _update_row_highlight()
            _update_compact_choice()


func _update_compact_choice() -> void:
    if _compact_choice_value == null:
        return
    var fields: Array = _current_fields()
    if fields.is_empty():
        _compact_choice_panel.hide()
        _stop_value_marquees()
        _value_labels.clear()
        _value_windows.clear()
        _refresh_armor_status()
        return
    _compact_choice_panel.show()
    var field_key: String = str(fields[clampi(_selected_index, 0, fields.size() - 1)])
    _stop_value_marquees()
    _value_labels.clear()
    _value_windows.clear()
    _compact_choice_value.text = _localized_value(field_key)
    var pending_change: bool = false
    if not appearance_window and _inventory != null:
        var slot: String = str(_inventory.call("get_equipment_slot", field_key))
        pending_change = _selected_equipment_id(field_key) != str(_inventory.call("get_equipped", slot))
    if not appearance_window and _equip_hint != null:
        # Keep the label's height reserved so browsing doesn't shift the
        # interface. Only show A: equip for an unconfirmed selection.
        _equip_hint.modulate.a = 1.0 if pending_change else 0.0
    _compact_choice_value.add_theme_color_override("font_color", ACTIVE_HIGHLIGHT if pending_change else Color("#f0f1ed"))
    _compact_prev.disabled = not _can_adjust_field(field_key, -1)
    _compact_next.disabled = not _can_adjust_field(field_key, 1)
    _value_labels[field_key] = _compact_choice_value
    _value_windows[field_key] = _compact_choice_window
    if not appearance_window:
        _preview_equipment_on_character(field_key)
    _refresh_armor_status()
    call_deferred("_refresh_all_value_marquees")


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
    if not appearance_window:
        if _inventory == null:
            return _tr("inventory.none")
        var candidate_id: String = _selected_equipment_id(key)
        if candidate_id.is_empty():
            return _tr("value.clothing.none")
        var garment: Dictionary = _inventory.call("get_item", candidate_id)
        return _tr(str(garment.get("label", "inventory.none")))

    var value: String = avatar.get_lpc_option(key)
    if value == "none":
        return _tr("value.clothing.none")
    if key == "body_type" or key.ends_with("_style"):
        return _tr("value." + key + "." + value.replace("/", "_"))
    return _tr("color." + value)

func _refresh_options() -> void:
    # Refresh the shared selector without rebuilding the list or losing the
    # current selection, then update all five counters independently.
    for option_key in _value_labels.keys():
        var key: String = str(option_key)
        var field_label: Label = _value_labels[option_key] as Label
        if is_instance_valid(field_label):
            field_label.text = _localized_value(key)
    for option_key in _row_counters.keys():
        var counter: Label = _row_counters[option_key] as Label
        if is_instance_valid(counter):
            counter.text = _field_counter(str(option_key))
    # Drop cropped frames from the previous equipment set immediately.
    # The preview creates fresh 64x64 textures for the new LPC nodes.
    if _preview != null and _preview.has_method("clear_frame_cache"):
        _preview.call("clear_frame_cache")
    else:
        _preview.queue_redraw()
    _refresh_preview_after_frame()
    # _update_compact_choice() updates the +/- preview and schedules the marquee.
    _update_compact_choice()


func _refresh_preview_after_frame() -> void:
    # _load_appearance() retires old AnimatedSprite2D layers using
    # queue_free(). Repaint after the next scene-tree frame so a paused
    # portrait cannot cache a stale/invalid atlas between rapid gear swaps.
    if _preview_refresh_pending:
        return
    _preview_refresh_pending = true
    await get_tree().process_frame
    _preview_refresh_pending = false
    if _opened and is_instance_valid(_preview):
        _preview.queue_redraw()


func _stop_value_marquees() -> void:
    for running_tween in _value_marquees.values():
        if running_tween is Tween and running_tween.is_valid():
            running_tween.kill()
    _value_marquees.clear()


func _refresh_all_value_marquees() -> void:
    if not _opened:
        return
    # Initial creation happens while the panel is still being laid out.
    # Measure the label only after the column and arrow anchors settle.
    await get_tree().process_frame
    if not _opened:
        return
    for field_key in _value_windows.keys():
        _update_value_marquee(str(field_key))


func _update_value_marquee(key: String) -> void:
    if not _opened or not _value_windows.has(key) or not _value_labels.has(key):
        return
    var viewport: Control = _value_windows[key] as Control
    var label: Label = _value_labels[key] as Label
    if not is_instance_valid(viewport) or not is_instance_valid(label):
        return
    if viewport.size.x <= 0.0:
        return

    if _value_marquees.has(key):
        var old_tween: Tween = _value_marquees[key] as Tween
        if old_tween != null and old_tween.is_valid():
            old_tween.kill()
        _value_marquees.erase(key)

    # Use real text width at the logical 14px minimum, not character count.
    var font: Font = label.get_theme_font("font")
    var text_width: float = ceilf(font.get_string_size(
        label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, MIN_UI_FONT_SIZE
    ).x) + 3.0
    var window_width: float = viewport.size.x
    label.position = Vector2.ZERO
    label.size = Vector2(maxf(text_width, window_width), viewport.size.y)

    if text_width <= window_width:
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        return

    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    var overflow: float = text_width - window_width
    var tween: Tween = create_tween()
    tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
    tween.set_loops()
    tween.tween_interval(0.8)
    tween.tween_property(label, "position:x", -overflow, maxf(1.0, overflow / 16.0))
    tween.tween_interval(0.8)
    tween.tween_property(label, "position:x", 0.0, maxf(1.0, overflow / 16.0))
    _value_marquees[key] = tween


func _on_inventory_changed() -> void:
    if _opened and not appearance_window:
        _refresh_options()


func _refresh_armor_status() -> void:
    if appearance_window or _inventory == null:
        return
    if _armor_class_label == null or _armor_value_label == null:
        return

    var armor_class: String = str(_inventory.call("get_equipped_armor_class"))
    var current_armor: int = int(_inventory.call("get_total_armor"))
    var projected_armor: int = current_armor
    var difference: int = 0
    var fields: Array = _current_fields()
    if _selected_index >= 0 and _selected_index < fields.size():
        var field: String = str(fields[_selected_index])
        var candidate_id: String = _selected_equipment_id(field)
        var comparison: Dictionary = _inventory.call("preview_equipment", field, candidate_id)
        if not comparison.is_empty():
            projected_armor = int(comparison.get("projected_total", current_armor))
            difference = int(comparison.get("delta", 0))
            if difference != 0:
                armor_class = str(comparison.get("class", armor_class))

    _armor_class_label.text = _tr("armor.class." + armor_class)
    if difference == 0:
        _armor_value_label.text = _tr("armor.value") % current_armor
        _armor_value_label.add_theme_color_override("font_color", Color("#f0f1ed"))
    else:
        # The narrow 104px portrait can fit +5 (+3), not
        # 'Броня +5 (+3)'. Show projected protection and its +/- delta.
        var signed_delta: String = ("+" if difference > 0 else "") + str(difference)
        _armor_value_label.text = "+%d (%s)" % [projected_armor, signed_delta]
        var ink: Color = Color("#99e1ad") if difference > 0 else Color("#ffb5a6")
        _armor_value_label.add_theme_color_override("font_color", ink)


func _adjust(key: String, direction: int, index: int = -1) -> void:
    if index >= 0:
        _selected_index = index
        _update_row_highlight()
        _reveal_selected_row()

    if not appearance_window:
        # Equipment can only be committed by _confirm_equipment_selection.
        # Arrow controls never call the old immediate-equip API.
        return

    if avatar.change_lpc_option(key, direction):
        # While creating a character, update the draft's starter clothes
        # immediately when body type changes. Later edits leave clothes alone.
        if _creation_mode and key == "body_type":
            avatar.apply_starter_outfit()
            if _inventory != null:
                _inventory.call("set_starter_equipment", avatar.get_lpc_option("body_type"))
        _refresh_options()


func _field_counter(key: String) -> String:
    if not avatar.has_lpc_character():
        return "0/0"
    var choices: Array[String] = []
    var chosen: String = ""
    if appearance_window:
        choices = avatar.get_lpc_option_choices(key)
        chosen = avatar.get_lpc_option(key)
    elif _inventory != null:
        choices = _inventory.call("get_equipment_choices", key)
        chosen = _selected_equipment_id(key)
    if choices.is_empty():
        return "0/0"

    if appearance_window:
        # "Немає" is hairstyle zero, not a sixth hairstyle.
        # Keep all five actual hairstyles in the denominator.
        if key == "hair_style" and choices.has("none"):
            if chosen == "none":
                return "0/%d" % (choices.size() - 1)
            var hair_index: int = choices.find(chosen)
            var none_index: int = choices.find("none")
            if hair_index >= 0:
                var ordinal: int = hair_index + 1 if hair_index < none_index else hair_index
                return "%d/%d" % [ordinal, choices.size() - 1]
        var index: int = choices.find(chosen)
        return "%d/%d" % [index + 1 if index >= 0 else 0, choices.size()]

    # "None" is an action to unequip, not a physical item.
    # Exclude it from both the current index and the total, without
    # removing it from the actual cyclic equipment choices.
    var item_count: int = 0
    var selected_item: int = 0
    for item_id in choices:
        if item_id.is_empty():
            continue
        item_count += 1
        if item_id == chosen:
            selected_item = item_count
    return "%d/%d" % [selected_item, item_count]


func _can_adjust_field(key: String, direction: int) -> bool:
    if not avatar.has_lpc_character():
        return false
    if not appearance_window:
        if _inventory == null:
            return false
        var equipment_choices: Array[String] = _inventory.call("get_equipment_choices", key)
        return equipment_choices.size() > 1
    # Appearance options are cyclic, unlike menu-row navigation.
    var choices: Array[String] = avatar.get_lpc_option_choices(key)
    return choices.size() > 1


