extends RefCounted
## Per-character save files. On PortMaster SKYVAL_SAVES_DIR points to
## /roms/ports/skyval/saves; in the editor the fallback is user://saves.

const VERSION := 2
const FALLBACK_DIR := "user://saves"


func directory_path() -> String:
    var override: String = OS.get_environment("SKYVAL_SAVES_DIR").strip_edges()
    return override.trim_suffix("/") if not override.is_empty() else FALLBACK_DIR


func new_profile(name: String) -> Dictionary:
    var clean_name: String = name.strip_edges()
    if clean_name.is_empty():
        return {}
    var profile_id: String = ""
    var filename: String = ""
    for attempt in range(30):
        profile_id = "%s%05d" % [str(int(Time.get_unix_time_from_system())), randi_range(0, 99999)]
        filename = "%s-%s.json" % [profile_id, clean_name.replace(" ", "_")]
        if not FileAccess.file_exists(directory_path().path_join(filename)):
            break
    if FileAccess.file_exists(directory_path().path_join(filename)):
        return {}
    var now: int = int(Time.get_unix_time_from_system())
    return {
        "version": VERSION,
        "profile_id": profile_id,
        "character_name": clean_name,
        "created_at": now,
        "last_played": now,
        "path": directory_path().path_join(filename),
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
    var position: Variant = data.get("player_position")
    if not position is Array or position.size() != 2:
        return {}
    for coordinate in position:
        if typeof(coordinate) != TYPE_INT and typeof(coordinate) != TYPE_FLOAT:
            return {}
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
    # A temporary file avoids truncating a valid checkpoint on an interrupted write.
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
    var directory: DirAccess = DirAccess.open(directory_path())
    if directory == null:
        return profiles
    directory.list_dir_begin()
    while true:
        var filename: String = directory.get_next()
        if filename.is_empty():
            break
        if directory.current_is_dir() or not filename.ends_with(".json"):
            continue
        var data: Dictionary = read_profile(directory_path().path_join(filename))
        if not data.is_empty():
            profiles.append(data)
    directory.list_dir_end()
    profiles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        if int(a.get("last_played", 0)) == int(b.get("last_played", 0)):
            return str(a.get("profile_id", "")) > str(b.get("profile_id", ""))
        return int(a.get("last_played", 0)) > int(b.get("last_played", 0))
    )
    return profiles


func delete_profile(path: String) -> bool:
    if not _is_profile_path(path) or not FileAccess.file_exists(path):
        return false
    return DirAccess.remove_absolute(path) == OK


func _is_profile_path(path: String) -> bool:
    return path.get_base_dir() == directory_path() and path.get_file().ends_with(".json") and not path.get_file().begins_with(".")
