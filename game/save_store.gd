extends RefCounted
## A directory per character: saves/<id>-<character>/profile.json,
## quick.json and named manual saves. Legacy flat v2 files are migrated
## by renaming them; migration never overwrites existing files.

const VERSION := 2
const FALLBACK_DIR := "user://saves"
const KIND_PROFILE := "profile"
const KIND_MANUAL := "manual"
const KIND_QUICK := "quick"
const PROFILE_FILE := "profile.json"
const RECENT_FILE := "last_opened.json"


func directory_path() -> String:
    var override: String = OS.get_environment("SKYVAL_SAVES_DIR").strip_edges()
    return override.trim_suffix("/") if not override.is_empty() else FALLBACK_DIR


func new_profile(name: String) -> Dictionary:
    var clean_name: String = name.strip_edges()
    if clean_name.is_empty():
        return {}
    for attempt in range(30):
        var profile_id: String = "%s%05d" % [str(int(Time.get_unix_time_from_system())), randi_range(0, 99999)]
        var directory: String = directory_path().path_join("%s-%s" % [profile_id, _safe_filename(clean_name)])
        if DirAccess.dir_exists_absolute(directory) or FileAccess.file_exists(directory + ".json"):
            continue
        var now: int = _timestamp_ms()
        return {
            "version": VERSION,
            "profile_id": profile_id,
            "character_name": clean_name,
            "created_at": now,
            "last_played": now,
            "saved_at": now,
            "save_kind": KIND_PROFILE,
            "path": directory.path_join(PROFILE_FILE),
        }
    return {}


func read_profile(path: String) -> Dictionary:
    if not _is_save_path(path) or not FileAccess.file_exists(path):
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
        if typeof(coordinate) not in [TYPE_FLOAT, TYPE_INT]:
            return {}
    data["save_kind"] = kind
    data["saved_at"] = int(data.get("saved_at", data.get("created_at", FileAccess.get_modified_time(path) * 1000)))
    data["path"] = path
    return data


func write_profile(path: String, data: Dictionary) -> bool:
    if not _is_save_path(path):
        return false
    return _write_json(path, data)


func list_profiles() -> Array[Dictionary]:
    _migrate_legacy_files()
    var profiles: Array[Dictionary] = []
    var seen: Dictionary = {}
    for data in _list_all_valid():
        if str(data.get("save_kind", "")) != KIND_PROFILE:
            continue
        var id: String = str(data.get("profile_id", ""))
        if seen.has(id):
            continue
        seen[id] = true
        profiles.append(data)
    profiles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        if int(a.get("last_played", 0)) == int(b.get("last_played", 0)):
            return str(a.get("profile_id", "")) > str(b.get("profile_id", ""))
        return int(a.get("last_played", 0)) > int(b.get("last_played", 0))
    )
    return profiles


func profile_by_id(profile_id: String) -> Dictionary:
    for profile in list_profiles():
        if str(profile.get("profile_id", "")) == profile_id:
            return profile
    return {}


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


func slot_path(profile: Dictionary, kind: String, save_name: String = "") -> String:
    if kind not in [KIND_QUICK, KIND_MANUAL]:
        return ""
    var profile_id: String = str(profile.get("profile_id", ""))
    var root: Dictionary = profile_by_id(profile_id)
    if root.is_empty():
        return ""
    var root_path: String = str(root.get("path", ""))
    var directory: String = root_path.get_base_dir()
    if root_path.get_base_dir() == directory_path():
        # Only used if a legacy file cannot be migrated yet.
        directory = directory_path()
        var base: String = root_path.trim_suffix(".json")
        if kind == KIND_QUICK:
            return base + "~quick.json"
        return _unique_slot(base + "~save-", save_name)
    if kind == KIND_QUICK:
        return directory.path_join("quick.json")
    return _unique_slot(directory.path_join("save-"), save_name)


func last_opened_profile() -> Dictionary:
    var profiles: Array[Dictionary] = list_profiles()
    if profiles.is_empty():
        return {}
    var marker_path: String = directory_path().path_join(RECENT_FILE)
    if FileAccess.file_exists(marker_path):
        var marker: Variant = JSON.parse_string(FileAccess.get_file_as_string(marker_path))
        if marker is Dictionary:
            var selected_id: String = str(marker.get("profile_id", ""))
            for profile in profiles:
                if str(profile.get("profile_id", "")) == selected_id:
                    return profile
    # Upgrade from v2: most recently opened profile is a safe fallback.
    return profiles[0]


func remember_opened(profile_id: String) -> bool:
    if profile_by_id(profile_id).is_empty():
        return false
    return _write_json(directory_path().path_join(RECENT_FILE), {
        "profile_id": profile_id,
        "updated_at": _timestamp_ms(),
    })


func delete_profile(path: String) -> bool:
    var profile: Dictionary = read_profile(path)
    if profile.is_empty() or str(profile.get("save_kind", "")) != KIND_PROFILE:
        return false
    var id: String = str(profile.get("profile_id", ""))
    # Only delete validated files owned by this character.
    for snapshot in list_saves(id):
        var target: String = str(snapshot.get("path", ""))
        if target == path:
            continue
        if DirAccess.remove_absolute(target) != OK:
            return false
    if DirAccess.remove_absolute(path) != OK:
        return false
    var folder: String = path.get_base_dir()
    if folder != directory_path() and DirAccess.dir_exists_absolute(folder):
        # The folder should be empty; do not delete unknown user files.
        DirAccess.remove_absolute(folder)
    var marker: String = directory_path().path_join(RECENT_FILE)
    if FileAccess.file_exists(marker):
        var last: Variant = JSON.parse_string(FileAccess.get_file_as_string(marker))
        if last is Dictionary and str(last.get("profile_id", "")) == id:
            DirAccess.remove_absolute(marker)
    return true


func _unique_slot(prefix: String, save_name: String) -> String:
    var cleaned: String = _safe_filename(save_name)
    for attempt in range(30):
        var filename: String = "%s%s-%05d-%s.json" % [prefix, str(_timestamp_ms()), randi_range(0, 99999), cleaned]
        if not FileAccess.file_exists(filename):
            return filename
    return ""


func _safe_filename(name: String) -> String:
    var clean: String = name.strip_edges().replace(" ", "_")
    for invalid in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "~"]:
        clean = clean.replace(invalid, "_")
    clean = clean.trim_prefix(".")
    return clean.substr(0, 28) if not clean.is_empty() else "save"


func _write_json(path: String, data: Dictionary) -> bool:
    if not _is_save_path(path) and path != directory_path().path_join(RECENT_FILE):
        return false
    var error: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
    if error != OK:
        push_warning("Skyval: could not create saves folder: %s" % error_string(error))
        return false
    var result: Dictionary = data.duplicate(true)
    result.erase("path")
    if path != directory_path().path_join(RECENT_FILE):
        result["version"] = VERSION
    var temp: String = path + ".tmp"
    var file: FileAccess = FileAccess.open(temp, FileAccess.WRITE)
    if file == null:
        push_warning("Skyval: cannot write: %s" % error_string(FileAccess.get_open_error()))
        return false
    file.store_string(JSON.stringify(result))
    file.flush()
    file.close()
    var renamed: Error = DirAccess.rename_absolute(temp, path)
    if renamed != OK:
        DirAccess.remove_absolute(temp)
        push_warning("Skyval: cannot finalize save: %s" % error_string(renamed))
        return false
    return true


func _list_all_valid() -> Array[Dictionary]:
    var found: Array[Dictionary] = []
    var folder: DirAccess = DirAccess.open(directory_path())
    if folder == null:
        return found
    folder.list_dir_begin()
    while true:
        var name: String = folder.get_next()
        if name.is_empty():
            break
        var path: String = directory_path().path_join(name)
        if folder.current_is_dir():
            var sub: DirAccess = DirAccess.open(path)
            if sub == null:
                continue
            sub.list_dir_begin()
            while true:
                var filename: String = sub.get_next()
                if filename.is_empty():
                    break
                if not sub.current_is_dir() and filename.ends_with(".json"):
                    var data: Dictionary = read_profile(path.path_join(filename))
                    if not data.is_empty():
                        found.append(data)
            sub.list_dir_end()
        elif name.ends_with(".json") and name != RECENT_FILE:
            var legacy: Dictionary = read_profile(path)
            if not legacy.is_empty():
                found.append(legacy)
    folder.list_dir_end()
    return found


func _migrate_legacy_files() -> void:
    var folder: DirAccess = DirAccess.open(directory_path())
    if folder == null:
        return
    # Discover old root profile files before moving any of them.
    var legacy_profiles: Array[String] = []
    folder.list_dir_begin()
    while true:
        var filename: String = folder.get_next()
        if filename.is_empty():
            break
        if folder.current_is_dir() or not filename.ends_with(".json") or filename == RECENT_FILE or filename.contains("~"):
            continue
        var old_path: String = directory_path().path_join(filename)
        var parsed: Dictionary = read_profile(old_path)
        if not parsed.is_empty() and str(parsed.get("save_kind", "")) == KIND_PROFILE:
            legacy_profiles.append(filename)
    folder.list_dir_end()
    for old_filename in legacy_profiles:
        var base: String = old_filename.trim_suffix(".json")
        var new_dir: String = directory_path().path_join(base)
        if DirAccess.make_dir_recursive_absolute(new_dir) != OK:
            continue
        var old_root: String = directory_path().path_join(old_filename)
        var new_root: String = new_dir.path_join(PROFILE_FILE)
        if FileAccess.file_exists(new_root):
            # Never overwrite an existing profile or delete its legacy copy.
            continue
        # Move snapshots before the profile; retry remains safe if an
        # interrupted migration leaves some snapshots already in the folder.
        var snapshots_ok: bool = true
        var scan: DirAccess = DirAccess.open(directory_path())
        if scan == null:
            continue
        var to_move: Array[String] = []
        scan.list_dir_begin()
        while true:
            var current: String = scan.get_next()
            if current.is_empty():
                break
            if not scan.current_is_dir() and current.begins_with(base + "~") and current.ends_with(".json"):
                to_move.append(current)
        scan.list_dir_end()
        for filename in to_move:
            var suffix: String = filename.substr(base.length() + 1)
            var source: String = directory_path().path_join(filename)
            var target: String = new_dir.path_join(suffix)
            if FileAccess.file_exists(target):
                # Preserve the old file if a destination already exists.
                snapshots_ok = false
                continue
            if DirAccess.rename_absolute(source, target) != OK:
                snapshots_ok = false
        if snapshots_ok:
            if DirAccess.rename_absolute(old_root, new_root) != OK:
                push_warning("Skyval: could not migrate profile: %s" % old_root)


func _is_save_path(path: String) -> bool:
    var parent: String = path.get_base_dir()
    if parent == directory_path():
        # Old flat v2 save names remain valid until they are migrated.
        return path.get_file().ends_with(".json") and path.get_file() != RECENT_FILE and not path.get_file().begins_with(".")
    return parent.get_base_dir() == directory_path() and path.get_file().ends_with(".json") and not path.get_file().begins_with(".") and not parent.get_file().begins_with(".")


func _timestamp_ms() -> int:
    return int(Time.get_unix_time_from_system() * 1000.0)
