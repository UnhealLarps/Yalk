extends Node

const PUSH_IMPULSE := Vector2(360.0, -110.0)
const PUSH_WINDOW_MSEC := 2500
const PUSHES_TO_DISARM := 3
const POCKET_DROP_CHANCE := 0.35
const POCKET_DROP_IMPULSE := 90.0

var player: CharacterBody2D
var push_times: Array[int] = []
var blocked_fire_hand := -1

func _ready() -> void:
	player = get_parent() as CharacterBody2D
	if NetworkManager.is_networked():
		NetworkManager.server_message.connect(_on_server_message)

func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("fire"):
		return
	if event is InputEventKey and event.echo:
		return
	if player == null or not is_instance_valid(player) or player.is_dead or player.chat_input_active:
		return
	if NetworkManager.is_networked() and not player.local_player:
		return
	for hand_index in range(2):
		if not player.is_hand_active(hand_index) or not _hand_overlaps_player(hand_index):
			continue
		blocked_fire_hand = hand_index
		if NetworkManager.is_client():
			NetworkManager.send_to_server({"kind": "push", "action": "attempt", "hand": hand_index})
		else:
			_try_push_on_server(hand_index)
		return

func _process(_delta: float) -> void:
	if not Input.is_action_pressed("fire"):
		blocked_fire_hand = -1

func reset_for_round() -> void:
	push_times.clear()
	blocked_fire_hand = -1

func blocks_fire_for_hand(hand_index: int) -> bool:
	return blocked_fire_hand == hand_index and Input.is_action_pressed("fire")

func _get_hand_area(hand_index: int) -> Area2D:
	if hand_index == 0:
		return player.get_node_or_null("LeftHandCollision/LeftHandArea") as Area2D
	if hand_index == 1:
		return player.get_node_or_null("RightHandCollision/RightHandArea") as Area2D
	return null

func _hand_overlaps_player(hand_index: int) -> bool:
	var hand_area := _get_hand_area(hand_index)
	if hand_area == null or not hand_area.monitoring:
		return false
	for body in hand_area.get_overlapping_bodies():
		if body is CharacterBody2D and body != player and body.has_node("Push") and body.get("is_dead") != true:
			return true
	return false

func _on_server_message(peer_id: int, message: Dictionary) -> void:
	if not NetworkManager.is_server() or player == null or not is_instance_valid(player):
		return
	if message.get("kind", "") != "push" or message.get("action", "") != "attempt":
		return
	if peer_id != int(player.get("network_player_id")):
		return
	var hand_index := int(message.get("hand", -1))
	if hand_index < 0 or hand_index > 1 or not player.is_hand_active(hand_index):
		return
	_try_push_on_server(hand_index)

func _try_push_on_server(hand_index: int) -> void:
	if NetworkManager.is_networked() and not NetworkManager.is_server():
		return
	if player == null or player.is_dead:
		return
	var hand_area := _get_hand_area(hand_index)
	if hand_area == null or not hand_area.monitoring:
		return
	var target: CharacterBody2D = null
	var target_distance := INF
	for body in hand_area.get_overlapping_bodies():
		if not body is CharacterBody2D or body == player or not body.has_node("Push") or body.get("is_dead") == true:
			continue
		var distance := hand_area.global_position.distance_squared_to(body.global_position)
		if distance < target_distance:
			target = body as CharacterBody2D
			target_distance = distance
	if target == null:
		return
	var horizontal_direction := signf(target.global_position.x - player.global_position.x)
	if is_zero_approx(horizontal_direction):
		horizontal_direction = 1.0 if player.is_facing_right else -1.0
	var impulse := Vector2(horizontal_direction * PUSH_IMPULSE.x, PUSH_IMPULSE.y)
	var target_push := target.get_node_or_null("Push")
	if target_push == null or not target_push.has_method("receive_server_push"):
		return
	target_push.call("receive_server_push", impulse)

func receive_server_push(impulse: Vector2) -> void:
	if not NetworkManager.is_server_authority() or player == null or player.is_dead or not impulse.is_finite():
		return
	if NetworkManager.is_networked() and not player.local_player:
		var peer_id := int(player.get("network_player_id"))
		if peer_id > 1:
			apply_network_push.rpc_id(peer_id, impulse)
		else:
			apply_network_push(impulse)
	else:
		apply_network_push(impulse)
	_register_push(impulse)

@rpc("authority", "call_remote", "reliable", 0)
func apply_network_push(impulse: Vector2) -> void:
	if player == null or not is_instance_valid(player) or player.is_dead or not impulse.is_finite():
		return
	player.velocity += impulse

func _register_push(impulse: Vector2) -> void:
	var now := Time.get_ticks_msec()
	for index in range(push_times.size() - 1, -1, -1):
		if now - push_times[index] > PUSH_WINDOW_MSEC:
			push_times.remove_at(index)
	push_times.append(now)
	if push_times.size() < PUSHES_TO_DISARM:
		return
	push_times.clear()
	_drop_held_items(impulse)
	_drop_pocket_items()

func _drop_held_items(impulse: Vector2) -> void:
	var direction := Vector2(signf(impulse.x), -0.15)
	if direction.length_squared() < 0.001:
		direction = Vector2.RIGHT
	for property_name in ["left_item", "right_item"]:
		var item_value: Variant = player.get(property_name)
		if item_value == null or not is_instance_valid(item_value):
			player.set(property_name, null)
			continue
		if item_value.has_method("drop"):
			item_value.call("drop", direction, POCKET_DROP_IMPULSE)
		player.set(property_name, null)

func _drop_pocket_items() -> void:
	var pockets := player.get_node_or_null("Pockets")
	if pockets == null:
		return
	var slot_values: Variant = pockets.get("slots")
	if not slot_values is Array:
		return
	for item_value in slot_values.duplicate():
		if item_value == null or not is_instance_valid(item_value) or randf() >= POCKET_DROP_CHANCE:
			continue
		if pockets.has_method("clear_network_item"):
			pockets.call("clear_network_item", item_value)
		if item_value.has_method("drop_from_pocket"):
			item_value.call("drop_from_pocket")
