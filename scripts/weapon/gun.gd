extends Node2D

@export_category("Weapon")

@export var muzzle: Marker2D
@export var bullet_scene: PackedScene
@export var fire_sound: AudioStream
@export_range(0.0, 5.0, 0.1) var recoil_strength: float = 1.0
@export_range(0.01, 1000.0, 0.01) var fire_rate: float = 5.0

@export_category("Magazine")

@export_range(1, 1000000, 1) var magazine_size: int = 8
@export_range(0, 1000000, 1) var magazine_ammo: int = 8
@export_range(0, 1000000, 1) var reserve_ammo: int = 0

@export_category("Reload")

@export_range(0.0, 30.0, 0.05) var reload_time: float = 1.0
@export_range(0.0, 90.0, 1.0) var reload_angle: float = 15.0

var fire_cooldown: float = 0.0
var is_reloading: bool = false
var fire_audio: AudioStreamPlayer2D

var rep := Reporter.new("Gun")

func _ready():
	fire_audio = AudioStreamPlayer2D.new()
	fire_audio.name = "FireAudio"
	fire_audio.max_distance = 1800.0
	fire_audio.stream = fire_sound
	add_child(fire_audio)
	if NetworkManager.is_networked():
		NetworkManager.server_message.connect(_on_server_message)

func play_fire_sound():
	if fire_sound == null:
		return
	if fire_audio == null or not is_instance_valid(fire_audio):
		fire_audio = AudioStreamPlayer2D.new()
		fire_audio.name = "FireAudio"
		fire_audio.max_distance = 1800.0
		add_child(fire_audio)
	fire_audio.stream = fire_sound
	fire_audio.play()

func apply_recoil(shot_direction: Vector2):
	if recoil_strength <= 0.0 or shot_direction.length_squared() < 0.001:
		return
	var player := get_player()
	var marker := get_holder_marker()
	if player == null or marker == null or not player.has_method("apply_recoil"):
		return
	var hand_area := marker.get_parent()
	if hand_area == null:
		return
	var hand_index := 0 if hand_area.name == "LeftHandArea" else 1 if hand_area.name == "RightHandArea" else -1
	if hand_index >= 0:
		player.call("apply_recoil", hand_index, shot_direction.normalized(), recoil_strength)

func play_remote_shot(shot_direction: Vector2):
	play_fire_sound()
	apply_recoil(shot_direction)

func _on_server_message(peer_id: int, message: Dictionary):
	if not NetworkManager.is_server():
		return
	if message.get("kind", "") != "gun":
		return
	if int(message.get("item_id", -1)) != int(get_parent().get_meta("network_item_id", -2)):
		return
	var player := get_player()
	if player == null or peer_id != int(player.get("network_player_id")):
		return
	var action := str(message.get("action", ""))
	if action == "shoot" and is_hand_active():
		shoot()
	elif action == "reload":
		reload()

func get_network_state() -> Dictionary:
	return {"magazine_ammo": magazine_ammo, "reserve_ammo": reserve_ammo, "is_reloading": is_reloading}

func apply_network_state(state: Dictionary):
	if state.has("magazine_ammo"):
		magazine_ammo = int(state["magazine_ammo"])
	if state.has("reserve_ammo"):
		reserve_ammo = int(state["reserve_ammo"])
	if state.has("is_reloading"):
		is_reloading = state["is_reloading"] == true

func _process(delta: float):
	if fire_cooldown > 0.0:
		fire_cooldown -= delta
	if not is_held():
		return
	var player := get_player()
	if player == null or player.is_dead:
		return
	if player.get("chat_input_active") == true:
		return
	if NetworkManager.is_networked() and player.get("local_player") != true:
		return
	if NetworkManager.is_client() and player.get("local_player") == true:
		if Input.is_action_just_pressed("reload"):
			NetworkManager.send_to_server({"kind": "gun", "action": "reload", "item_id": int(get_parent().get_meta("network_item_id", -1))})
			return
		if is_reloading or not is_hand_active() or fire_cooldown > 0.0:
			return
		if Input.is_action_pressed("fire"):
			fire_cooldown = 1.0 / fire_rate
			NetworkManager.send_to_server({"kind": "gun", "action": "shoot", "item_id": int(get_parent().get_meta("network_item_id", -1))})
		return
	if Input.is_action_just_pressed("reload"):
		reload()
		return
	if is_reloading or not is_hand_active() or not Input.is_action_pressed("fire") or fire_cooldown > 0.0:
		return
	shoot()

func get_pickup() -> Node:
	var weapon_root: Node = get_parent()

	if weapon_root == null:
		return null
	if not weapon_root.has_method("update_held_transform"):
		return null
	return weapon_root

func is_held() -> bool:
	var pickup: Node = get_pickup()

	if pickup == null:
		return false
	var value: Variant = pickup.get("held")
	if typeof(value) != TYPE_BOOL:
		return false
	return value == true

func get_holder_marker() -> Marker2D:
	var pickup: Node = get_pickup()

	if pickup == null:
		return null
	var value: Variant = pickup.get("holder_marker")
	if value is Marker2D:
		return value as Marker2D
	return null

func is_hand_active() -> bool:
	var marker: Marker2D = get_holder_marker()
	if marker == null:
		return false
	var hand_area: Node = marker.get_parent()
	if hand_area == null:
		return false
	var player := get_player()
	if player != null and player.get("local_player") != true and NetworkManager.is_networked():
		if hand_area.name == "LeftHandArea":
			return player.call("is_hand_active", 0) == true
		if hand_area.name == "RightHandArea":
			return player.call("is_hand_active", 1) == true
	if hand_area.name == "LeftHandArea":
		return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if hand_area.name == "RightHandArea":
		return Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	return false

func shoot():
	if muzzle == null:
		rep.error("Muzzle is not assigned")
		return
	if bullet_scene == null:
		rep.error("Bullet Scene is not assigned")
		return
	if magazine_ammo <= 0:
		rep.warn("Magazine is empty")
		return

	fire_cooldown = 1.0 / fire_rate
	var bullet: Node = bullet_scene.instantiate()
	if bullet == null:
		rep.error("Failed to instantiate Bullet")
		return

	magazine_ammo -= 1
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = muzzle.global_position
	var direction: Vector2 = muzzle.global_transform.x.normalized()
	var player: CharacterBody2D = get_player()

	if bullet.has_method("setup"):
		bullet.setup(direction, player)
	else:
		rep.error("Bullet has no setup() method")
		GC.destroy(bullet)

		return
	if NetworkManager.is_server():
		var bullet_id := NetworkManager.register_bullet(bullet)
		if bullet.has_method("set_network_bullet_id"):
			bullet.call("set_network_bullet_id", bullet_id)
	play_remote_shot(direction)
	if NetworkManager.is_server():
		NetworkManager.broadcast_gunshot(int(get_parent().get_meta("network_item_id", 0)), direction)
	rep.debug("Fired Bullet | Direction: " + str(direction))

func get_player() -> CharacterBody2D:
	var marker: Marker2D = get_holder_marker()
	if marker == null:
		return null
	var current: Node = marker
	while current != null:
		if (current is CharacterBody2D and not (current is HandCollision)):
			return current as CharacterBody2D
		current = current.get_parent()
	return null

func reload():
	if is_reloading:
		return
	if magazine_ammo >= magazine_size:
		return
	if reserve_ammo <= 0:
		return

	var weapon_root: Node2D = get_parent() as Node2D
	if weapon_root == null:
		rep.error("Weapon root is not Node2D")
		return
		
	is_reloading = true
	var previous_rotation: float
	
	if weapon_root.has_method("get_held_rotation"):
		previous_rotation = weapon_root.get_held_rotation()
	else:
		previous_rotation = weapon_root.rotation
		
	if weapon_root.has_method("set_held_rotation"):
		weapon_root.set_held_rotation(previous_rotation + deg_to_rad(reload_angle))
	else:
		weapon_root.rotation = previous_rotation + deg_to_rad(reload_angle)

	rep.debug("Reload started")
	await get_tree().create_timer(reload_time).timeout
	if not is_instance_valid(weapon_root):
		is_reloading = false
		return
	var needed: int = magazine_size - magazine_ammo
	var loaded: int = mini(needed, reserve_ammo)
	magazine_ammo += loaded
	reserve_ammo -= loaded

	if weapon_root.has_method("set_held_rotation"):
		weapon_root.set_held_rotation(previous_rotation)
	else:
		weapon_root.rotation = previous_rotation

	is_reloading = false
	rep.debug("Reload finished | Magazine: %d/%d | Reserve: %d" % [magazine_ammo, magazine_size, reserve_ammo])

func add_reserve_ammo(amount: int) -> int:
	if amount <= 0:
		return 0

	reserve_ammo += amount
	return amount
