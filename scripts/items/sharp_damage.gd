extends Node

@export var area: Area2D
@export_range(0.0, 100.0, 1.0) var sharpness: float = 0.0
@export_range(50.0, 2000.0, 10.0) var minimum_impact_speed: float = 100.0
@export_range(1.0, 30.0, 0.5) var wound_radius: float = 5.0
@export_range(1.0, 1000.0, 10.0) var minimum_cut_speed: float = 180.0
@export_range(0.0, 100.0, 1.0) var minimum_cut_sharpness: float = 1.0
@export_range(1.0, 50.0, 1.0) var blade_sweep_radius: float = 18.0

var item: RigidBody2D = null
var last_holder: Node = null
var last_position := Vector2.ZERO
var hit_players: Dictionary = {}
var was_held := false
var last_rotation := 0.0
var last_swing_direction := Vector2.ZERO

func _ready():
	item = get_parent() as RigidBody2D
	if item == null:
		set_physics_process(false)
		return
	if area == null:
		area = item.get_node_or_null("Area2D") as Area2D
	if area == null:
		set_physics_process(false)
		return
	area.collision_mask = area.collision_mask | 16
	area.monitoring = true
	last_position = item.global_position
	last_rotation = item.global_rotation

func _physics_process(delta: float):
	if item == null or not is_instance_valid(item) or area == null or not is_instance_valid(area):
		return
	var held_value: Variant = item.get("held")
	var pocketed_value: Variant = item.get("pocketed")
	var is_held: bool = held_value == true
	var is_pocketed: bool = pocketed_value == true
	if is_pocketed:
		hit_players.clear()
		was_held = false
		last_position = item.global_position
		last_rotation = item.global_rotation
		return
	_clear_separated_targets()
	if is_held:
		var holder_value: Variant = item.get("holder_player")
		if holder_value is Node:
			last_holder = holder_value
		if not was_held:
			last_swing_direction = Vector2.ZERO
		if NetworkManager.is_networked() and not NetworkManager.is_server():
			last_position = item.global_position
			last_rotation = item.global_rotation
			was_held = true
			return
		var frame_delta := maxf(delta, 0.001)
		var movement := item.global_position - last_position
		var angle_delta := wrapf(item.global_rotation - last_rotation, -PI, PI)
		var linear_speed := movement.length() / frame_delta
		var rotation_speed := absf(angle_delta) * blade_sweep_radius / frame_delta
		var cut_speed := maxf(linear_speed, rotation_speed)
		if sharpness >= minimum_cut_sharpness and cut_speed >= minimum_cut_speed:
			var swing_direction := movement.normalized() if movement.length_squared() > 0.001 else Vector2.RIGHT.rotated(item.global_rotation) * signf(angle_delta)
			if swing_direction != Vector2.ZERO:
				last_swing_direction = swing_direction
			_process_overlapping_targets(cut_speed)
		else:
			last_swing_direction = Vector2.ZERO
		last_position = item.global_position
		last_rotation = item.global_rotation
		was_held = true
		return
	if was_held:
		last_position = item.global_position
		last_rotation = item.global_rotation
		last_swing_direction = Vector2.ZERO
		was_held = false
	if NetworkManager.is_networked() and not NetworkManager.is_server():
		last_position = item.global_position
		last_rotation = item.global_rotation
		return
	if item.freeze or item.linear_velocity.length() < minimum_impact_speed:
		last_position = item.global_position
		last_rotation = item.global_rotation
		return
	_process_overlapping_targets(item.linear_velocity.length())
	last_position = item.global_position
	last_rotation = item.global_rotation

func _clear_separated_targets():
	var overlapping_players: Dictionary = {}
	for target_value in area.get_overlapping_areas():
		if not target_value is Area2D:
			continue
		var target_area := target_value as Area2D
		if not target_area.has_meta("ultra_violence"):
			continue
		var violence_value: Variant = target_area.get_meta("ultra_violence")
		if not violence_value is Node:
			continue
		var player := (violence_value as Node).get_parent()
		if player != null and is_instance_valid(player):
			overlapping_players[player.get_instance_id()] = true
	for player_id_value in hit_players.keys():
		var player_id := int(player_id_value)
		if not overlapping_players.has(player_id):
			hit_players.erase(player_id)

func _process_overlapping_targets(impact_speed: float):
	for target_value in area.get_overlapping_areas():
		if target_value is Area2D and _try_hit(target_value as Area2D, impact_speed):
			return

func _try_hit(target_area: Area2D, impact_speed: float) -> bool:
	if not target_area.has_meta("ultra_violence") or not target_area.has_meta("ultra_region"):
		return false
	var violence_value: Variant = target_area.get_meta("ultra_violence")
	var region_value: Variant = target_area.get_meta("ultra_region")
	if not violence_value is Node or not region_value is int:
		return false
	var violence := violence_value as Node
	if not is_instance_valid(violence) or not violence.has_method("apply_sharp_hit"):
		return false
	var player := violence.get_parent()
	if player == null or not is_instance_valid(player) or player == last_holder:
		return false
	var player_id := player.get_instance_id()
	if hit_players.has(player_id):
		return false
	var hit_position := _find_hit_position(target_area)
	var impact_direction := last_swing_direction
	if impact_direction.length_squared() < 0.001:
		impact_direction = item.linear_velocity.normalized()
	if impact_direction.length_squared() < 0.001:
		impact_direction = (hit_position - item.global_position).normalized()
	var result: float = float(violence.call("apply_sharp_hit", int(region_value), sharpness, impact_speed, hit_position, wound_radius, impact_direction))
	if result <= 0.0:
		return false
	hit_players[player_id] = true
	return true

func _find_hit_position(target_area: Area2D) -> Vector2:
	var motion := item.global_position - last_position
	if motion.length_squared() > 0.01:
		var query := PhysicsRayQueryParameters2D.create(last_position, item.global_position)
		query.collision_mask = 16
		query.collide_with_areas = true
		query.collide_with_bodies = false
		query.exclude = [area.get_rid(), item.get_rid()]
		var hit := item.get_world_2d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.get("collider") == target_area:
			var point_value: Variant = hit.get("position")
			if point_value is Vector2:
				return point_value
	var best_position := target_area.global_position
	var best_distance := INF
	for node in target_area.find_children("*", "CollisionShape2D", true, false):
		var shape_node := node as CollisionShape2D
		if shape_node == null or shape_node.disabled or shape_node.shape == null:
			continue
		var point := shape_node.to_local(item.global_position)
		var rect := shape_node.shape.get_rect()
		point.x = clampf(point.x, rect.position.x, rect.end.x)
		point.y = clampf(point.y, rect.position.y, rect.end.y)
		if shape_node.shape is CircleShape2D:
			var circle := shape_node.shape as CircleShape2D
			if point.length() > circle.radius:
				point = point.normalized() * circle.radius
		var world_point := shape_node.to_global(point)
		var distance := world_point.distance_squared_to(item.global_position)
		if distance < best_distance:
			best_distance = distance
			best_position = world_point
	return best_position
