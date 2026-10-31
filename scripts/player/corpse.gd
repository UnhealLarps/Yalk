extends Node

func begin_death(impulse_direction: Vector2, state: Dictionary = {}):
	var player := get_parent() as CharacterBody2D
	if player == null:
		return
	if player.has_method("drop_all_items"):
		player.call("drop_all_items")
	player.set("left_hand_is_disabled", true)
	player.set("right_hand_is_disabled", true)
	for path in ["LeftHandCollision/LeftHandArea", "RightHandCollision/RightHandArea"]:
		var area := player.get_node_or_null(path) as Area2D
		if area != null:
			area.monitoring = false
			area.collision_layer = 0
			area.collision_mask = 0
	for path in ["LeftHandCollision", "RightHandCollision"]:
		var hand := player.get_node_or_null(path) as CollisionObject2D
		if hand != null:
			hand.collision_layer = 0
			hand.collision_mask = 0
	for path in ["BodyVisuals/Hands/LeftShoulder/Skin", "BodyVisuals/Hands/LeftShoulder/Muscle", "BodyVisuals/Hands/LeftShoulder/Skeleton", "BodyVisuals/Hands/RightShoulder/Skin", "BodyVisuals/Hands/RightShoulder/Muscle", "BodyVisuals/Hands/RightShoulder/Skeleton"]:
		var sprite := player.get_node_or_null(path) as CanvasItem
		if sprite != null:
			sprite.visible = false
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.enabled = false
	var direction := impulse_direction.normalized()
	if direction.length_squared() < 0.000001:
		direction = Vector2.RIGHT
	var death_velocity := direction * 260.0
	death_velocity.y -= 70.0
	var velocity_value: Variant = state.get("death_velocity", null)
	if velocity_value is Vector2:
		death_velocity = velocity_value
	player.set("death_velocity", death_velocity)
	player.set("death_has_left_floor", false)
	player.set("death_target_rotation", float(state.get("death_rotation", 0.7 if direction.x > 0.1 else -0.7 if direction.x < -0.1 else 0.0)))
