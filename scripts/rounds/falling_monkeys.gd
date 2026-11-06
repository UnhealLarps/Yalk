extends Resource

const MONKEY_SCENE_PATH := "res://prefabs/weapons/monkey.tscn"
const MUSIC_PATH := "res://audio/music/rounds/DraggedThroughHellfire.mp3"
const SPAWN_INTERVAL_MIN := 0.9
const SPAWN_INTERVAL_MAX := 1.2
const MONKEYS_PER_WAVE := 1
const MAX_ACTIVE_MONKEYS := 4
const MONKEY_SPEED_MIN := 1050.0
const MONKEY_SPEED_MAX := 1450.0
const SPAWN_HEIGHT_MIN := 1700.0
const SPAWN_HEIGHT_MAX := 2400.0

var mode_id := "falling_monkeys"
var mode_name := "Falling Monkeys"
var description := "Avoid the falling monkeys. Push other players and stay alive."
var image: Texture2D = ResourceLoader.load("res://sprites/ui/rounds/fm.png") as Texture2D if ResourceLoader.exists("res://sprites/ui/rounds/fm.png") else null
var music_path := MUSIC_PATH
var teams := [
	{"name": "Survivor", "percentage": 100.0, "items": ["", ""]}
]
var outlines: Array[Dictionary] = []
var monkey_scene: PackedScene = null
var monkey_scene_warning_shown := false
var monkey_nodes: Dictionary = {}
var monkey_states: Dictionary = {}
var next_monkey_id := 1
var spawn_timer := 0.15
var spawn_left_x := -800.0
var spawn_right_x := 800.0
var spawn_top_y := 0.0
var cleanup_y := 1200.0
var round_active := false

func assign_roles(player_ids: Array[int]) -> Dictionary:
	var result: Dictionary = {}
	for peer_id in player_ids:
		result[peer_id] = "Survivor"
	return result

func get_team(team_name: String) -> Dictionary:
	for team_value in teams:
		if team_value is Dictionary and str(team_value.get("name", "")) == team_name:
			return team_value.duplicate(true)
	return {}

func start_round(player_ids: Array[int]):
	_clear_monkeys()
	_find_spawn_bounds(player_ids)
	next_monkey_id = 1
	spawn_timer = 0.15
	round_active = true

func process_round(delta: float, player_ids: Array[int]):
	if not NetworkManager.is_server() or not round_active:
		return
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		for index in range(MONKEYS_PER_WAVE):
			if monkey_states.size() >= MAX_ACTIVE_MONKEYS:
				break
			_spawn_monkey()
		spawn_timer = randf_range(SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_MAX)
	for id_value in monkey_states.keys().duplicate():
		var monkey_id := int(id_value)
		var monkey_state: Dictionary = monkey_states[monkey_id]
		var position_value: Variant = monkey_state.get("position", Vector2.ZERO)
		if not position_value is Vector2:
			_remove_monkey(monkey_id)
			continue
		var position: Vector2 = position_value
		position.y += float(monkey_state.get("speed", MONKEY_SPEED_MIN)) * delta
		var rotation_value := float(monkey_state.get("rotation", 0.0)) + float(monkey_state.get("spin", 0.0)) * delta
		monkey_state["position"] = position
		monkey_state["rotation"] = rotation_value
		monkey_states[monkey_id] = monkey_state
		_set_monkey_transform(monkey_id, position, rotation_value)
		if position.y > cleanup_y:
			_remove_monkey(monkey_id)

func get_winner(player_ids: Array[int], _roles: Dictionary) -> String:
	var alive_players: Array[int] = []
	for peer_id in player_ids:
		var player := NetworkManager.get_player(int(peer_id))
		if player == null or not is_instance_valid(player):
			continue
		if player.get("is_dead") != true:
			alive_players.append(int(peer_id))
	if alive_players.size() > 1:
		return ""
	if alive_players.size() == 1:
		var nickname := NicknameManager.get_nickname(alive_players[0])
		return nickname if not nickname.is_empty() else "Player %d" % alive_players[0]
	return "Nobody"

func get_network_state() -> Dictionary:
	var network_monkeys: Array[Dictionary] = []
	for monkey_id in monkey_states.keys():
		var state: Dictionary = monkey_states[monkey_id]
		network_monkeys.append(state.duplicate(true))
	return {"active": round_active, "monkeys": network_monkeys}

func sync_network_state(state: Dictionary):
	if NetworkManager.is_server():
		return
	if state.get("active", false) != true:
		round_active = false
		_clear_monkeys()
		return
	round_active = true
	var incoming_value: Variant = state.get("monkeys", [])
	if not incoming_value is Array:
		return
	var received_ids: Dictionary = {}
	for entry_value in incoming_value:
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		var monkey_id := int(entry.get("id", 0))
		var position_value: Variant = entry.get("position", Vector2.ZERO)
		if monkey_id <= 0 or not position_value is Vector2:
			continue
		var position: Vector2 = position_value
		var speed := float(entry.get("speed", MONKEY_SPEED_MIN))
		var rotation_value := float(entry.get("rotation", 0.0))
		var spin := float(entry.get("spin", 0.0))
		received_ids[monkey_id] = true
		var monkey := _ensure_monkey(monkey_id, position, rotation_value)
		if monkey == null:
			continue
		monkey.set_meta("target_position", position)
		monkey.set_meta("target_rotation", rotation_value)
		monkey.set_meta("fall_speed", speed)
		monkey.set_meta("spin", spin)
		monkey_states[monkey_id] = entry.duplicate(true)
	for id_value in monkey_nodes.keys().duplicate():
		var monkey_id := int(id_value)
		if not received_ids.has(monkey_id):
			_remove_monkey(monkey_id)

func client_process(delta: float):
	if NetworkManager.is_server() or not round_active:
		return
	for id_value in monkey_nodes.keys():
		var monkey := monkey_nodes.get(id_value) as Node2D
		if monkey == null or not is_instance_valid(monkey):
			continue
		var target_value: Variant = monkey.get_meta("target_position", monkey.global_position)
		if target_value is Vector2:
			var target_position: Vector2 = target_value
			var speed := maxf(float(monkey.get_meta("fall_speed", MONKEY_SPEED_MIN)) * 1.5, 1.0)
			monkey.global_position = monkey.global_position.move_toward(target_position, speed * delta)
		var target_rotation := float(monkey.get_meta("target_rotation", monkey.global_rotation))
		monkey.global_rotation = lerp_angle(monkey.global_rotation, target_rotation, minf(delta * 14.0, 1.0))

func end_round():
	round_active = false
	_clear_monkeys()

func _spawn_monkey():
	if _load_monkey_scene() == null:
		if not monkey_scene_warning_shown:
			push_warning("Falling Monkeys requires res://prefabs/weapons/monkey.tscn")
			monkey_scene_warning_shown = true
		return
	var position := Vector2(randf_range(spawn_left_x, spawn_right_x), spawn_top_y - randf_range(SPAWN_HEIGHT_MIN, SPAWN_HEIGHT_MAX))
	var speed := randf_range(MONKEY_SPEED_MIN, MONKEY_SPEED_MAX)
	var rotation_value := randf_range(-PI, PI)
	var spin := randf_range(-1.8, 1.8)
	var monkey_id := next_monkey_id
	next_monkey_id += 1
	var state := {"id": monkey_id, "position": position, "speed": speed, "rotation": rotation_value, "spin": spin}
	monkey_states[monkey_id] = state
	_ensure_monkey(monkey_id, position, rotation_value)

func _ensure_monkey(monkey_id: int, position: Vector2, rotation_value: float) -> Node2D:
	var existing := monkey_nodes.get(monkey_id) as Node2D
	if existing != null and is_instance_valid(existing):
		return existing
	var packed := _load_monkey_scene()
	if packed == null:
		return null
	var instance: Node = packed.instantiate()
	var monkey := instance as Node2D
	if monkey == null:
		if instance != null:
			instance.free()
		return null
	var killbox := monkey.find_child("Killbox", true, false)
	if monkey is CollisionObject2D:
		var monkey_collision := monkey as CollisionObject2D
		monkey_collision.collision_layer = 0
		monkey_collision.collision_mask = 0
	if monkey is RigidBody2D:
		var rigid_monkey := monkey as RigidBody2D
		rigid_monkey.freeze = true
	monkey.name = "FallingMonkey_%d" % monkey_id
	var scene_tree := Engine.get_main_loop() as SceneTree
	if scene_tree == null or scene_tree.current_scene == null:
		monkey.free()
		return null
	scene_tree.current_scene.add_child(monkey)
	monkey.global_position = position
	monkey.global_rotation = rotation_value
	monkey.set_meta("target_position", position)
	monkey.set_meta("target_rotation", rotation_value)
	monkey.set_meta("network_initialized", true)
	monkey_nodes[monkey_id] = monkey
	return monkey

func _load_monkey_scene() -> PackedScene:
	if monkey_scene != null:
		return monkey_scene
	if not ResourceLoader.exists(MONKEY_SCENE_PATH):
		return null
	monkey_scene = ResourceLoader.load(MONKEY_SCENE_PATH) as PackedScene
	return monkey_scene

func _set_monkey_transform(monkey_id: int, position: Vector2, rotation_value: float):
	var monkey := monkey_nodes.get(monkey_id) as Node2D
	if monkey == null or not is_instance_valid(monkey):
		return
	monkey.global_position = position
	monkey.global_rotation = rotation_value

func _remove_monkey(monkey_id: int):
	var monkey := monkey_nodes.get(monkey_id) as Node2D
	if monkey != null and is_instance_valid(monkey):
		monkey.queue_free()
	monkey_nodes.erase(monkey_id)
	monkey_states.erase(monkey_id)

func _clear_monkeys():
	for monkey_id_value in monkey_nodes.keys().duplicate():
		_remove_monkey(int(monkey_id_value))
	monkey_nodes.clear()
	monkey_states.clear()

func _find_spawn_bounds(player_ids: Array[int]):
	spawn_left_x = 0.0
	spawn_right_x = 0.0
	spawn_top_y = 0.0
	cleanup_y = 1200.0
	var found_spawn := false
	var map_manager := NetworkManager.get_map_manager()
	if map_manager != null:
		var map := map_manager.get("current_map") as Node2D
		if map != null and is_instance_valid(map):
			var spawns := map.find_child("Spawns", true, false)
			if spawns != null:
				var first_spawn := true
				var bottom_y := 0.0
				for spawn_value in spawns.get_children():
					if not spawn_value is Node2D:
						continue
					var spawn := spawn_value as Node2D
					spawn_left_x = minf(spawn_left_x, spawn.global_position.x)
					spawn_right_x = maxf(spawn_right_x, spawn.global_position.x)
					if first_spawn:
						spawn_top_y = spawn.global_position.y
						bottom_y = spawn.global_position.y
						first_spawn = false
					else:
						spawn_top_y = minf(spawn_top_y, spawn.global_position.y)
						bottom_y = maxf(bottom_y, spawn.global_position.y)
					found_spawn = true
				cleanup_y = bottom_y + 900.0
	if not found_spawn:
		var found_player := false
		var bottom_y := 0.0
		for peer_id in player_ids:
			var player := NetworkManager.get_player(int(peer_id))
			if player == null or not is_instance_valid(player):
				continue
			spawn_left_x = minf(spawn_left_x, player.global_position.x)
			spawn_right_x = maxf(spawn_right_x, player.global_position.x)
			if not found_player:
				spawn_top_y = player.global_position.y
				bottom_y = player.global_position.y
				found_player = true
			else:
				spawn_top_y = minf(spawn_top_y, player.global_position.y)
				bottom_y = maxf(bottom_y, player.global_position.y)
		if found_player:
			cleanup_y = bottom_y + 900.0
	if spawn_right_x - spawn_left_x < 500.0:
		spawn_left_x -= 800.0
		spawn_right_x += 800.0
