extends RefCounted
## All Skyval profiles and snapshots live in one writable saves folder.
## PortMaster sets SKYVAL_SAVES_DIR; desktop Godot uses user://saves.
## v2 profiles created before snapshot support stay readable.

const VERSION := 2
const FALLBACK_DIR := "user://saves"
const KIND_PROFILE := "profile"
const KIND_MANUAL := "manual"
const KIND_QUICK := "quick"


func directory_path() -> String:
    var override: String = OS.get_environment("SKYVAL_SAVES_DIR").strip_edges()
    return override.trim_suffix("/") if not override.is_empty() else FALLBACK_DIR


func new_profile(name: String) -> Dictionary:
    var clean_name: String = name.strip_edges()
    if clean_name.is_empty():
        return {}
    var profile_id: String = ""
    var path: String = ""
    for attempt in range(30):
        profile_id = "%s%05d" % [str(int(Time.get_unix_time_from_system())), randi_range(0, 99999)]
        var filename: String = "%s-%s.json" % [profile_id, clean_name.replace(" ", "_")]
        path = directory_path().path_join(filename)
        if not FileAccess.file_exists(path):
            break
    if FileAccess.file_exists(path):
        return {}
    var now: int = _timestamp_ms()
    return {
        "version": VERSION,
        "profile_id": profile_id,
        "character_name": clean_name,
        "created_at": now,
        "last_played": now,
        "saved_at": now,
        "save_kind": KIND_PROFILE,
        "path": path,
    }


func read_profile(path: String) -> Dictionary:
    if not _is_profile_path(path) or not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not parsed is Dictionary:
        return {}
    var data: Dictionary = parsed
    if int(data.get("version", 0)) != VERSION:
        return {}
    if str(data.get("profile_id", "")).is_empty() or str(data.get("character_name", "")).strip_edges().is_empty():
        return {}
    var kind: String = str(data.get("save_kind", KIND_PROFILE))
    if kind not in [KIND_PROFILE, KIND_MANUAL, KIND_QUICK]:
        return {}
    var position: Variant = data.get("player_position")
    if not position is Array or position.size() != 2:
        return {}
    for coordinate in position:
        if typeof(coordinate) != TYPE_FLOAT and typeof(coordinate) != TYPE_INT:
            return {}
    data["save_kind"] = kind
    data["saved_at"] = int(data.get("saved_at", data.get("created_at", FileAccess.get_modified_time(path) * 1000)))
    data["path"] = path
    return data


func write_profile(path: String, data: Dictionary) -> bool:
    if not _is_profile_path(path):
        return false
    var dir_error: Error = DirAccess.make_dir_recursive_absolute(directory_path())
    if dir_error != OK:
        push_warning("Skyval: cannot create saves folder: %s" % error_string(dir_error))
        return false
    var serialized: Dictionary = data.duplicate(true)
    serialized.erase("path")
    serialized["version"] = VERSION
    var pending: String = path + ".tmp"
    var output: FileAccess = FileAccess.open(pending, FileAccess.WRITE)
    if output == null:
        push_warning("Skyval: cannot open save for writing: %s" % error_string(FileAccess.get_open_error()))
        return false
    output.store_string(JSON.stringify(serialized))
    output.flush()
    output.close()
    var rename_error: Error = DirAccess.rename_absolute(pending, path)
    if rename_error != OK:
        DirAccess.remove_absolute(pending)
        push_warning("Skyval: cannot finalize save: %s" % error_string(rename_error))
        return false
    return true


func list_profiles() -> Array[Dictionary]:
    var profiles: Array[Dictionary] = []
    for data in _list_all_valid():
        # Only root files represent characters. Snapshots never create a
        # second character in Select Character.
        if str(data.get("save_kind", "")) == KIND_PROFILE:
            profiles.append(data)
    profiles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        if int(a.get("last_played", 0)) == int(b.get("last_played", 0)):
            return str(a.get("profile_id", "")) > str(b.get("profile_id", ""))
        return int(a.get("last_played", 0)) > int(b.get("last_played", 0))
    )
    return profiles


func list_saves(profile_id: String = "") -> Array[Dictionary]:
    var saves: Array[Dictionary] = []
    var valid_ids: Dictionary = {}
    for profile in list_profiles():
        valid_ids[str(profile.get("profile_id", ""))] = true
    for data in _list_all_valid():
        var id: String = str(data.get("profile_id", ""))
        if not valid_ids.has(id) or (not profile_id.is_empty() and id != profile_id):
            continue
        saves.append(data)
    saves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        if int(a.get("saved_at", 0)) == int(b.get("saved_at", 0)):
            return str(a.get("path", "")) > str(b.get("path", ""))
        return int(a.get("saved_at", 0)) > int(b.get("saved_at", 0))
    )
    return saves


func latest_save(profile_id: String = "") -> Dictionary:
    var saves: Array[Dictionary] = list_saves(profile_id)
    return saves[0] if not saves.is_empty() else {}


func quick_save_for(profile_id: String) -> Dictionary:
    for data in list_saves(profile_id):
        if str(data.get("save_kind", "")) == KIND_QUICK:
            return data
    return {}


func slot_path(profile: Dictionary, kind: String) -> String:
    if kind not in [KIND_MANUAL, KIND_QUICK]:
        return ""
    var root_path: String = str(profile.get("path", ""))
    if not _is_profile_path(root_path):
        return ""
    var base: String = root_path.trim_suffix(".json")
    if kind == KIND_QUICK:
        return base + "~quick.json"
    for attempt in range(30):
        var candidate: String = "%s~save-%s-%05d.json" % [base, str(_timestamp_ms()), randi_range(0, 99999)]
        if not FileAccess.file_exists(candidate):
            return candidate
    return ""


func delete_profile(path: String) -> bool:
    var profile: Dictionary = read_profile(path)
    if profile.is_empty() or str(profile.get("save_kind", "")) != KIND_PROFILE:
        return false
    var id: String = str(profile.get("profile_id", ""))
    # Delete snapshots first so an interrupted deletion cannot leave
    # visible orphan snapshots without a character profile.
    for snapshot in list_saves(id):
        var snapshot_path: String = str(snapshot.get("path", ""))
        if snapshot_path == path:
            continue
        if DirAccess.remove_absolute(snapshot_path) != OK:
            return false
    return DirAccess.remove_absolute(path) == OK


func _list_all_valid() -> Array[Dictionary]:
    var found: Array[Dictionary] = []
    var folder: DirAccess = DirAccess.open(directory_path())
    if folder == null:
        return found
    folder.list_dir_begin()
    while true:
        var filename: String = folder.get_next()
        if filename.is_empty():
            break
        if folder.current_is_dir() or not filename.ends_with(".json"):
            continue
        var parsed: Dictionary = read_profile(directory_path().path_join(filename))
        if not parsed.is_empty():
            found.append(parsed)
    folder.list_dir_end()
    return found


func _is_profile_path(path: String) -> bool:
    return path.get_base_dir() == directory_path() and path.get_file().ends_with(".json") and not path.get_file().begins_with(".")


func _timestamp_ms() -> int:
    return int(Time.get_unix_time_from_system() * 1000.0)
