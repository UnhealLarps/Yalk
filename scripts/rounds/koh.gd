extends Resource

const FLAG_SCENE: PackedScene = preload("res://prefabs/forRounds/flag_for_koh.tscn")
const FLAG_START_Y := -22.0
const FLAG_TARGET_Y := -256.0
const FLAG_RAISE_SPEED := 4.0
const FLAG_CLEARANCE_MASK := 15

var mode_id := "koh"
var mode_name := "King of the Hill"
var description := "Hold the flag alone. Contestants stop its progress."
var image: Texture2D = ResourceLoader.load("res://sprites/ui/rounds/koh.png") as Texture2D if ResourceLoader.exists("res://sprites/ui/rounds/koh.png") else null
var music_path := ""
var teams := [
	{"name": "Contender", "percentage": 100.0, "items": ["", ""]}
]
var outlines: Array[Dictionary] = []
var flag_instance: Node2D = null
var flag_position := Vector2.ZERO
var flag_y := FLAG_START_Y
var remote_flag_y := FLAG_START_Y
var last_player_id := 0
var flag_active := false

func assign_roles(player_ids: Array[int]) -> Dictionary:
	var result: Dictionary = {}
	for peer_id in player_ids:
		result[peer_id] = "Contender"
	return result

func get_team(team_name: String) -> Dictionary:
	for team_value in teams:
		if team_value is Dictionary and str(team_value.get("name", "")) == team_name:
			return team_value.duplicate(true)
	return {}

func start_round(_player_ids: Array[int]):
	_remove_flag()
	flag_position = _find_flag_position()
	flag_y = FLAG_START_Y
	remote_flag_y = FLAG_START_Y
	last_player_id = 0
	flag_active = true
	_spawn_flag(flag_position)

func process_round(delta: float, player_ids: Array[int]):
	if not NetworkManager.is_server() or not flag_active:
		return
	if flag_instance == null or not is_instance_valid(flag_instance):
		_spawn_flag(flag_position)
	if flag_instance == null:
		return
	var area := flag_instance.get_node_or_null("CaptureArea") as Area2D
	if area == null:
		return
	var occupants: Array[int] = []
	for body_value in area.get_overlapping_bodies():
		if not body_value is CharacterBody2D:
			continue
		var player := body_value as CharacterBody2D
		var peer_id := int(player.get("network_player_id"))
		if peer_id <= 0 or not player_ids.has(peer_id) or player.get("is_dead") == true:
			continue
		if not occupants.has(peer_id):
			occupants.append(peer_id)
	if occupants.size() != 1:
		return
	last_player_id = occupants[0]
	flag_y = move_toward(flag_y, FLAG_TARGET_Y, FLAG_RAISE_SPEED * delta)
	_apply_flag_height(flag_y)

func get_winner(player_ids: Array[int], _roles: Dictionary) -> String:
	if not flag_active or flag_y > FLAG_TARGET_Y or last_player_id <= 0 or not player_ids.has(last_player_id):
		return ""
	var nickname := NicknameManager.get_nickname(last_player_id)
	return nickname if not nickname.is_empty() else "Player %d" % last_player_id

func get_network_state() -> Dictionary:
	return {
		"active": flag_active,
		"position": flag_position,
		"flag_y": flag_y,
		"last_player_id": last_player_id
	}

func sync_network_state(state: Dictionary):
	if state.get("active", false) != true:
		flag_active = false
		_remove_flag()
		return
	flag_active = true
	var position_value: Variant = state.get("position", Vector2.ZERO)
	if position_value is Vector2:
		if flag_instance == null or not is_instance_valid(flag_instance) or flag_position.distance_squared_to(position_value) > 0.01:
			flag_position = position_value
			_remove_flag()
			_spawn_flag(flag_position)
	flag_y = float(state.get("flag_y", FLAG_START_Y))
	remote_flag_y = flag_y
	last_player_id = int(state.get("last_player_id", 0))
	if flag_instance != null and is_instance_valid(flag_instance):
		_apply_flag_height(remote_flag_y)

func client_process(delta: float):
	if NetworkManager.is_server() or not flag_active or flag_instance == null or not is_instance_valid(flag_instance):
		return
	var sprite := flag_instance.get_node_or_null("Flag") as Sprite2D
	if sprite != null:
		sprite.position.y = move_toward(sprite.position.y, remote_flag_y, 8.0 * delta)

func end_round():
	flag_active = false
	last_player_id = 0
	_remove_flag()

func _spawn_flag(position: Vector2):
	var scene_tree := Engine.get_main_loop() as SceneTree
	if scene_tree == null or scene_tree.current_scene == null:
		return
	var instance := FLAG_SCENE.instantiate() as Node2D
	if instance == null:
		return
	instance.name = "KingOfTheHillFlag"
	scene_tree.current_scene.add_child(instance)
	instance.global_position = position
	flag_instance = instance
	_apply_flag_height(FLAG_START_Y if NetworkManager.is_server() else remote_flag_y)

func _remove_flag():
	if flag_instance != null and is_instance_valid(flag_instance):
		flag_instance.queue_free()
	flag_instance = null

func _apply_flag_height(value: float):
	if flag_instance == null or not is_instance_valid(flag_instance):
		return
	var sprite := flag_instance.get_node_or_null("Flag") as Sprite2D
	if sprite != null:
		sprite.position.y = value

func _find_flag_position() -> Vector2:
	var map_manager := NetworkManager.get_map_manager()
	if map_manager == null:
		return Vector2.ZERO
	var map_value: Variant = map_manager.get("current_map")
	var map := map_value as Node2D
	if map == null or not is_instance_valid(map):
		return Vector2.ZERO
	var center := map.global_position
	var spawns_node := map.find_child("Spawns", true, false)
	if spawns_node != null:
		var spawn_positions: Array[Vector2] = []
		for child in spawns_node.get_children():
			if child is Node2D:
				spawn_positions.append((child as Node2D).global_position)
		if not spawn_positions.is_empty():
			center = Vector2.ZERO
			for position in spawn_positions:
				center += position
			center /= float(spawn_positions.size())
	var scene_tree := Engine.get_main_loop() as SceneTree
	if scene_tree == null or scene_tree.current_scene == null:
		return center
	var current_scene := scene_tree.current_scene as Node2D
	if current_scene == null:
		return center
	var world := current_scene.get_world_2d()
	if world == null:
		return center
	var space := world.direct_space_state
	var offsets: Array[float] = [0.0]
	for distance in range(48, 769, 48):
		offsets.append(float(distance))
		offsets.append(-float(distance))
	for offset in offsets:
		var candidate_x := center.x + offset
		var floor_values: Array[float] = []
		var has_floor := true
		for sample_offset in [-56.0, 0.0, 56.0]:
			var floor_y := _probe_floor_y(space, candidate_x + sample_offset, center.y)
			if floor_y > 100000000.0:
				has_floor = false
				break
			floor_values.append(floor_y)
		if not has_floor:
			continue
		var minimum_y := minf(floor_values[0], minf(floor_values[1], floor_values[2]))
		var maximum_y := maxf(floor_values[0], maxf(floor_values[1], floor_values[2]))
		if maximum_y - minimum_y > 20.0:
			continue
		var floor_position := Vector2(candidate_x, (floor_values[0] + floor_values[1] + floor_values[2]) / 3.0)
		if _has_flag_clearance(space, floor_position):
			return floor_position
	var fallback_y := _probe_floor_y(space, center.x, center.y)
	if fallback_y <= 100000000.0:
		return Vector2(center.x, fallback_y)
	return center

func _probe_floor_y(space: PhysicsDirectSpaceState2D, x: float, reference_y: float) -> float:
	var query := PhysicsRayQueryParameters2D.create(Vector2(x, reference_y - 450.0), Vector2(x, reference_y + 550.0), 1)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return 100000001.0
	var hit_position: Vector2 = hit["position"]
	return hit_position.y

func _has_flag_clearance(space: PhysicsDirectSpaceState2D, position: Vector2) -> bool:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(132.0, 270.0)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, position + Vector2(0.0, -141.0))
	query.collision_mask = FLAG_CLEARANCE_MASK
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return space.intersect_shape(query, 1).is_empty()
