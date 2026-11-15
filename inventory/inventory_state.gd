extends Node
## Prototype inventory shared by the backpack and the test chest.
## Each item id represents one physical piece of clothing; only owned
## items can be equipped. The starter outfit is equipped, not in the bag.

signal changed

const ITEMS := {
    "formal_pants": {"slot": "pants", "style": "formal", "variant": "charcoal", "label": "item.formal_pants", "armor_class": "cloth", "armor_value": 0},
    "basic_tshirt": {"slot": "shirt", "style": "shortsleeve/tshirt", "variant": "blue", "label": "item.basic_tshirt", "armor_class": "cloth", "armor_value": 0},
    "white_shirt": {"slot": "shirt", "style": "shortsleeve/shortsleeve", "variant": "white", "label": "item.white_shirt", "armor_class": "cloth", "armor_value": 0},
    "green_polo": {"slot": "shirt", "style": "shortsleeve/shortsleeve_polo", "variant": "forest", "label": "item.green_polo", "armor_class": "cloth", "armor_value": 0},
    "black_longsleeve": {"slot": "shirt", "style": "longsleeve/longsleeve", "variant": "black", "label": "item.black_longsleeve", "armor_class": "cloth", "armor_value": 0},
    "brown_pants": {"slot": "pants", "style": "pants", "variant": "brown", "label": "item.brown_pants", "armor_class": "cloth", "armor_value": 0},
    "navy_cuffed_pants": {"slot": "pants", "style": "cuffed", "variant": "navy", "label": "item.navy_cuffed_pants", "armor_class": "cloth", "armor_value": 0},
    "brown_boots": {"slot": "footwear", "style": "boots/basic", "variant": "brown", "label": "item.brown_boots", "armor_class": "cloth", "armor_value": 0},
    "black_shoes": {"slot": "footwear", "style": "shoes/basic", "variant": "black", "label": "item.black_shoes", "armor_class": "cloth", "armor_value": 0},
    # Separate equippable armor slot. These items are physical loot,
    # never offered as free options or granted at character creation.
    "leather_vest": {"slot": "armor", "style": "leather_vest", "label": "item.leather_vest", "armor_class": "light", "armor_value": 2},
    "reinforced_vest": {"slot": "armor", "style": "reinforced_vest", "label": "item.reinforced_vest", "armor_class": "light", "armor_value": 3},
    "plate_cuirass": {"slot": "armor", "style": "plate_cuirass", "label": "item.plate_cuirass", "armor_class": "heavy", "armor_value": 5},
}
# Armor classes are data, not inferred from garment sprite paths.
# Future LPC armor pieces will declare their own class and protection
# value. Class ranks describe the material tier; armor_value is additive.
const ARMOR_CLASSES := {
    "cloth": {"rank": 0, "label": "armor.class.cloth", "default_value": 0},
    "light": {"rank": 1, "label": "armor.class.light", "default_value": 2},
    "heavy": {"rank": 2, "label": "armor.class.heavy", "default_value": 5},
}

const TEST_CHEST_ITEMS := [
    "white_shirt",
    "green_polo",
    "black_longsleeve",
    "brown_pants",
    "navy_cuffed_pants",
    "brown_boots",
    "black_shoes",
]
const TEST_ARMOR_CHEST_ITEMS := [
    "leather_vest",
    "reinforced_vest",
    "plate_cuirass",
]

# Five matching equipment areas in Clothing and Armor. Existing saved
# names stay unchanged (shirt/pants/footwear/armor); the empty extra
# slots reserve room for actual head, hand and leg art later.
const EQUIPMENT_FIELD_SLOTS := {
    "clothes_head": "clothes_head",
    "clothes_top": "shirt",
    "clothes_bottom": "pants",
    "clothes_hands": "clothes_hands",
    "clothes_feet": "footwear",
    "armor_head": "armor_head",
    "armor_top": "armor",
    "armor_bottom": "armor_bottom",
    "armor_hands": "armor_hands",
    "armor_feet": "armor_feet",
}
const EMPTY_EQUIPMENT := {
    "shirt": "", "pants": "", "footwear": "", "armor": "",
    "clothes_head": "", "clothes_hands": "",
    "armor_head": "", "armor_bottom": "", "armor_hands": "", "armor_feet": "",
}

var _bag: Array[String] = []
var _chest: Array[String] = []
var _armor_chest: Array[String] = []
var _equipped: Dictionary = EMPTY_EQUIPMENT.duplicate()


func _ready() -> void:
    reset_for_new_game("male")


func reset_for_new_game(body_type: String = "male") -> void:
    _bag.clear()
    _chest.clear()
    for item_id in TEST_CHEST_ITEMS:
        _chest.append(item_id)
    _armor_chest.clear()
    for item_id in TEST_ARMOR_CHEST_ITEMS:
        _armor_chest.append(item_id)
    set_starter_equipment(body_type)


func set_starter_equipment(body_type: String) -> void:
    _equipped = EMPTY_EQUIPMENT.duplicate()
    _equipped["shirt"] = "basic_tshirt" if body_type == "female" else ""
    _equipped["pants"] = "formal_pants"
    changed.emit()


func get_bag() -> Array[String]:
    return _bag.duplicate()


func get_chest() -> Array[String]:
    return _chest.duplicate()


func get_chest_items(chest_kind: String = "clothes") -> Array[String]:
    return _armor_chest.duplicate() if chest_kind == "armor" else _chest.duplicate()


func get_equipped(slot: String) -> String:
    return str(_equipped.get(slot, ""))


func get_item(item_id: String) -> Dictionary:
    return ITEMS.get(item_id, {})


# The right-hand character portrait uses these summaries for the
# two-line panel below the divider. Currently all owned garments
# are cloth (+0); armor items can use light/heavy in the same catalog.
func get_item_armor_class(item_id: String) -> String:
    var info: Dictionary = get_item(item_id)
    var result: String = str(info.get("armor_class", "cloth"))
    return result if ARMOR_CLASSES.has(result) else "cloth"


func get_item_armor_value(item_id: String) -> int:
    var info: Dictionary = get_item(item_id)
    if info.is_empty():
        return 0
    # Each item can override its tier's default value independently.
    var armor_class: String = get_item_armor_class(item_id)
    var base: int = int(ARMOR_CLASSES[armor_class]["default_value"])
    return maxi(int(info.get("armor_value", base)), 0)


func get_total_armor() -> int:
    var total: int = 0
    for slot in _equipped.keys():
        total += get_item_armor_value(str(_equipped[slot]))
    return total


func get_equipped_armor_class() -> String:
    var strongest: String = "cloth"
    var strongest_rank: int = 0
    for slot in _equipped.keys():
        var item_id: String = str(_equipped[slot])
        var armor_class: String = get_item_armor_class(item_id)
        var rank: int = int(ARMOR_CLASSES[armor_class]["rank"])
        if rank > strongest_rank:
            strongest = armor_class
            strongest_rank = rank
    return strongest


func compare_item_armor(item_id: String) -> Dictionary:
    # Future armor selection can show candidate vs current protection.
    # This does NOT equip or add the item and remains safe for old saves.
    var candidate: Dictionary = get_item(item_id)
    if candidate.is_empty():
        return {}
    var slot: String = str(candidate.get("slot", ""))
    if not _equipped.has(slot):
        return {}
    var old_value: int = get_item_armor_value(get_equipped(slot))
    var new_value: int = get_item_armor_value(item_id)
    var total: int = get_total_armor()
    return {
        "class": get_item_armor_class(item_id),
        "value": new_value,
        "current_total": total,
        "delta": new_value - old_value,
        "projected_total": total - old_value + new_value,
    }


func get_save_state() -> Dictionary:
    return {
        "bag": _bag.duplicate(),
        "chest": _chest.duplicate(),
        "armor_chest": _armor_chest.duplicate(),
        "equipped": _equipped.duplicate(),
    }


func load_save_state(data: Variant, avatar: Node) -> void:
    # Old saves have no inventory. Preserve their visible clothing and
    # initialize an unopened chest rather than generating free bag items.
    if not data is Dictionary:
        _bag.clear()
        _chest.clear()
        for item_id in TEST_CHEST_ITEMS:
            _chest.append(item_id)
        _armor_chest.clear()
        for item_id in TEST_ARMOR_CHEST_ITEMS:
            _armor_chest.append(item_id)
        _equipped = EMPTY_EQUIPMENT.duplicate()
        _infer_legacy_equipment(avatar)
        changed.emit()
        return

    var raw: Dictionary = data
    var used: Dictionary = {}
    var bag: Array[String] = []
    var chest: Array[String] = []
    var armor_chest: Array[String] = []
    var equipment: Dictionary = EMPTY_EQUIPMENT.duplicate()

    var saved_equipment: Variant = raw.get("equipped", {})
    if saved_equipment is Dictionary:
        for slot in equipment.keys():
            var item_id: String = str(saved_equipment.get(slot, ""))
            var item: Dictionary = get_item(item_id)
            if not item.is_empty() and str(item.get("slot", "")) == slot and not used.has(item_id):
                equipment[slot] = item_id
                used[item_id] = true

    var saved_bag: Variant = raw.get("bag", [])
    if saved_bag is Array:
        for value in saved_bag:
            var item_id: String = str(value)
            if ITEMS.has(item_id) and not used.has(item_id):
                bag.append(item_id)
                used[item_id] = true

    var saved_chest: Variant = raw.get("chest", [])
    if saved_chest is Array:
        for value in saved_chest:
            var item_id: String = str(value)
            if ITEMS.has(item_id) and not used.has(item_id):
                chest.append(item_id)
                used[item_id] = true

    # Older saves have no armor_chest field: introduce its initial stock
    # while preserving their existing bag, gear and original clothing chest.
    var saved_armor_chest: Variant = raw.get("armor_chest", TEST_ARMOR_CHEST_ITEMS)
    if saved_armor_chest is Array:
        for value in saved_armor_chest:
            var armor_id: String = str(value)
            if TEST_ARMOR_CHEST_ITEMS.has(armor_id) and not used.has(armor_id):
                armor_chest.append(armor_id)
                used[armor_id] = true

    # Migrate older saves that allowed torso clothing and armor together.
    # Armor takes precedence; a displaced shirt becomes owned bag loot.
    if not str(equipment["armor"]).is_empty() and not str(equipment["shirt"]).is_empty():
        bag.append(str(equipment["shirt"]))
        equipment["shirt"] = ""

    _bag = bag
    _chest = chest
    _armor_chest = armor_chest
    _equipped = equipment
    if not get_equipped("armor").is_empty():
        # If a save references missing art, keep that armor as an owned
        # item rather than claiming it is worn without a visible sprite.
        if not _apply_armor_to_avatar(avatar, get_equipped("armor")):
            var missing_armor: String = get_equipped("armor")
            _equipped["armor"] = ""
            if not _bag.has(missing_armor):
                _bag.append(missing_armor)
            _apply_armor_to_avatar(avatar, "")
    changed.emit()


func _infer_legacy_equipment(avatar: Node) -> void:
    if avatar == null or not avatar.has_method("get_lpc_option"):
        return
    # Legacy LPC saves know only these three clothing categories. Do not
    # try to read nonexistent *_style fields for future empty equipment.
    for slot in ["shirt", "pants", "footwear"]:
        var style_key: String = "footwear_style" if slot == "footwear" else slot + "_style"
        var variant_key: String = "boots_variant" if slot == "footwear" else slot + "_variant"
        var style: String = str(avatar.call("get_lpc_option", style_key))
        var variant: String = str(avatar.call("get_lpc_option", variant_key))
        for item_id in ITEMS:
            var item: Dictionary = ITEMS[item_id]
            if item["slot"] == slot and item["style"] == style and item["variant"] == variant:
                _equipped[slot] = item_id
                break


func take_from_chest(requested: Array[String], chest_kind: String = "clothes") -> int:
    var source: Array[String] = _armor_chest if chest_kind == "armor" else _chest
    var count: int = 0
    for item_id in requested:
        if source.has(item_id) and not _bag.has(item_id):
            source.erase(item_id)
            _bag.append(item_id)
            count += 1
    if count > 0:
        changed.emit()
    return count


# Shared five-field selector API for both tabs. It enumerates actual
# owned physical items, including the worn item, plus "None". Head/hands
# and lower armor stay at 1/1 until matching assets/items are introduced.
func get_equipment_slot(field: String) -> String:
    return str(EQUIPMENT_FIELD_SLOTS.get(field, ""))


func get_equipment_choices(field: String) -> Array[String]:
    var choices: Array[String] = []
    var slot: String = get_equipment_slot(field)
    if slot.is_empty():
        return choices
    choices.append("")
    var equipped_id: String = get_equipped(slot)
    for raw_id in ITEMS.keys():
        var item_id: String = str(raw_id)
        var item: Dictionary = get_item(item_id)
        if str(item.get("slot", "")) != slot:
            continue
        if item_id == equipped_id or _bag.has(item_id):
            choices.append(item_id)
    return choices


func cycle_equipment_field(field: String, direction: int, avatar: Node) -> bool:
    var slot: String = get_equipment_slot(field)
    if slot.is_empty():
        return false
    if slot == "armor":
        # Preserve existing "skip missing LPC atlas" behavior.
        return cycle_armor(direction, avatar)

    var choices: Array[String] = get_equipment_choices(field)
    if choices.size() <= 1:
        return false
    var current_id: String = get_equipped(slot)
    var current_index: int = choices.find(current_id)
    if current_index < 0:
        return false
    var step: int = 1 if direction >= 0 else -1
    for offset in range(1, choices.size()):
        var next_id: String = choices[posmod(current_index + offset * step, choices.size())]
        if next_id.is_empty():
            if unequip(slot, avatar):
                return true
        elif equip(next_id, avatar):
            return true
    return false


# Expose only physically owned clothes to the original six selector rows.
# Style selectors cycle the distinct styles; color selectors cycle variants
# within the currently equipped style. Both work with complete item ids.
func _field_slot(field: String) -> String:
    match field:
        "shirt_style", "shirt_variant":
            return "shirt"
        "pants_style", "pants_variant":
            return "pants"
        "footwear_style", "boots_variant":
            return "footwear"
    return ""


func get_field_choices(field: String) -> Array[String]:
    var slot: String = _field_slot(field)
    var choices: Array[String] = []
    if slot.is_empty():
        return choices

    var current_id: String = get_equipped(slot)
    var current_info: Dictionary = get_item(current_id)
    var is_color_field: bool = field.ends_with("_variant")
    if is_color_field and current_id.is_empty():
        return choices

    if not is_color_field:
        choices.append("") # No garment in this slot.
    var seen_styles: Dictionary = {}
    for id in ITEMS.keys():
        var item_id: String = str(id)
        if item_id != current_id and not _bag.has(item_id):
            continue
        var info: Dictionary = get_item(item_id)
        if info.is_empty() or str(info.get("slot", "")) != slot:
            continue
        var item_style: String = str(info.get("style", ""))
        if is_color_field:
            if item_style == str(current_info.get("style", "")):
                choices.append(item_id)
        elif not seen_styles.has(item_style):
            # Preserve the equipped color when cycling across styles.
            var representative: String = item_id
            if not current_info.is_empty() and str(current_info.get("style", "")) == item_style:
                # Always include the equipped variant as the representative
                # for its style, even if an older bag variant appears first.
                representative = current_id
            choices.append(representative)
            seen_styles[item_style] = true
    return choices


func cycle_field(field: String, direction: int, avatar: Node) -> bool:
    var slot: String = _field_slot(field)
    var options: Array[String] = get_field_choices(field)
    if slot.is_empty() or options.size() <= 1:
        return false
    var current_id: String = get_equipped(slot)
    var old_index: int = options.find(current_id)
    if old_index < 0:
        return false
    var new_id: String = options[posmod(old_index + (1 if direction >= 0 else -1), options.size())]
    if new_id == current_id:
        return false
    if new_id.is_empty():
        return unequip(slot, avatar)
    return equip(new_id, avatar)


# One cyclical field in the Armor backpack tab, containing only the
# armor pieces the player has recovered from the second chest.
func get_armor_choices() -> Array[String]:
    var options: Array[String] = [""]
    for item_id in TEST_ARMOR_CHEST_ITEMS:
        if get_equipped("armor") == item_id or _bag.has(item_id):
            options.append(item_id)
    return options


func cycle_armor(direction: int, avatar: Node) -> bool:
    var options: Array[String] = get_armor_choices()
    if options.size() < 2:
        return false
    var equipped_id: String = get_equipped("armor")
    var index: int = options.find(equipped_id)
    if index < 0:
        return false

    # A single missing/malformed LPC sprite must not trap the player on
    # the same item forever. Try the next owned option in the requested
    # direction, preserving inventory if an equip attempt fails.
    var step_direction: int = 1 if direction >= 0 else -1
    for offset in range(1, options.size()):
        var next_id: String = options[posmod(index + offset * step_direction, options.size())]
        if next_id.is_empty():
            if unequip("armor", avatar):
                return true
        elif equip(next_id, avatar):
            return true
    return false


# One LPC rebuild applies BOTH layers in a single, validated step.
# No intermediate frame with overlapping shirt and armor is rendered.
func _apply_armor_to_avatar(avatar: Node, item_id: String) -> bool:
    var style: String = str(get_item(item_id).get("style", "none"))
    var changes: Dictionary = {"armor_style": style}
    if not item_id.is_empty():
        changes["shirt_style"] = "none"
    return _apply_lpc_changes(avatar, changes)


func _apply_lpc_changes(avatar: Node, changes: Dictionary) -> bool:
    if avatar == null or not avatar.has_method("get_lpc_character"):
        return false
    var lpc: Node = avatar.call("get_lpc_character") as Node
    if lpc == null or not lpc.has_method("apply_appearance_state"):
        return false
    return bool(lpc.call("apply_appearance_state", changes))

func equip(item_id: String, avatar: Node) -> bool:
    if not _bag.has(item_id):
        return false
    var item: Dictionary = get_item(item_id)
    if item.is_empty():
        return false
    var slot: String = str(item["slot"])
    # Only torso clothing and torso armor are exclusive; pants and shoes
    # remain equipped. All mutations happen AFTER the LPC validation.
    if slot == "armor":
        if not _apply_armor_to_avatar(avatar, item_id):
            return false
    elif slot in ["shirt", "pants", "footwear"]:
        if not _apply_to_avatar(avatar, slot, item):
            return false
    else:
        # Future equipment areas must be given matching LPC layers before
        # their items can be equipped. Never silently claim a visual swap.
        return false

    var old_id: String = get_equipped(slot)
    var conflicting_slot: String = "shirt" if slot == "armor" else ("armor" if slot == "shirt" else "")
    var conflicting_id: String = get_equipped(conflicting_slot) if not conflicting_slot.is_empty() else ""

    _bag.erase(item_id)
    if not old_id.is_empty():
        _bag.append(old_id)
    _equipped[slot] = item_id
    if not conflicting_id.is_empty():
        _equipped[conflicting_slot] = ""
        _bag.append(conflicting_id)
    changed.emit()
    return true


func unequip(slot: String, avatar: Node) -> bool:
    var previous_id: String = get_equipped(slot)
    if previous_id.is_empty():
        return false
    if slot == "armor":
        if not _apply_armor_to_avatar(avatar, ""):
            return false
    elif not _apply_to_avatar(avatar, slot, {"style": "none"}):
        return false
    _equipped[slot] = ""
    _bag.append(previous_id)
    changed.emit()
    return true


func _apply_to_avatar(avatar: Node, slot: String, item: Dictionary) -> bool:
    if avatar == null or not avatar.has_method("get_lpc_character"):
        return false
    var lpc: Node = avatar.call("get_lpc_character") as Node
    if lpc == null or not lpc.has_method("apply_appearance_state"):
        return false
    var style_key: String = "footwear_style" if slot == "footwear" else slot + "_style"
    var variant_key: String = "boots_variant" if slot == "footwear" else slot + "_variant"
    var state: Dictionary = {style_key: str(item["style"])}
    if item.has("variant"):
        state[variant_key] = str(item["variant"])
    if slot == "shirt" and str(item["style"]) != "none":
        # Putting on a top removes any worn torso armor atomically.
        state["armor_style"] = "none"
    return bool(lpc.call("apply_appearance_state", state))
