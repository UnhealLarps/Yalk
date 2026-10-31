extends Node2D

const GAME_VERSION := "0.1"

var rep := Reporter.new("MapManager")
var current_map_name := ""
var current_map: Node2D = null
var current_manifest: Dictionary = {}
var map_revision := 0
var initialized := false
var mounted_packs: Dictionary = {}
var manifest_cache: Dictionary = {}

func _ready():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://maps"))

func initialize_for_server() -> bool:
	if initialized:
		return false
	initialized = true
	var available_maps: Array[String] = get_available_maps()
	available_maps.shuffle()
	for map_name in available_maps:
		if load_map(map_name):
			return true
	rep.error("No maps with a valid manifest for game version %s were found." % GAME_VERSION)
	return false

func get_available_maps(player_count: int = -1) -> Array[String]:
	var files: Dictionary = {}
	_scan_map_directory("user://maps", files)
	_scan_map_directory("res://maps", files)
	var executable_maps := OS.get_executable_path().get_base_dir().path_join("maps")
	if not OS.has_feature("editor"):
		_scan_map_directory(executable_maps, files)
	var result: Array[String] = []
	for value in files.keys():
		var map_name := str(value)
		var manifest := _get_map_manifest(map_name)
		if manifest.is_empty() or not _is_version_supported(manifest):
			continue
		if player_count > 0 and not _manifest_supports_players(manifest, player_count):
			continue
		result.append(map_name)
	result.sort()
	return result

func _scan_map_directory(directory_path: String, result: Dictionary):
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.get_extension().to_lower() == "pck":
			var map_name := file_name.get_basename()
			if not result.has(map_name):
				result[map_name] = directory_path.path_join(file_name)
		file_name = directory.get_next()
	directory.list_dir_end()

func get_current_map_name() -> String:
	return current_map_name

func get_map_revision() -> int:
	return map_revision

func is_current_map_compatible(player_count: int) -> bool:
	return not current_manifest.is_empty() and _is_version_supported(current_manifest) and _manifest_supports_players(current_manifest, player_count)

func ensure_map_for_player_count(player_count: int) -> bool:
	if player_count < 1:
		return false
	if is_current_map_compatible(player_count):
		return true
	return change_to_random_map(player_count)

func reset_current_map(player_count: int = -1) -> bool:
	if current_map_name.is_empty():
		return false
	if player_count > 0 and not is_current_map_compatible(player_count):
		return change_to_random_map(player_count)
	return load_map(current_map_name, true, player_count)

func load_map(map_name: String, force_reload: bool = false, player_count: int = -1) -> bool:
	var normalized_name := map_name.trim_suffix(".pck").strip_edges()
	if normalized_name.is_empty():
		return false
	if not force_reload and current_map_name == normalized_name and current_map != null and is_instance_valid(current_map):
		return player_count <= 0 or is_current_map_compatible(player_count)
	var manifest := _get_map_manifest(normalized_name)
	if manifest.is_empty():
		rep.error("Map '%s' has no valid manifest.json." % normalized_name)
		return false
	if not _is_version_supported(manifest):
		rep.warn("Map '%s' requires game version %s; current map version is %s." % [normalized_name, str(manifest.get("required_game_version", "?")), GAME_VERSION])
		return false
	if player_count > 0 and not _manifest_supports_players(manifest, player_count):
		var players: Dictionary = manifest.get("players", {})
		rep.warn("Map '%s' supports %d-%d players, but %d are connected." % [normalized_name, int(players.get("min_count", 1)), int(players.get("max_count", 0)), player_count])
		return false
	var scene_path := _get_map_scene_path(normalized_name)
	if scene_path.is_empty():
		rep.error("Map '%s' is mounted, but map.tscn was not found." % normalized_name)
		return false
	var packed_scene := ResourceLoader.load(scene_path) as PackedScene
	if packed_scene == null:
		rep.error("Unable to load map scene: %s" % scene_path)
		return false
	var instance := packed_scene.instantiate() as Node2D
	if instance == null:
		rep.error("Map root must be Node2D: %s" % scene_path)
		return false
	var had_map := current_map != null and is_instance_valid(current_map)
	if had_map:
		_prepare_scene_for_reload()
	for child in get_children():
		remove_child(child)
		GC.destroy(child)
	instance.name = "LoadedMap"
	add_child(instance)
	current_map = instance
	current_map_name = normalized_name
	current_manifest = manifest
	map_revision += 1
	_spawn_reference_items()
	_mark_map_items()
	if NetworkManager.has_method("on_map_loaded"):
		NetworkManager.on_map_loaded()
	if not had_map and NetworkManager.is_server() and NetworkManager.has_method("move_players_to_map_spawns"):
		NetworkManager.move_players_to_map_spawns(NetworkManager.get_connected_peer_ids())
	rep.info("Loaded map: %s (revision %d)" % [normalized_name, map_revision])
	return true

func _get_map_scene_path(map_name: String) -> String:
	var candidates: Array[String] = ["res://maps/%s/map.tscn" % map_name, "res://maps/%s.pck/map.tscn" % map_name]
	for candidate in candidates:
		if ResourceLoader.exists(candidate):
			return candidate
	return ""

func _get_map_manifest(map_name: String) -> Dictionary:
	if manifest_cache.has(map_name):
		var cached: Variant = manifest_cache[map_name]
		return cached.duplicate(true) if cached is Dictionary else {}
	if not _ensure_pack_mounted(map_name):
		manifest_cache[map_name] = {}
		rep.warn("Unable to mount map pack '%s'." % map_name)
		return {}
	var manifest_path := ""
	var candidates: Array[String] = ["res://maps/%s/manifest.json" % map_name, "res://maps/%s.pck/manifest.json" % map_name]
	for candidate in candidates:
		if FileAccess.file_exists(candidate):
			manifest_path = candidate
			break
	if manifest_path.is_empty():
		manifest_cache[map_name] = {}
		rep.warn("Map '%s' has no manifest.json beside map.tscn." % map_name)
		return {}
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		manifest_cache[map_name] = {}
		rep.warn("Unable to read map manifest: %s" % manifest_path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		manifest_cache[map_name] = {}
		rep.warn("Map manifest is not a JSON object: %s" % manifest_path)
		return {}
	var manifest: Dictionary = parsed
	var required_version: Variant = manifest.get("required_game_version", null)
	var players_value: Variant = manifest.get("players", null)
	if not required_version is String or not players_value is Dictionary:
		manifest_cache[map_name] = {}
		rep.warn("Map manifest must define required_game_version and players: %s" % manifest_path)
		return {}
	var min_value: Variant = players_value.get("min_count", null)
	var max_value: Variant = players_value.get("max_count", null)
	if (not min_value is int and not min_value is float) or (not max_value is int and not max_value is float):
		manifest_cache[map_name] = {}
		rep.warn("Map manifest players must define numeric min_count and max_count: %s" % manifest_path)
		return {}
	var min_count := int(min_value)
	var max_count := int(max_value)
	if min_count < 1 or max_count < min_count or float(min_value) != float(min_count) or float(max_value) != float(max_count):
		manifest_cache[map_name] = {}
		rep.warn("Map manifest has invalid player limits: %s" % manifest_path)
		return {}
	manifest_cache[map_name] = manifest.duplicate(true)
	return manifest.duplicate(true)

func _ensure_pack_mounted(map_name: String) -> bool:
	var pack_path := _resolve_pack_path(map_name)
	if pack_path.is_empty():
		return false
	if mounted_packs.has(pack_path):
		return true
	if not ProjectSettings.load_resource_pack(pack_path, false):
		return false
	mounted_packs[pack_path] = true
	return true

func _is_version_supported(manifest: Dictionary) -> bool:
	var required_version: Variant = manifest.get("required_game_version", null)
	if not required_version is String:
		return false
	var current_parts := _version_parts(GAME_VERSION)
	var required_parts := _version_parts(str(required_version))
	if current_parts.is_empty() or required_parts.is_empty():
		return false
	var part_count: int = maxi(current_parts.size(), required_parts.size())
	for index in range(part_count):
		var current_part := int(current_parts[index]) if index < current_parts.size() else 0
		var required_part := int(required_parts[index]) if index < required_parts.size() else 0
		if current_part > required_part:
			return true
		if current_part < required_part:
			return false
	return true

func _version_parts(version: String) -> Array[int]:
	var result: Array[int] = []
	for part in version.strip_edges().split("."):
		var digits := ""
		for character in part:
			if character >= "0" and character <= "9":
				digits += character
			elif not digits.is_empty():
				break
		if digits.is_empty():
			return []
		result.append(int(digits))
	return result

func _manifest_supports_players(manifest: Dictionary, player_count: int) -> bool:
	var players_value: Variant = manifest.get("players", null)
	if not players_value is Dictionary:
		return false
	var players: Dictionary = players_value
	var min_count := int(players.get("min_count", 1))
	var max_count := int(players.get("max_count", 0))
	return player_count >= min_count and player_count <= max_count

func _prepare_scene_for_reload():
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var nodes: Array[Node] = []
	for node: Node in scene.find_children("*", "", true, false):
		nodes.append(node)
	for node in nodes:
		if node is CharacterBody2D and node.has_method("drop_all_items"):
			node.call("drop_all_items")
	var reference_items: Array[Node] = []
	for node in scene.find_children("*", "", true, false):
		if node is RigidBody2D and (node.has_meta("map_reference_id") or node.has_meta("map_spawned_item") or node.has_meta("network_item_id") or node.has_meta("network_scene_path")):
			reference_items.append(node)
	for item in reference_items:
		if not is_instance_valid(item):
			continue
		var parent := item.get_parent()
		if parent != null:
			parent.remove_child(item)
		GC.destroy(item)

func _spawn_reference_items():
	if current_map == null or not is_instance_valid(current_map):
		return
	var references: Array[Node2D] = []
	for node: Node in current_map.find_children("*", "Node2D", true, false):
		if node.name.contains("Reference") and (node.has_meta("id") or node.has_meta("ID")):
			references.append(node as Node2D)
	for reference in references:
		if reference.has_meta("reference_spawned"):
			continue
		var resource_id: Variant = reference.get_meta("id") if reference.has_meta("id") else reference.get_meta("ID")
		var scene_path := _resolve_reference_scene_path(resource_id)
		if scene_path.is_empty():
			rep.warn("Reference scene not found for ID '%s': %s" % [str(resource_id), reference.get_path()])
			continue
		var packed := ResourceLoader.load(scene_path) as PackedScene
		if packed == null:
			rep.warn("Reference resource is not a PackedScene: %s" % scene_path)
			continue
		var instance := packed.instantiate() as Node2D
		if instance == null:
			rep.warn("Reference scene root must be Node2D: %s" % scene_path)
			continue
		current_map.add_child(instance)
		instance.global_transform = reference.global_transform
		instance.set_meta("map_reference_id", str(resource_id))
		instance.set_meta("map_reference_key", current_map_name + ":" + str(current_map.get_path_to(reference)))
		reference.set_meta("reference_spawned", true)

func _mark_map_items():
	if current_map == null or not is_instance_valid(current_map):
		return
	for node in current_map.find_children("*", "", true, false):
		if node is RigidBody2D:
			node.set_meta("map_spawned_item", true)

func _resolve_reference_scene_path(resource_id: Variant) -> String:
	if not resource_id is String and not resource_id is StringName:
		return ""
	var id := str(resource_id).strip_edges().replace("\\", "/")
	if id.is_empty() or id.contains("..") or id.begins_with("user://"):
		return ""
	var candidates: Array[String] = []
	if id.begins_with("res://"):
		candidates.append(id if id.ends_with(".tscn") else id + ".tscn")
	else:
		id = id.trim_prefix("/")
		id = id.trim_prefix("prefabs/")
		candidates.append("res://prefabs/" + (id if id.ends_with(".tscn") else id + ".tscn"))
	for candidate in candidates:
		if ResourceLoader.exists(candidate):
			return candidate
	return ""

func change_to_random_map(player_count: int = -1) -> bool:
	var available_maps := get_available_maps(player_count)
	var alternatives: Array[String] = []
	for map_name in available_maps:
		if map_name != current_map_name:
			alternatives.append(map_name)
	alternatives.shuffle()
	if alternatives.is_empty():
		if available_maps.has(current_map_name):
			return load_map(current_map_name, true, player_count)
		return false
	for map_name in alternatives:
		if load_map(map_name, true, player_count):
			return true
	return false

func change_to_next_map() -> bool:
	return change_to_random_map()

func _resolve_pack_path(map_name: String) -> String:
	var candidate := "user://maps/%s.pck" % map_name
	if FileAccess.file_exists(candidate):
		return candidate
	candidate = "res://maps/%s.pck" % map_name
	if FileAccess.file_exists(candidate):
		return candidate
	var executable_candidate := OS.get_executable_path().get_base_dir().path_join("maps").path_join("%s.pck" % map_name)
	if not OS.has_feature("editor") and FileAccess.file_exists(executable_candidate):
		return executable_candidate
	return ""
