extends Node
## Prototype inventory shared by the backpack and the test chest.
## Each item id represents one physical piece of clothing; only owned
## items can be equipped. The starter outfit is equipped, not in the bag.

signal changed

const ITEMS := {
    "formal_pants": {"slot": "pants", "style": "formal", "variant": "charcoal", "label": "item.formal_pants"},
    "basic_tshirt": {"slot": "shirt", "style": "shortsleeve/tshirt", "variant": "blue", "label": "item.basic_tshirt"},
    "white_shirt": {"slot": "shirt", "style": "shortsleeve/shortsleeve", "variant": "white", "label": "item.white_shirt"},
    "green_polo": {"slot": "shirt", "style": "shortsleeve/shortsleeve_polo", "variant": "forest", "label": "item.green_polo"},
    "black_longsleeve": {"slot": "shirt", "style": "longsleeve/longsleeve", "variant": "black", "label": "item.black_longsleeve"},
    "brown_pants": {"slot": "pants", "style": "pants", "variant": "brown", "label": "item.brown_pants"},
    "navy_cuffed_pants": {"slot": "pants", "style": "cuffed", "variant": "navy", "label": "item.navy_cuffed_pants"},
    "brown_boots": {"slot": "footwear", "style": "boots/basic", "variant": "brown", "label": "item.brown_boots"},
    "black_shoes": {"slot": "footwear", "style": "shoes/basic", "variant": "black", "label": "item.black_shoes"},
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

var _bag: Array[String] = []
var _chest: Array[String] = []
var _equipped: Dictionary = {"shirt": "", "pants": "", "footwear": ""}


func _ready() -> void:
    reset_for_new_game("male")


func reset_for_new_game(body_type: String = "male") -> void:
    _bag.clear()
    _chest.clear()
    for item_id in TEST_CHEST_ITEMS:
        _chest.append(item_id)
    set_starter_equipment(body_type)


func set_starter_equipment(body_type: String) -> void:
    _equipped = {
        "shirt": "basic_tshirt" if body_type == "female" else "",
        "pants": "formal_pants",
        "footwear": "",
    }
    changed.emit()


func get_bag() -> Array[String]:
    return _bag.duplicate()


func get_chest() -> Array[String]:
    return _chest.duplicate()


func get_equipped(slot: String) -> String:
    return str(_equipped.get(slot, ""))


func get_item(item_id: String) -> Dictionary:
    return ITEMS.get(item_id, {})


func get_save_state() -> Dictionary:
    return {
        "bag": _bag.duplicate(),
        "chest": _chest.duplicate(),
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
        _equipped = {"shirt": "", "pants": "", "footwear": ""}
        _infer_legacy_equipment(avatar)
        changed.emit()
        return

    var raw: Dictionary = data
    var used: Dictionary = {}
    var bag: Array[String] = []
    var chest: Array[String] = []
    var equipment: Dictionary = {"shirt": "", "pants": "", "footwear": ""}

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

    _bag = bag
    _chest = chest
    _equipped = equipment
    changed.emit()


func _infer_legacy_equipment(avatar: Node) -> void:
    if avatar == null or not avatar.has_method("get_lpc_option"):
        return
    for slot in _equipped.keys():
        var style_key: String = "footwear_style" if slot == "footwear" else slot + "_style"
        var variant_key: String = "boots_variant" if slot == "footwear" else slot + "_variant"
        var style: String = str(avatar.call("get_lpc_option", style_key))
        var variant: String = str(avatar.call("get_lpc_option", variant_key))
        for item_id in ITEMS:
            var item: Dictionary = ITEMS[item_id]
            if item["slot"] == slot and item["style"] == style and item["variant"] == variant:
                _equipped[slot] = item_id
                break


func take_from_chest(requested: Array[String]) -> int:
    var count: int = 0
    for item_id in requested:
        if _chest.has(item_id) and not _bag.has(item_id):
            _chest.erase(item_id)
            _bag.append(item_id)
            count += 1
    if count > 0:
        changed.emit()
    return count


func equip(item_id: String, avatar: Node) -> bool:
    if not _bag.has(item_id):
        return false
    var item: Dictionary = get_item(item_id)
    if item.is_empty():
        return false
    var slot: String = str(item["slot"])
    if not _apply_to_avatar(avatar, slot, item):
        return false
    var previous_id: String = get_equipped(slot)
    _bag.erase(item_id)
    if not previous_id.is_empty():
        _bag.append(previous_id)
    _equipped[slot] = item_id
    changed.emit()
    return true


func unequip(slot: String, avatar: Node) -> bool:
    var previous_id: String = get_equipped(slot)
    if previous_id.is_empty():
        return false
    if not _apply_to_avatar(avatar, slot, {"style": "none"}):
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
    return bool(lpc.call("apply_appearance_state", state))
