extends RigidBody2D

var rep := Reporter.new("Pickup")

@export var grip: Marker2D
@export_range(1.0, 360.0, 1.0) var rotation_step: float = 15.0

var holder_marker: Marker2D = null
var holder_player: CharacterBody2D = null

var saved_collision_layer: int
var saved_collision_mask: int

var original_scale: Vector2

var held: bool = false
var pocketed: bool = false

var facing_right: bool = true
var last_facing_right: bool = true
var actual_facing_right: bool = true

var held_rotation: float = 0.0
var applied_held_rotation: float = 0.0

var collision_shapes: Array[CollisionShape2D] = []

var network_remote := false

func _on_server_message(peer_id: int, message: Dictionary):
	if not NetworkManager.is_server() or not held or holder_player == null:
		return
	var kind: Variant = message.get("kind", "")
	var action: Variant = message.get("action", "")
	if not kind is String or not action is String or kind != "pickup" or action != "rotate":
		return
	if peer_id != int(holder_player.get("network_player_id")):
		return
	if int(message.get("item_id", -1)) != int(get_meta("network_item_id", -2)):
		return
	var step := int(message.get("step", 0))
	if step != -1 and step != 1:
		return
	rotate_held(step)

func get_network_state() -> Dictionary:
	var holder_id := 0
	var hand := -1
	var slot := -1
	if holder_player != null and is_instance_valid(holder_player):
		holder_id = int(holder_player.get("network_player_id"))
		if held:
			hand = get_hand_index()
	if pocketed:
		var parent: Node = get_parent()
		if parent != null:
			if parent.name == "Slot1":
				slot = 0
			elif parent.name == "Slot2":
				slot = 1
		var current: Node = parent
		while current != null:
			if current.name == "Pockets":
				var owner: Node = current.get_parent()
				if owner != null:
					holder_id = int(owner.get("network_player_id"))
				break
			current = current.get_parent()
	var gun: Node = find_child("GunComponent", true, false)
	var gun_state: Dictionary = {}
	if gun != null and gun.has_method("get_network_state"):
		var gun_value: Variant = gun.call("get_network_state")
		if gun_value is Dictionary:
			gun_state = gun_value
	var ammo: Node = find_child("AmmoComponent", true, false)
	var ammo_amount := -1
	if ammo != null:
		var ammo_value: Variant = ammo.get("ammo_amount")
		if ammo_value is int:
			ammo_amount = ammo_value
	return {"id": int(get_meta("network_item_id", 0)), "alive": true, "position": global_position, "rotation": global_rotation, "linear_velocity": linear_velocity, "angular_velocity": angular_velocity, "held_rotation": held_rotation, "held": held, "pocketed": pocketed, "visible": visible, "holder_id": holder_id, "hand": hand, "slot": slot, "gun": gun_state, "ammo_amount": ammo_amount}

func get_hand_index() -> int:
	if holder_marker == null:
		return -1
	var hand_area: Node = holder_marker.get_parent()
	if hand_area == null:
		return -1
	if hand_area.name == "LeftHandArea":
		return 0
	if hand_area.name == "RightHandArea":
		return 1
	return -1

func apply_network_state(state: Dictionary, network_players: Dictionary):
	if not NetworkManager.is_client():
		return
	var gun: Node = find_child("GunComponent", true, false)
	var gun_state: Variant = state.get("gun", {})
	if gun != null and gun_state is Dictionary and gun.has_method("apply_network_state"):
		gun.call("apply_network_state", gun_state)
	var ammo: Node = find_child("AmmoComponent", true, false)
	var ammo_value: Variant = state.get("ammo_amount", -1)
	if ammo != null and ammo_value is int and ammo_value >= 0:
		ammo.set("ammo_amount", ammo_value)
	var holder_id := int(state.get("holder_id", 0))
	var hand := int(state.get("hand", -1))
	var slot := int(state.get("slot", -1))
	var server_held: bool = state.get("held", false) == true
	var server_pocketed: bool = state.get("pocketed", false) == true
	var holder_value: Variant = network_players.get(holder_id, null)
	var local_holder: CharacterBody2D = null
	if holder_value is CharacterBody2D and is_instance_valid(holder_value):
		local_holder = holder_value as CharacterBody2D
	if server_held and local_holder != null and (hand == 0 or hand == 1):
		var marker_value: Variant = local_holder.call("get_hand_marker", hand) if local_holder.has_method("get_hand_marker") else null
		var marker: Marker2D = marker_value as Marker2D
		if marker == null:
			return
		var same_holder := held and holder_player == local_holder and holder_marker == marker
		if local_holder.has_method("clear_item_reference"):
			local_holder.call("clear_item_reference", self)
		holder_player = local_holder
		holder_marker = marker
		if hand == 0:
			local_holder.set("left_item", self)
		else:
			local_holder.set("right_item", self)
		held = true
		pocketed = false
		visible = true
		freeze = true
		collision_mask = 1
		network_remote = local_holder.get("local_player") != true
		var rotation_value: Variant = state.get("held_rotation", held_rotation)
		if rotation_value is float or rotation_value is int:
			held_rotation = float(rotation_value)
		if get_parent() != get_tree().current_scene:
			reparent(get_tree().current_scene, false)
		if not same_holder:
			global_transform = get_target_held_transform(held_rotation, get_player_facing())
		update_held_transform()
		return
	if server_pocketed and slot >= 0 and slot <= 1:
		if local_holder == null:
			held = false
			pocketed = true
			holder_player = null
			holder_marker = null
			visible = false
			freeze = true
			collision_layer = 0
			collision_mask = 0
			return
		var pockets: Node = local_holder.get_node_or_null("Pockets")
		var marker: Marker2D = pockets.get_slot(slot) if pockets != null and pockets.has_method("get_slot") else null
		if marker != null:
			held = false
			pocketed = true
			holder_player = local_holder
			holder_marker = null
			network_remote = local_holder.get("local_player") != true
			reparent(marker, false)
			position = Vector2.ZERO
			visible = false
			freeze = true
			collision_layer = 0
			collision_mask = 0
			if pockets.has_method("set_network_slot"):
				pockets.call("set_network_slot", slot, self)
			return
	if held or pocketed:
		if holder_player != null and holder_player.has_method("clear_item_reference"):
			holder_player.call("clear_item_reference", self)
		held = false
		pocketed = false
		holder_player = null
		holder_marker = null
		network_remote = true
		var world: Node = get_tree().current_scene
		if get_parent() != world:
			reparent(world, false)
		visible = state.get("visible", true)
	freeze = false
	sleeping = false
	collision_layer = saved_collision_layer if saved_collision_layer != 0 else collision_layer
	collision_mask = saved_collision_mask if saved_collision_mask != 0 else 1
	global_position = state.get("position", global_position)
	global_rotation = float(state.get("rotation", global_rotation))
	var velocity_value: Variant = state.get("linear_velocity", Vector2.ZERO)
	if velocity_value is Vector2 and velocity_value.is_finite() and not held and not pocketed:
		linear_velocity = velocity_value
	var angular_velocity_value: Variant = state.get("angular_velocity", 0.0)
	if (angular_velocity_value is float or angular_velocity_value is int) and not held and not pocketed:
		angular_velocity = float(angular_velocity_value)

func _ready():
	add_to_group("interactable")
	if NetworkManager.is_networked():
		NetworkManager.server_message.connect(_on_server_message)
	original_scale = scale
	saved_collision_layer = collision_layer
	saved_collision_mask = collision_mask

	held_rotation = rotation
	applied_held_rotation = rotation

	actual_facing_right = scale.x >= 0.0

	facing_right = actual_facing_right
	last_facing_right = actual_facing_right

	for node in find_children("*", "CollisionShape2D", true, false):
		if not node is CollisionShape2D:
			continue

		var current: Node = node.get_parent()
		var belongs_to_area := false

		while (current != null and current != self):
			if current is Area2D:
				belongs_to_area = true
				break
			current = current.get_parent()
		if not belongs_to_area:
			collision_shapes.append(node as CollisionShape2D)
	if grip == null:
		rep.error("Pickup: Grip is not assigned on " + name)

func find_player_from_marker(marker: Marker2D) -> CharacterBody2D:
	var current: Node = marker
	while current != null:
		if current is CharacterBody2D and not (current is HandCollision):
			return current as CharacterBody2D
		current = current.get_parent()
	return null

func get_player_facing() -> bool:
	if holder_player == null:
		return true
	var value: Variant = holder_player.get("is_facing_right")
	if typeof(value) == TYPE_BOOL:
		return value
		
	return true

func build_held_transform(angle: float, use_facing_right: bool, position_override: Vector2) -> Transform2D:
	var sx := absf(original_scale.x)
	
	if not use_facing_right:
		sx = -sx
		
	var sy := original_scale.y
	var c := cos(angle)
	var s := sin(angle)
	var x_axis := Vector2(c, s) * sx
	var y_axis := Vector2(-s, c) * sy

	return Transform2D(x_axis, y_axis, position_override)

func get_held_transform_at(holder_position: Vector2, angle: float, use_facing_right: bool) -> Transform2D:
	var transform := build_held_transform(angle, use_facing_right, Vector2.ZERO)
	transform.origin = holder_position - transform * grip.position
	return transform

func get_target_held_transform(angle: float, use_facing_right: bool) -> Transform2D:
	return get_held_transform_at(holder_marker.global_position, angle, use_facing_right)

func constrain_holder_position(target_position: Vector2) -> Vector2:
	if not held or holder_marker == null or collision_mask == 0:
		return target_position

	var current_position := holder_marker.global_position
	var facing_right := actual_facing_right
	var desired_facing := get_player_facing()

	if desired_facing != actual_facing_right:
		var facing_transform := get_held_transform_at(current_position, applied_held_rotation, desired_facing)
		if can_place_transform(facing_transform):
			facing_right = desired_facing
	var target_transform := get_held_transform_at(target_position, applied_held_rotation, facing_right)
	if can_place_transform(target_transform):
		return target_position

	var low := 0.0
	var high := 1.0
	var best_position := current_position

	for _i in range(10):
		var middle := (low + high) * 0.5
		var position := current_position + (target_position - current_position) * middle
		var candidate := get_held_transform_at(position, applied_held_rotation, facing_right)
		if can_place_transform(candidate):
			low = middle
			best_position = position
		else:
			high = middle

	return best_position

func can_place_transform(target_transform: Transform2D) -> bool:
	if collision_mask == 0:
		return true
	var space_state := get_world_2d().direct_space_state

	for shape_node in collision_shapes:
		if not is_instance_valid(shape_node):
			continue
		if shape_node.disabled:
			continue
		if shape_node.shape == null:
			continue

		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = shape_node.shape
		var shape_local_transform := global_transform.affine_inverse() * shape_node.global_transform

		query.transform = target_transform * shape_local_transform
		query.collision_mask = collision_mask
		query.collide_with_bodies = true
		query.collide_with_areas = false
		query.exclude = [get_rid()]

		var hits := space_state.intersect_shape(query, 1)
		if not hits.is_empty():
			return false
			
	return true

func resolve_held_transform(desired_transform: Transform2D, desired_rotation: float, desired_facing: bool) -> Transform2D:
	var current_transform := global_transform
	if desired_facing != actual_facing_right:
		if can_place_transform(desired_transform):
			actual_facing_right = desired_facing
			applied_held_rotation = desired_rotation
			held_rotation = desired_rotation

			return desired_transform
		desired_transform = get_target_held_transform(desired_rotation, actual_facing_right)
	else:
		actual_facing_right = desired_facing
	if can_place_transform(desired_transform):
		applied_held_rotation = desired_rotation
		held_rotation = desired_rotation

		return desired_transform

	var low := 0.0
	var high := 1.0
	var best := current_transform
	var best_angle := applied_held_rotation

	for _i in range(8):
		var middle := (low + high) * 0.5

		var angle := lerp_angle(applied_held_rotation, desired_rotation, middle)
		var position := current_transform.origin.lerp(desired_transform.origin, middle)
		var candidate := build_held_transform(angle, actual_facing_right, position)

		if can_place_transform(candidate):
			low = middle
			best = candidate
			best_angle = angle
		else:
			high = middle

	applied_held_rotation = best_angle
	held_rotation = best_angle

	return best

func pickup(hand_marker: Marker2D) -> bool:
	if held or pocketed:
		return false
	if hand_marker == null:
		return false
	if grip == null:
		return false

	holder_marker = hand_marker
	holder_player = find_player_from_marker(hand_marker)

	if holder_player == null:
		return false
	held = true

	saved_collision_layer = collision_layer
	saved_collision_mask = collision_mask

	freeze = true
	sleeping = true

	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0

	collision_mask = 1
	visible = true

	held_rotation = rotation
	applied_held_rotation = rotation

	facing_right = get_player_facing()

	last_facing_right = facing_right
	actual_facing_right = facing_right

	update_held_transform()

	return true

func set_held_collision_active(active: bool):
	if not held or pocketed:
		return
	collision_mask = 1 if active else 0

func update_held_transform():
	if not held:
		return
	if holder_marker == null:
		return
	if holder_player == null:
		return
	facing_right = get_player_facing()
	last_facing_right = facing_right
	collision_mask = 1 if is_hand_active() else 0
	var desired_transform := get_target_held_transform(held_rotation, facing_right)
	global_transform = resolve_held_transform(desired_transform, held_rotation, facing_right)

func is_hand_active() -> bool:
	if holder_marker == null:
		return false
	var hand_area: Node = holder_marker.get_parent()
	if hand_area == null:
		return false
	if hand_area.name == "LeftHandArea":
		if NetworkManager.is_networked() and holder_player != null and holder_player.get("local_player") != true:
			return holder_player.call("is_hand_active", 0) == true
		return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if hand_area.name == "RightHandArea":
		if NetworkManager.is_networked() and holder_player != null and holder_player.get("local_player") != true:
			return holder_player.call("is_hand_active", 1) == true
		return Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)

	return false

func update_rotation():
	if not held or network_remote:
		return
	if not is_hand_active():
		return
	var step := 0
	if Input.is_action_just_pressed("rotate_up"):
		step = -1
	elif Input.is_action_just_pressed("rotate_down"):
		step = 1
	if step == 0:
		return
	rotate_held(step)
	if NetworkManager.is_client():
		NetworkManager.send_to_server({"kind": "pickup", "action": "rotate", "item_id": int(get_meta("network_item_id", -1)), "step": step})

func rotate_held(step: int):
	if not held or step == 0:
		return
	held_rotation = wrapf(held_rotation + deg_to_rad(rotation_step) * step, -PI, PI)

func get_held_rotation() -> float:
	if held:
		return applied_held_rotation
	return rotation

func set_held_rotation(value: float):
	if held:
		held_rotation = wrapf(value, -PI, PI)
		update_held_transform()
	else:
		rotation = value

func place_in_pocket(slot: Marker2D, player: CharacterBody2D) -> bool:
	if held or pocketed or slot == null or player == null or not is_instance_valid(player):
		return false
	if grip == null:
		return false
	holder_player = player
	holder_marker = null
	held = false
	pocketed = true
	visible = false
	freeze = true
	sleeping = true
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	collision_layer = 0
	collision_mask = 0
	reparent(slot, false)
	position = Vector2.ZERO
	rotation = 0.0
	var pockets: Node = slot.get_parent()
	if pockets != null and pockets.has_method("set_network_slot"):
		pockets.call("set_network_slot", 0 if slot.name == "Slot1" else 1, self)
	return true

func drop_from_pocket():
	if not pocketed:
		return
	var saved_transform: Transform2D = global_transform
	pocketed = false
	holder_marker = null
	holder_player = null
	var world: Node = get_tree().current_scene
	if world != null and get_parent() != world:
		reparent(world, false)
	global_transform = saved_transform
	visible = true
	freeze = false
	sleeping = false
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	collision_layer = saved_collision_layer
	collision_mask = saved_collision_mask

func store_in_pocket(slot: Marker2D) -> bool:
	if not held:
		return false
	if pocketed:
		return false
	if slot == null:
		return false

	held = false
	pocketed = true

	holder_marker = null
	holder_player = null

	reparent(slot, false)
	visible = false

	freeze = true
	sleeping = true

	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0

	collision_layer = 0
	collision_mask = 0

	position = Vector2.ZERO
	return true

func take_from_pocket(hand_marker: Marker2D) -> bool:
	if not pocketed:
		return false
	if hand_marker == null:
		return false
	if grip == null:
		return false

	holder_marker = hand_marker
	holder_player = find_player_from_marker(hand_marker)

	if holder_player == null:
		return false
	pocketed = false
	held = true

	var world: Node = get_tree().current_scene
	reparent(world, false)

	visible = true
	freeze = true
	sleeping = true

	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0

	collision_layer = saved_collision_layer
	collision_mask = 1
	facing_right = get_player_facing()

	last_facing_right = facing_right
	actual_facing_right = facing_right

	update_held_transform()
	return true

func drop(throw_direction: Vector2 = Vector2.ZERO, throw_impulse: float = 0.0):
	if not held:
		return
	var saved_transform: Transform2D = global_transform
	held = false
	holder_marker = null
	holder_player = null
	var world: Node = get_tree().current_scene
	reparent(world, false)
	visible = true
	global_transform = saved_transform
	freeze = false
	sleeping = false
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	collision_layer = saved_collision_layer
	collision_mask = saved_collision_mask
	scale = original_scale
	if throw_impulse > 0.0 and throw_direction.is_finite() and throw_direction.length_squared() > 0.0001:
		apply_central_impulse(throw_direction.normalized() * throw_impulse)

func _physics_process(_delta):
	if held:
		update_rotation()
		update_held_transform()
