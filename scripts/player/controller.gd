extends CharacterBody2D

const DROP_THROW_HOLD_TIME := 0.28
const DROP_THROW_IMPULSE := 500.0
const TEAM_OUTLINE_SHADER = preload("res://shaders/team_outline.gdshader")

@export var speed := 250
@export var jump_force := -450
@export var friction := 1600
@export var acceleration := 1200

@onready var body_skin: Sprite2D = $BodyVisuals/Torso/Skin
@onready var body_muscle: Sprite2D = $BodyVisuals/Torso/Muscle
@onready var body_skeleton: Sprite2D = $BodyVisuals/Torso/Skeleton

@onready var head_skin: Sprite2D = $BodyVisuals/Head/Skin
@onready var head_muscle: Sprite2D = $BodyVisuals/Head/Muscle
@onready var head_skeleton: Sprite2D = $BodyVisuals/Head/Skeleton

@onready var left_shoulder: Marker2D = $BodyVisuals/Hands/LeftShoulder
@onready var right_shoulder: Marker2D = $BodyVisuals/Hands/RightShoulder

@onready var left_hand_skin: Sprite2D = $BodyVisuals/Hands/LeftShoulder/Skin
@onready var left_hand_muscle: Sprite2D = $BodyVisuals/Hands/LeftShoulder/Muscle
@onready var left_hand_skeleton: Sprite2D = $BodyVisuals/Hands/LeftShoulder/Skeleton

@onready var right_hand_skin: Sprite2D = $BodyVisuals/Hands/RightShoulder/Skin
@onready var right_hand_muscle: Sprite2D = $BodyVisuals/Hands/RightShoulder/Muscle
@onready var right_hand_skeleton: Sprite2D = $BodyVisuals/Hands/RightShoulder/Skeleton

@onready var left_hand_collision: HandCollision = $LeftHandCollision
@onready var right_hand_collision: HandCollision = $RightHandCollision

@onready var left_hand_area: Area2D = $LeftHandCollision/LeftHandArea
@onready var right_hand_area: Area2D = $RightHandCollision/RightHandArea

@onready var left_hand_marker: Marker2D = $LeftHandCollision/LeftHandArea/Marker2D
@onready var right_hand_marker: Marker2D = $RightHandCollision/RightHandArea/Marker2D

@onready var pockets = $Pockets
@onready var ultra_violence = $UltraViolence
@onready var camera: Camera2D = $Camera2D
@onready var corpse: Node = $Corpse

var left_rest_pos: Vector2
var right_rest_pos: Vector2
var left_rest_pos_left: Vector2
var right_rest_pos_left: Vector2
var base_left_shoulder_pos: Vector2
var base_right_shoulder_pos: Vector2

var left_item = null
var right_item = null

var base_head_y: float
var base_l_shoulder_y: float
var base_r_shoulder_y: float
var bob_time := 0.0
var base_left_eye_x: float
var base_right_eye_x: float

var is_facing_right := true
var is_dead := false
var left_hand_is_disabled := false
var right_hand_is_disabled := false

var death_velocity := Vector2.ZERO
var death_has_left_floor := false
var death_target_rotation := 0.0

var ghost_scene := preload("res://prefabs/ghost.tscn")

var network_player_id := 0
var local_player := true
var network_remote := false
var network_spawn_ready := true
var network_aim_direction := Vector2.RIGHT
var network_head_rotation := 0.0
var network_facing_right := true
var network_left_hand_offset := Vector2.ZERO
var network_right_hand_offset := Vector2.ZERO
var network_left_active := false
var network_right_active := false
var network_on_floor := false
var network_position := Vector2.ZERO
var network_velocity := Vector2.ZERO
var network_receive_sequence := -1
var network_send_sequence := 0
var network_state_time := 0
var network_send_timer := 0.0
var network_ghost_spawned := false
var chat_input_active := false
var round_role := ""
var role_outline_enabled := false
var role_outline_color := Color.RED
var role_outline_sources: Array[Sprite2D] = []
var role_outline_sprites: Array[Sprite2D] = []
var drop_hold_time := 0.0
var drop_throw_sent := false
var drop_through_authorize_pending := false
var drop_through_platforms: Array = []
var left_recoil_offset := Vector2.ZERO
var right_recoil_offset := Vector2.ZERO
const RECOIL_RECOVERY_SPEED := 100.0

func set_network_player_id(peer_id: int):
	network_player_id = peer_id

func set_chat_input_active(value: bool):
	chat_input_active = value
	if value:
		drop_hold_time = 0.0
		drop_throw_sent = false

func apply_recoil(hand_index: int, shot_direction: Vector2, strength: float):
	if hand_index < 0 or hand_index > 1 or not shot_direction.is_finite() or shot_direction.length_squared() < 0.001:
		return
	var direction := shot_direction.normalized()
	var kick := -direction * (12.0 * maxf(strength, 0.0)) + Vector2(0.0, -5.0 * maxf(strength, 0.0))
	if hand_index == 0:
		left_recoil_offset = (left_recoil_offset + kick).limit_length(36.0)
	else:
		right_recoil_offset = (right_recoil_offset + kick).limit_length(36.0)

func set_round_role(value: String, outline_enabled: bool = false, outline_color: Color = Color.RED):
	round_role = value
	role_outline_enabled = outline_enabled
	role_outline_color = outline_color
	for outline in role_outline_sprites:
		var material := outline.material as ShaderMaterial
		if material != null:
			material.set_shader_parameter("outline_color", role_outline_color)
	_sync_role_outline_sprites()

func _create_role_outline_sprites():
	if not role_outline_sprites.is_empty():
		return
	var sources: Array[Sprite2D] = [body_skin, head_skin, left_hand_skin, right_hand_skin]
	for source in sources:
		if source == null or source.texture == null or source.get_parent() == null:
			continue
		var outline := Sprite2D.new()
		outline.name = "%sRoleOutline" % source.name
		outline.texture = source.texture
		outline.centered = source.centered
		outline.offset = source.offset
		outline.flip_h = source.flip_h
		outline.flip_v = source.flip_v
		outline.region_enabled = source.region_enabled
		outline.region_rect = source.region_rect
		outline.hframes = source.hframes
		outline.vframes = source.vframes
		outline.frame = source.frame
		outline.frame_coords = source.frame_coords
		outline.texture_filter = source.texture_filter
		var material := ShaderMaterial.new()
		material.shader = TEAM_OUTLINE_SHADER
		material.set_shader_parameter("outline_color", role_outline_color)
		outline.material = material
		outline.z_as_relative = false
		outline.z_index = 4096
		outline.visible = false
		source.get_parent().add_child(outline)
		source.get_parent().move_child(outline, source.get_index())
		role_outline_sources.append(source)
		role_outline_sprites.append(outline)
	_sync_role_outline_sprites()

func _sync_role_outline_sprites():
	for i in range(role_outline_sources.size()):
		var source: Sprite2D = role_outline_sources[i]
		var outline: Sprite2D = role_outline_sprites[i]
		if not is_instance_valid(source) or not is_instance_valid(outline):
			continue
		outline.global_transform = source.global_transform
		outline.frame = source.frame
		outline.frame_coords = source.frame_coords
		outline.visible = role_outline_enabled and source.visible

func reset_for_round():
	_sanitize_held_item_references()
	for platform_value in drop_through_platforms:
		if not is_instance_valid(platform_value) or not platform_value is PhysicsBody2D:
			continue
		var platform := platform_value as PhysicsBody2D
		remove_collision_exception_with(platform)
	drop_through_platforms.clear()
	drop_through_authorize_pending = false
	is_dead = false
	left_hand_is_disabled = false
	right_hand_is_disabled = false
	death_velocity = Vector2.ZERO
	death_has_left_floor = false
	death_target_rotation = 0.0
	network_ghost_spawned = false
	network_spawn_ready = true
	network_receive_sequence = -1
	network_state_time = 0
	drop_through_authorize_pending = false
	network_position = global_position
	network_velocity = Vector2.ZERO
	velocity = Vector2.ZERO
	rotation = 0.0
	is_facing_right = true
	network_facing_right = true
	left_shoulder.position = base_left_shoulder_pos
	right_shoulder.position = base_right_shoulder_pos
	base_l_shoulder_y = base_left_shoulder_pos.y
	base_r_shoulder_y = base_right_shoulder_pos.y
	left_hand_area.monitoring = true
	left_hand_area.collision_layer = 16
	left_hand_area.collision_mask = 12
	right_hand_area.monitoring = true
	right_hand_area.collision_layer = 16
	right_hand_area.collision_mask = 12
	left_hand_collision.collision_layer = 0
	left_hand_collision.collision_mask = 0
	right_hand_collision.collision_layer = 0
	right_hand_collision.collision_mask = 0
	left_hand_skin.visible = true
	left_hand_muscle.visible = true
	left_hand_skeleton.visible = true
	right_hand_skin.visible = true
	right_hand_muscle.visible = true
	right_hand_skeleton.visible = true
	camera.enabled = not NetworkManager.is_networked() or local_player
	if ultra_violence != null and ultra_violence.has_method("reset_for_round"):
		ultra_violence.call("reset_for_round")

func set_local_player(value: bool):
	local_player = value
	network_remote = NetworkManager.is_networked() and not local_player
	if is_inside_tree():
		camera.enabled = not NetworkManager.is_networked() or local_player
		var item_description := get_node_or_null("ItemDescription")
		if item_description != null:
			item_description.set_process(not NetworkManager.is_networked() or local_player)

func set_network_spawn_ready(value: bool):
	network_spawn_ready = value

func _sanitize_held_item_references():
	if not is_instance_valid(left_item):
		left_item = null
	if not is_instance_valid(right_item):
		right_item = null

func _get_player_collision_bounds() -> Rect2:
	var bounds := Rect2()
	var has_bounds := false
	for child in get_children():
		if not child is CollisionShape2D:
			continue
		var shape_node := child as CollisionShape2D
		if shape_node.disabled or shape_node.shape == null:
			continue
		var shape_rect := shape_node.shape.get_rect()
		var corners: Array[Vector2] = [shape_rect.position, Vector2(shape_rect.end.x, shape_rect.position.y), shape_rect.end, Vector2(shape_rect.position.x, shape_rect.end.y)]
		for corner in corners:
			var point: Vector2 = shape_node.global_transform * corner
			if not has_bounds:
				bounds = Rect2(point, Vector2.ZERO)
				has_bounds = true
			else:
				bounds = bounds.expand(point)
	return bounds

func clear_item_reference(item: Node):
	if left_item == item:
		left_item = null
	if right_item == item:
		right_item = null
	if pockets != null and pockets.has_method("clear_network_item"):
		pockets.call("clear_network_item", item)

func get_hand_marker(hand: int) -> Marker2D:
	if hand == 0:
		return left_hand_marker
	if hand == 1:
		return right_hand_marker
	return null

func is_hand_active(hand: int) -> bool:
	if chat_input_active and local_player:
		return false
	if network_remote:
		return network_left_active if hand == 0 else network_right_active if hand == 1 else false
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) if hand == 0 else Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) if hand == 1 else false

func get_aim_position() -> Vector2:
	if network_remote:
		return global_position + network_aim_direction * 100.0
	return get_global_mouse_position()

func get_game_input() -> Dictionary:
	return {"left_active": is_hand_active(0), "right_active": is_hand_active(1), "aim": get_aim_position()}

func get_network_state() -> Dictionary:
	return {"id": network_player_id, "position": global_position, "velocity": velocity, "rotation": rotation, "aim_direction": (get_aim_position() - global_position).normalized(), "head_rotation": network_head_rotation if network_remote else head_skin.global_rotation, "left_hand_offset": left_hand_collision.global_position - left_shoulder.global_position - left_recoil_offset, "right_hand_offset": right_hand_collision.global_position - right_shoulder.global_position - right_recoil_offset, "left_active": is_hand_active(0), "right_active": is_hand_active(1), "on_floor": is_on_floor(), "facing": is_facing_right, "dead": is_dead, "death_impulse": death_velocity.normalized(), "death_velocity": death_velocity, "death_rotation": death_target_rotation}

func apply_local_network_correction(position: Vector2, new_velocity: Vector2):
	global_position = position
	velocity = new_velocity
	network_position = position
	network_velocity = new_velocity
	network_spawn_ready = true

func apply_network_state(state: Dictionary):
	_sanitize_held_item_references()
	var sequence := int(state.get("sequence", network_receive_sequence + 1))
	if not local_player and sequence <= network_receive_sequence:
		return
	if not local_player:
		network_receive_sequence = sequence
	var position_value: Variant = state.get("position", network_position)
	if position_value is Vector2:
		network_position = position_value
		if local_player and not network_spawn_ready:
			global_position = position_value
			network_spawn_ready = true
	var velocity_value: Variant = state.get("velocity", network_velocity)
	if velocity_value is Vector2:
		network_velocity = velocity_value
	var aim_value: Variant = state.get("aim_direction", network_aim_direction)
	if aim_value is Vector2 and aim_value.length_squared() > 0.000001:
		network_aim_direction = aim_value.normalized()
	var head_rotation_value: Variant = state.get("head_rotation", network_head_rotation)
	if (head_rotation_value is float or head_rotation_value is int) and is_finite(float(head_rotation_value)):
		network_head_rotation = float(head_rotation_value)
	var left_value: Variant = state.get("left_active", network_left_active)
	var right_value: Variant = state.get("right_active", network_right_active)
	if left_value is bool:
		network_left_active = left_value
	if right_value is bool:
		network_right_active = right_value
	var left_hand_value: Variant = state.get("left_hand_offset", network_left_hand_offset)
	var right_hand_value: Variant = state.get("right_hand_offset", network_right_hand_offset)
	if left_hand_value is Vector2 and left_hand_value.is_finite():
		network_left_hand_offset = left_hand_value
	if right_hand_value is Vector2 and right_hand_value.is_finite():
		network_right_hand_offset = right_hand_value
	var floor_value: Variant = state.get("on_floor", network_on_floor)
	if floor_value is bool:
		network_on_floor = floor_value
	var facing_value: Variant = state.get("facing", network_facing_right)
	if facing_value is bool:
		network_facing_right = facing_value
	var rotation_value: Variant = state.get("rotation", rotation)
	if not local_player and (rotation_value is float or rotation_value is int):
		rotation = float(rotation_value)
	var dead_value: Variant = state.get("dead", is_dead)
	if dead_value is bool and dead_value and not is_dead:
		var impulse_value: Variant = state.get("death_impulse", Vector2.RIGHT)
		var impulse := Vector2.RIGHT
		if impulse_value is Vector2 and impulse_value.length_squared() > 0.000001:
			impulse = impulse_value
		apply_network_death(impulse, state)

func apply_network_death(impulse_direction: Vector2, state: Dictionary = {}):
	if is_dead:
		return
	is_dead = true
	corpse.call("begin_death", impulse_direction, state)
	if local_player:
		_spawn_ghost()

func _spawn_ghost():
	if network_ghost_spawned:
		return
	if ghost_scene == null:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var ghost := ghost_scene.instantiate() as Node2D
	if ghost == null:
		return
	scene.add_child(ghost)
	ghost.global_position = global_position
	network_ghost_spawned = true

func _on_server_player_state(peer_id: int, state: Dictionary):
	_sanitize_held_item_references()
	if not NetworkManager.is_server() or peer_id != network_player_id or local_player:
		return
	if int(state.get("id", -1)) != peer_id:
		return
	var sequence := int(state.get("sequence", -1))
	if sequence <= network_receive_sequence:
		return
	var position_value: Variant = state.get("position")
	var velocity_value: Variant = state.get("velocity")
	var aim_value: Variant = state.get("aim_direction")
	if not position_value is Vector2 or not velocity_value is Vector2 or not aim_value is Vector2:
		return
	var new_position: Vector2 = position_value
	var new_velocity: Vector2 = velocity_value
	var new_aim_direction: Vector2 = aim_value
	if not new_position.is_finite() or not new_velocity.is_finite() or not new_aim_direction.is_finite() or new_aim_direction.length_squared() < 0.000001:
		return
	var left_value: Variant = state.get("left_active", false)
	var right_value: Variant = state.get("right_active", false)
	var floor_value: Variant = state.get("on_floor", false)
	var drop_through_value: Variant = state.get("drop_through", false)
	var left_hand_value: Variant = state.get("left_hand_offset", Vector2.ZERO)
	var right_hand_value: Variant = state.get("right_hand_offset", Vector2.ZERO)
	if not left_value is bool or not right_value is bool or not floor_value is bool or not drop_through_value is bool:
		return
	if not left_hand_value is Vector2 or not right_hand_value is Vector2:
		return
	if not left_hand_value.is_finite() or not right_hand_value.is_finite():
		return
	var now := Time.get_ticks_usec()
	var elapsed: float = 1.0 / 60.0
	if network_state_time > 0:
		elapsed = clampf(float(now - network_state_time) / 1000000.0, 0.01, 0.2)
	var motion := new_position - global_position
	var maximum_speed: float = maxf(float(speed), absf(float(jump_force)))
	var maximum_distance: float = maximum_speed * elapsed * 1.8 + 24.0
	var maximum_velocity: float = maximum_speed * 1.8 + 250.0
	if motion.length() > maximum_distance or new_velocity.length() > maximum_velocity:
		NetworkManager.send_correction(network_player_id, global_position, velocity)
		return
	if motion.length_squared() > 0.000001 and test_move(global_transform, motion):
		var authorized_platform_drop: bool = drop_through_value == true and motion.y > 0.0 and not test_move(global_transform, Vector2(motion.x, 0.0))
		if not authorized_platform_drop:
			NetworkManager.send_correction(network_player_id, global_position, velocity)
			return
	network_receive_sequence = sequence
	network_state_time = now
	network_position = new_position
	network_velocity = new_velocity
	network_aim_direction = new_aim_direction.normalized()
	var head_rotation_value: Variant = state.get("head_rotation", network_head_rotation)
	if (head_rotation_value is float or head_rotation_value is int) and is_finite(float(head_rotation_value)):
		network_head_rotation = float(head_rotation_value)
	network_facing_right = network_aim_direction.x >= 0.0
	network_left_active = left_value
	network_right_active = right_value
	network_on_floor = floor_value
	global_position = new_position
	velocity = new_velocity
	if not is_dead:
		update_look()
		network_left_hand_offset = _validate_network_hand_offset(left_hand_value, left_shoulder, left_hand_collision, network_left_active, 0, left_item, left_recoil_offset)
		network_right_hand_offset = _validate_network_hand_offset(right_hand_value, right_shoulder, right_hand_collision, network_right_active, 1, right_item, right_recoil_offset)
		_update_network_hand(left_hand_skin, left_hand_muscle, left_hand_skeleton, left_hand_collision, left_shoulder, network_left_hand_offset, network_left_active, left_recoil_offset, left_item)
		_update_network_hand(right_hand_skin, right_hand_muscle, right_hand_skeleton, right_hand_collision, right_shoulder, network_right_hand_offset, network_right_active, right_recoil_offset, right_item)
		
func _on_server_message(peer_id: int, message: Dictionary):
	_sanitize_held_item_references()
	if not NetworkManager.is_server() or peer_id != network_player_id:
		return
	var kind: Variant = message.get("kind", "")
	var action: Variant = message.get("action", "")
	if not kind is String or not action is String or kind != "controller":
		return
	if action == "interact":
		interact(message.get("left_active", false) == true, message.get("right_active", false) == true, true)
	elif action == "drop":
		var aim_value: Variant = message.get("aim_position", Vector2.ZERO)
		var aim_position: Vector2 = aim_value if aim_value is Vector2 and aim_value.is_finite() else Vector2.ZERO
		drop_items(message.get("left_active", false) == true, message.get("right_active", false) == true, true, message.get("throw", false) == true, aim_position)

func _send_network_state(delta: float):
	if not NetworkManager.is_client() or not local_player or not network_spawn_ready:
		return
	network_send_timer += delta
	if network_send_timer < 1.0 / 60.0:
		return
	network_send_timer = 0.0
	network_send_sequence += 1
	NetworkManager.send_player_state({"id": network_player_id, "sequence": network_send_sequence, "position": global_position, "velocity": velocity, "aim_direction": (get_global_mouse_position() - global_position).normalized(), "head_rotation": head_skin.global_rotation, "facing": is_facing_right, "left_hand_offset": left_hand_collision.global_position - left_shoulder.global_position - left_recoil_offset, "right_hand_offset": right_hand_collision.global_position - right_shoulder.global_position - right_recoil_offset, "left_active": Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "right_active": Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT), "on_floor": is_on_floor(), "drop_through": drop_through_authorize_pending})
	drop_through_authorize_pending = false

func _ready():
	left_rest_pos = left_hand_skin.position
	right_rest_pos = right_hand_skin.position

	left_rest_pos_left = Vector2(right_rest_pos.x, left_rest_pos.y)
	right_rest_pos_left = Vector2(left_rest_pos.x, right_rest_pos.y)

	base_left_shoulder_pos = left_shoulder.position
	base_right_shoulder_pos = right_shoulder.position

	base_head_y = head_skin.position.y
	base_l_shoulder_y = left_shoulder.position.y
	base_r_shoulder_y = right_shoulder.position.y

	left_hand_collision.global_position = left_hand_skin.global_position
	right_hand_collision.global_position = right_hand_skin.global_position

	left_hand_skin.global_position = left_hand_collision.global_position
	left_hand_muscle.global_position = left_hand_collision.global_position
	left_hand_skeleton.global_position = left_hand_collision.global_position

	right_hand_skin.global_position = right_hand_collision.global_position
	right_hand_muscle.global_position = right_hand_collision.global_position
	right_hand_skeleton.global_position = right_hand_collision.global_position

	camera.enabled = not NetworkManager.is_networked() or local_player
	var item_description := get_node_or_null("ItemDescription")
	if item_description != null:
		item_description.set_process(not NetworkManager.is_networked() or local_player)
	if NetworkManager.is_networked():
		NetworkManager.server_player_state.connect(_on_server_player_state)
		NetworkManager.server_message.connect(_on_server_message)

	if ultra_violence.has_signal("died"):
		if not ultra_violence.died.is_connected(_on_died):
			ultra_violence.died.connect(_on_died)
	if ultra_violence.has_signal("hand_disabled"):
		if not ultra_violence.hand_disabled.is_connected(_on_hand_disabled):
			ultra_violence.hand_disabled.connect(_on_hand_disabled)
	_create_role_outline_sprites()

func interact(left_active: bool = false, right_active: bool = false, network_input: bool = false):
	_sanitize_held_item_references()
	if not network_input:
		left_active = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		right_active = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if try_ammo_box(left_hand_area, left_item, left_active):
		return
	if try_ammo_box(right_hand_area, right_item, right_active):
		return

	if not left_hand_is_disabled and left_item == null:
		for body in left_hand_area.get_overlapping_bodies():
			if body.is_in_group("interactable") and body.has_method("pickup"):
				if body.pickup(left_hand_marker):
					left_item = body
					return
	if not right_hand_is_disabled and right_item == null:
		for body in right_hand_area.get_overlapping_bodies():
			if body.is_in_group("interactable") and body.has_method("pickup"):
				if body.pickup(right_hand_marker):
					right_item = body
					return

func drop_items(left_pressed: bool = false, right_pressed: bool = false, network_input: bool = false, throw_item: bool = false, aim_position: Vector2 = Vector2.ZERO):
	_sanitize_held_item_references()
	if not network_input:
		left_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		right_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		aim_position = get_global_mouse_position()
	if throw_item and not aim_position.is_finite():
		throw_item = false
	if left_pressed and left_item != null:
		if left_item.has_method("drop"):
			if throw_item:
				var left_throw_direction: Vector2 = aim_position - left_item.global_position
				left_item.call("drop", left_throw_direction, DROP_THROW_IMPULSE)
			else:
				left_item.call("drop")
		left_item = null
	if right_pressed and right_item != null:
		if right_item.has_method("drop"):
			if throw_item:
				var right_throw_direction: Vector2 = aim_position - right_item.global_position
				right_item.call("drop", right_throw_direction, DROP_THROW_IMPULSE)
			else:
				right_item.call("drop")
		right_item = null

func _handle_drop_input(delta: float):
	if Input.is_action_just_pressed("drop"):
		drop_hold_time = 0.0
		drop_throw_sent = false
	if Input.is_action_pressed("drop"):
		drop_hold_time += delta
		if drop_hold_time >= DROP_THROW_HOLD_TIME and not drop_throw_sent:
			drop_throw_sent = true
			_perform_drop(true)
	if Input.is_action_just_released("drop") and not drop_throw_sent:
		drop_throw_sent = true
		_perform_drop(false)

func _perform_drop(throw_item: bool):
	var left_pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var right_pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var aim_position := get_global_mouse_position()
	if NetworkManager.is_client() and local_player:
		NetworkManager.send_to_server({"kind": "controller", "action": "drop", "left_active": left_pressed, "right_active": right_pressed, "throw": throw_item, "aim_position": aim_position})
	else:
		drop_items(left_pressed, right_pressed, true, throw_item, aim_position)

func drop_all_items():
	_sanitize_held_item_references()
	if left_item != null:
		if left_item.has_method("drop"):
			left_item.drop()
		left_item = null
	if right_item != null:
		if right_item.has_method("drop"):
			right_item.drop()
		right_item = null

	if pockets != null and pockets.has_method("drop_all"):
		pockets.drop_all()

func _on_hand_disabled(region: int):
	if region == 2:
		left_hand_is_disabled = true
		if left_item != null and left_item.has_method("drop"):
			left_item.drop()

		left_item = null
		left_hand_area.monitoring = false
		left_hand_area.collision_layer = 0
		left_hand_area.collision_mask = 0
		left_hand_collision.collision_layer = 0
		left_hand_collision.collision_mask = 0
		left_hand_skin.visible = false
		left_hand_muscle.visible = false
		left_hand_skeleton.visible = false

	elif region == 3:
		right_hand_is_disabled = true
		if right_item != null and right_item.has_method("drop"):
			right_item.drop()

		right_item = null
		right_hand_area.monitoring = false
		right_hand_area.collision_layer = 0
		right_hand_area.collision_mask = 0
		right_hand_collision.collision_layer = 0
		right_hand_collision.collision_mask = 0
		right_hand_skin.visible = false
		right_hand_muscle.visible = false
		right_hand_skeleton.visible = false

func _on_died(impulse_direction: Vector2, _hit_position: Vector2):
	if is_dead:
		return
	is_dead = true
	drop_all_items()

	left_hand_area.monitoring = false
	left_hand_area.collision_layer = 0
	left_hand_area.collision_mask = 0

	right_hand_area.monitoring = false
	right_hand_area.collision_layer = 0
	right_hand_area.collision_mask = 0

	left_hand_collision.collision_layer = 0
	left_hand_collision.collision_mask = 0

	right_hand_collision.collision_layer = 0
	right_hand_collision.collision_mask = 0

	left_hand_skin.visible = false
	left_hand_muscle.visible = false
	left_hand_skeleton.visible = false

	right_hand_skin.visible = false
	right_hand_muscle.visible = false
	right_hand_skeleton.visible = false

	camera.enabled = false

	var knockback_direction := -impulse_direction.normalized()
	if knockback_direction.length_squared() < 0.001:
		knockback_direction = Vector2.LEFT
	death_velocity = knockback_direction * 260.0
	death_velocity.y -= 70.0
	death_has_left_floor = false
	death_target_rotation = 0.7 if knockback_direction.x > 0.1 else -0.7 if knockback_direction.x < -0.1 else 0.0

	if not NetworkManager.is_networked() or local_player:
		_spawn_ghost()

func try_ammo_box(hand_area: Area2D, held_item: Node, hand_active: bool) -> bool:
	if not hand_active or held_item == null:
		return false

	var gun_component: Node = held_item.find_child("GunComponent", true, false)
	if gun_component == null:
		return false
	for body in hand_area.get_overlapping_bodies():
		var ammo_component: Node = body.find_child("AmmoComponent", true, false)
		if ammo_component == null:
			continue
		if not ammo_component.has_method("interact_with_weapon"):
			continue
		if ammo_component.interact_with_weapon(held_item):
			return true

	return false

func _get_hand_rest_offset(hand_index: int) -> Vector2:
	var shoulder: Node2D = left_shoulder if hand_index == 0 else right_shoulder
	var rest_pos: Vector2
	if is_facing_right:
		rest_pos = left_rest_pos if hand_index == 0 else right_rest_pos
	else:
		rest_pos = left_rest_pos_left if hand_index == 0 else right_rest_pos_left
	return shoulder.to_global(rest_pos) - shoulder.global_position

func _set_hand_collision_enabled(hand_collision: HandCollision, enabled: bool):
	if enabled:
		hand_collision.collision_layer = 8
		hand_collision.collision_mask = 1
	else:
		hand_collision.collision_layer = 0
		hand_collision.collision_mask = 0
	hand_collision.velocity = Vector2.ZERO

func _validate_network_hand_offset(offset: Vector2, shoulder: Node2D, hand_collision: HandCollision, active: bool, hand_index: int, held_item: Node = null, recoil_offset: Vector2 = Vector2.ZERO) -> Vector2:
	if not active:
		if is_instance_valid(held_item) and held_item.has_method("set_held_collision_active"):
			held_item.call("set_held_collision_active", false)
		return _get_hand_rest_offset(hand_index)
	_set_hand_collision_enabled(hand_collision, true)
	var target_offset := offset
	if target_offset.length() > 50.0:
		target_offset = target_offset.normalized() * 50.0
	var target_global := shoulder.global_position + target_offset + recoil_offset
	if is_instance_valid(held_item) and held_item.has_method("set_held_collision_active"):
		held_item.call("set_held_collision_active", true)
	if is_instance_valid(held_item) and held_item.has_method("constrain_holder_position"):
		var constrained_value: Variant = held_item.call("constrain_holder_position", target_global)
		if constrained_value is Vector2 and constrained_value.is_finite():
			target_global = constrained_value
		target_offset = target_global - shoulder.global_position - recoil_offset
	var movement := target_global - hand_collision.global_position
	if movement.length_squared() > 0.000001 and hand_collision.test_move(hand_collision.global_transform, movement):
		return hand_collision.global_position - shoulder.global_position - recoil_offset
	return target_offset

func _update_network_hand(hand: Sprite2D, muscle: Sprite2D, skeleton: Sprite2D, hand_collision: HandCollision, shoulder: Node2D, offset: Vector2, active: bool, recoil_offset: Vector2 = Vector2.ZERO, held_item: Node = null):
	var collision_enabled := active and NetworkManager.is_server()
	_set_hand_collision_enabled(hand_collision, collision_enabled)
	if is_instance_valid(held_item) and held_item.has_method("set_held_collision_active"):
		held_item.call("set_held_collision_active", active)
	var target_global := shoulder.global_position + offset + recoil_offset
	hand_collision.global_position = target_global
	hand.global_position = target_global
	muscle.global_position = target_global
	skeleton.global_position = target_global
	if not active:
		hand.rotation = 0.0

func update_look():
	var mouse_pos: Vector2 = get_aim_position()
	var looking_right: bool = mouse_pos.x > global_position.x
	if network_remote:
		looking_right = network_facing_right
	var facing_scale := 0.1 if looking_right else -0.1

	body_skin.scale.x = facing_scale
	body_muscle.scale.x = facing_scale
	body_skeleton.scale.x = facing_scale

	left_hand_skin.scale.x = facing_scale
	left_hand_muscle.scale.x = facing_scale
	left_hand_skeleton.scale.x = facing_scale

	right_hand_skin.scale.x = facing_scale
	right_hand_muscle.scale.x = facing_scale
	right_hand_skeleton.scale.x = facing_scale

	head_skin.look_at(mouse_pos)
	head_muscle.look_at(mouse_pos)
	head_skeleton.look_at(mouse_pos)
	if network_remote:
		head_skin.global_rotation = network_head_rotation
		head_muscle.global_rotation = network_head_rotation
		head_skeleton.global_rotation = network_head_rotation

	if looking_right:
		head_skin.scale.x = 0.1
		head_skin.scale.y = 0.1

		head_muscle.scale.x = 0.1
		head_muscle.scale.y = 0.1

		head_skeleton.scale.x = 0.1
		head_skeleton.scale.y = 0.1
	else:
		head_skin.scale.x = 0.1
		head_skin.scale.y = -0.1

		head_muscle.scale.x = 0.1
		head_muscle.scale.y = -0.1

		head_skeleton.scale.x = 0.1
		head_skeleton.scale.y = -0.1

	if looking_right == is_facing_right:
		return
	is_facing_right = looking_right
	if looking_right:
		left_shoulder.position = base_left_shoulder_pos
		right_shoulder.position = base_right_shoulder_pos

		base_l_shoulder_y = base_left_shoulder_pos.y
		base_r_shoulder_y = base_right_shoulder_pos.y
	else:
		left_shoulder.position = base_right_shoulder_pos
		right_shoulder.position = base_left_shoulder_pos

		base_l_shoulder_y = base_right_shoulder_pos.y
		base_r_shoulder_y = base_left_shoulder_pos.y

func update_hand(hand: Node2D, shoulder: Node2D, rest_pos: Vector2, hand_collision: HandCollision, active: bool, recoil_offset: Vector2 = Vector2.ZERO, held_item: Node = null):
	var arm_length := 50.0
	var target_global: Vector2
	if is_instance_valid(held_item) and held_item.has_method("set_held_collision_active"):
		held_item.call("set_held_collision_active", active)
	if active:
		_set_hand_collision_enabled(hand_collision, true)
		target_global = get_aim_position()
		var direction := target_global - shoulder.global_position
		if direction.length() > arm_length:
			target_global = shoulder.global_position + direction.normalized() * arm_length
	else:
		_set_hand_collision_enabled(hand_collision, false)
		target_global = shoulder.to_global(rest_pos)
	target_global += recoil_offset
	if active and is_instance_valid(held_item) and held_item.has_method("constrain_holder_position"):
		var constrained_value: Variant = held_item.call("constrain_holder_position", target_global)
		if constrained_value is Vector2 and constrained_value.is_finite():
			target_global = constrained_value
	if active:
		hand_collision.move_to_global(target_global)
	else:
		hand_collision.global_position = target_global
		hand_collision.velocity = Vector2.ZERO
	hand.global_position = hand_collision.global_position
	if not active:
		hand.rotation = 0.0

func update_arms():
	_sanitize_held_item_references()
	if network_remote:
		_update_network_hand(left_hand_skin, left_hand_muscle, left_hand_skeleton, left_hand_collision, left_shoulder, network_left_hand_offset, network_left_active, left_recoil_offset, left_item)
		_update_network_hand(right_hand_skin, right_hand_muscle, right_hand_skeleton, right_hand_collision, right_shoulder, network_right_hand_offset, network_right_active, right_recoil_offset, right_item)
		return

	var current_left_rest_pos: Vector2
	var current_right_rest_pos: Vector2

	if is_facing_right:
		current_left_rest_pos = left_rest_pos
		current_right_rest_pos = right_rest_pos
	else:
		current_left_rest_pos = left_rest_pos_left
		current_right_rest_pos = right_rest_pos_left
		
	if not left_hand_is_disabled:
		update_hand(
			left_hand_skin,
			left_shoulder,
			current_left_rest_pos,
			left_hand_collision,
			is_hand_active(0),
			left_recoil_offset,
			left_item
		)

		left_hand_muscle.global_position = left_hand_skin.global_position
		left_hand_skeleton.global_position = left_hand_skin.global_position
	if not right_hand_is_disabled:
		update_hand(
			right_hand_skin,
			right_shoulder,
			current_right_rest_pos,
			right_hand_collision,
			is_hand_active(1),
			right_recoil_offset,
			right_item
		)

		right_hand_muscle.global_position = right_hand_skin.global_position
		right_hand_skeleton.global_position = right_hand_skin.global_position

func update_animation(delta: float):
	if is_on_floor() and abs(velocity.x) > 10:
		bob_time += delta * 15.0
		var bob_amount := sin(bob_time) * 2.0
		head_skin.position.y = base_head_y + bob_amount - 3
		head_muscle.position.y = base_head_y + bob_amount - 3
		head_skeleton.position.y = base_head_y + bob_amount - 3

		left_shoulder.position.y = base_l_shoulder_y + bob_amount
		right_shoulder.position.y = base_r_shoulder_y + bob_amount
	else:
		bob_time = 0.0

		head_skin.position.y = move_toward(
			head_skin.position.y,
			base_head_y,
			20 * delta
		)

		head_muscle.position.y = move_toward(
			head_muscle.position.y,
			base_head_y,
			20 * delta
		)

		head_skeleton.position.y = move_toward(
			head_skeleton.position.y,
			base_head_y,
			20 * delta
		)

		left_shoulder.position.y = move_toward(
			left_shoulder.position.y,
			base_l_shoulder_y,
			20 * delta
		)

		right_shoulder.position.y = move_toward(
			right_shoulder.position.y,
			base_r_shoulder_y,
			20 * delta
		)

func _try_drop_through_one_way() -> bool:
	for index in range(get_slide_collision_count()):
		var collision := get_slide_collision(index)
		if collision.get_normal().y > -0.5:
			continue
		var platform := _get_one_way_platform(collision.get_collider(), collision.get_collider_shape_index())
		if platform != null:
			return _begin_one_way_drop(platform)
	var bounds := _get_player_collision_bounds()
	if bounds.size == Vector2.ZERO:
		return false
	var probe := RectangleShape2D.new()
	probe.size = Vector2(maxf(8.0, bounds.size.x * 0.8), 4.0)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = probe
	query.transform = Transform2D(0.0, Vector2(bounds.get_center().x, bounds.end.y + 1.5))
	query.collision_mask = 0xFFFFFFFF
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	for hit in get_world_2d().direct_space_state.intersect_shape(query, 32):
		var collider_value: Variant = hit.get("collider")
		var shape_index := int(hit.get("shape", -1))
		var platform := _get_one_way_platform(collider_value, shape_index)
		if platform != null:
			return _begin_one_way_drop(platform)
	return false

func _get_one_way_platform(collider_value: Variant, shape_index: int) -> PhysicsBody2D:
	if not is_instance_valid(collider_value) or not collider_value is PhysicsBody2D or shape_index < 0:
		return null
	var platform := collider_value as PhysicsBody2D
	var owner_id := platform.shape_find_owner(shape_index)
	if owner_id < 0 or not platform.is_shape_owner_one_way_collision_enabled(owner_id):
		return null
	return platform

func _begin_one_way_drop(platform: PhysicsBody2D) -> bool:
	if not is_instance_valid(platform):
		return false
	if not drop_through_platforms.has(platform):
		add_collision_exception_with(platform)
		drop_through_platforms.append(platform)
	velocity.y = maxf(velocity.y, 180.0)
	if NetworkManager.is_client() and local_player:
		drop_through_authorize_pending = true
	return true

func _player_overlaps_platform(platform: PhysicsBody2D) -> bool:
	var space_state := get_world_2d().direct_space_state
	for child in get_children():
		if not child is CollisionShape2D:
			continue
		var shape_node := child as CollisionShape2D
		if shape_node.disabled or shape_node.shape == null:
			continue
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = shape_node.shape
		query.transform = shape_node.global_transform
		query.collision_mask = 0xFFFFFFFF
		query.collide_with_bodies = true
		query.collide_with_areas = false
		query.exclude = [get_rid()]
		for hit in space_state.intersect_shape(query, 64):
			if hit.get("collider") == platform:
				return true
	return false

func _update_drop_through_platforms():
	for index in range(drop_through_platforms.size() - 1, -1, -1):
		var platform_value: Variant = drop_through_platforms[index]
		if not is_instance_valid(platform_value) or not platform_value is PhysicsBody2D:
			drop_through_platforms.remove_at(index)
			continue
		var platform := platform_value as PhysicsBody2D
		if _player_overlaps_platform(platform):
			continue
		remove_collision_exception_with(platform)
		drop_through_platforms.remove_at(index)

func _process(_delta: float):
	_sync_role_outline_sprites()

func _physics_process(delta: float):
	_sanitize_held_item_references()
	left_recoil_offset = left_recoil_offset.move_toward(Vector2.ZERO, RECOIL_RECOVERY_SPEED * delta)
	right_recoil_offset = right_recoil_offset.move_toward(Vector2.ZERO, RECOIL_RECOVERY_SPEED * delta)
	if NetworkManager.is_client() and network_player_id == 0:
		return
	if NetworkManager.is_networked() and network_remote:
		if NetworkManager.is_server():
			if is_dead:
				if not death_has_left_floor:
					if not is_on_floor():
						death_has_left_floor = true
					else:
						death_velocity += get_gravity() * delta
				else:
					if not is_on_floor():
						death_velocity += get_gravity() * delta
					else:
						death_velocity.x = move_toward(death_velocity.x, 0.0, friction * delta)
				velocity = death_velocity
				move_and_slide()
				rotation = move_toward(rotation, death_target_rotation, 5.0 * delta)
			else:
				global_position = network_position
				velocity = network_velocity
				update_look()
				update_arms()
				update_animation(delta)
		else:
			if is_dead:
				global_position = network_position
			else:
				global_position = global_position.lerp(network_position, minf(delta * 36.0, 1.0))
				velocity = network_velocity
				update_look()
				update_arms()
				update_animation(delta)
		return

	if NetworkManager.is_client() and local_player and not network_spawn_ready:
		return

	if is_dead:
		if not death_has_left_floor:
			if not is_on_floor():
				death_has_left_floor = true
			else:
				death_velocity += get_gravity() * delta
		else:
			if not is_on_floor():
				death_velocity += get_gravity() * delta
			else:
				death_velocity.x = move_toward(
					death_velocity.x,
					0.0,
					friction * delta
				)

		velocity = death_velocity
		move_and_slide()
		rotation = move_toward(rotation, death_target_rotation, 5.0 * delta)

		return

	if not chat_input_active and Input.is_action_just_pressed("move_down"):
		_try_drop_through_one_way()
	if not is_on_floor():
		velocity += get_gravity() * delta
	var direction := 0.0 if chat_input_active else Input.get_axis("move_left", "move_right")
	if direction != 0:
		velocity.x = move_toward(velocity.x, direction * speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, friction * delta)

	if not chat_input_active and Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_force
	if not chat_input_active and Input.is_action_just_pressed("interact"):
		if NetworkManager.is_client() and local_player:
			NetworkManager.send_to_server({"kind": "controller", "action": "interact", "left_active": Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "right_active": Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)})
		else:
			interact()
	if chat_input_active:
		drop_hold_time = 0.0
		drop_throw_sent = false
	else:
		_handle_drop_input(delta)

	move_and_slide()
	_update_drop_through_platforms()
	var push_force := 80.0

	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var collider := collision.get_collider()
		if collider is RigidBody2D:
			var push_direction := -collision.get_normal()
			push_direction.y = 0
			collider.apply_central_impulse(
				push_direction * push_force
			)

	update_look()
	update_arms()
	update_animation(delta)

	_send_network_state(delta)
# I hate this shit
