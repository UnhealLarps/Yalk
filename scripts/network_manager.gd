# even worse shit than controller
extends Node

signal server_message(peer_id: int, message: Dictionary)
signal server_player_state(peer_id: int, state: Dictionary)
signal chat_message_received(sender_id: int, nickname: String, message: String, sender_position: Vector2)
signal server_probe_finished(ip: String, port: int, success: bool)

const CHAT_MAX_MESSAGE_LENGTH := 200
const CHAT_RATE_LIMIT_MSEC := 350
var last_chat_message_msec: Dictionary = {}

const MAX_CONNECTIONS := 16
const SERVER_LIST_PATH := "user://servers.json"
const PLAYER_STATE_RATE := 60.0
const ITEM_STATE_RATE := 30.0
const PLAYER_STATE_MIN_INTERVAL_USEC := 10000
const PLAYER_NAME_PREFIX := "Player_"

var rep := Reporter.new("NetworkManager")
var network_active := false
var local_player_id := 0
var server_name := "Yalk Server"
var host_port := 27015
var configured_max_players := MAX_CONNECTIONS + 1
var pending_server_entry: Dictionary = {}
var server_probe_active := false
var server_probe_ip := ""
var server_probe_port := -1
var server_probe_generation := 0
var prepared_scene: Node = null
var players: Dictionary = {}
var items: Dictionary = {}
var spawn_claims: Dictionary = {}
var registered_peers: Dictionary = {}
var player_timer := 0.0
var item_timer := 0.0
var last_player_state_time: Dictionary = {}
var last_player_sequence: Dictionary = {}
var last_correction_time: Dictionary = {}
var last_bullet_id := 0
var next_network_item_id := 1
var disconnect_cleanup_scheduled := false
var ghosts: Dictionary = {}
var round_manager: Node = null
var last_client_round_number := 0
var cached_round_active: Array[int] = []
var cached_round_waiting: Array[int] = []
var cached_round_positions: Dictionary = {}
var cached_round_number := 0
var cached_round_state_valid := false
var round_scene_synced := false
var pending_player_states: Dictionary = {}
var clock_sync_timer := 0.0
var clock_offset_usec := 0
var clock_offset_initialized := false

func _ready():
	_create_round_manager()
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	if Args.host:
		host()
	elif not Args.connect_address.is_empty():
		connect_to(Args.connect_address)

func _process(delta: float):
	if server_probe_active:
		return
	_prepare_scene()
	_flush_pending_player_states()
	if is_client():
		clock_sync_timer += delta
		var ping_interval: float = 0.25 if not clock_offset_initialized else 2.0
		if clock_sync_timer >= ping_interval:
			clock_sync_timer = 0.0
			_send_clock_ping()
	if not is_server():
		return
	player_timer += delta
	item_timer += delta
	if player_timer >= 1.0 / PLAYER_STATE_RATE:
		player_timer = 0.0
		broadcast_player_states()
	if item_timer >= 1.0 / ITEM_STATE_RATE:
		item_timer = 0.0
		broadcast_item_states()

func get_estimated_server_time_usec() -> int:
	if not clock_offset_initialized:
		return 0
	return Time.get_ticks_usec() + clock_offset_usec

func _send_clock_ping():
	if not is_client() or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	clock_ping.rpc_id(1, Time.get_ticks_usec())

@rpc("any_peer", "call_remote", "unreliable", 9)
func clock_ping(client_sent_usec: int):
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id <= 0:
		return
	var server_received_usec := Time.get_ticks_usec()
	var server_sent_usec := Time.get_ticks_usec()
	clock_pong.rpc_id(peer_id, client_sent_usec, server_received_usec, server_sent_usec)

@rpc("authority", "call_remote", "unreliable", 9)
func clock_pong(client_sent_usec: int, server_received_usec: int, server_sent_usec: int):
	if not is_client():
		return
	var client_received_usec := Time.get_ticks_usec()
	var measured_offset := int(round((float(server_received_usec - client_sent_usec) + float(server_sent_usec - client_received_usec)) / 2.0))
	if clock_offset_initialized:
		clock_offset_usec = int(round(lerpf(float(clock_offset_usec), float(measured_offset), 0.2)))
	else:
		clock_offset_usec = measured_offset
		clock_offset_initialized = true

func is_networked() -> bool:
	return network_active

func is_server() -> bool:
	return network_active and multiplayer.is_server()

func is_client() -> bool:
	return network_active and not multiplayer.is_server()

func is_server_authority() -> bool:
	return not network_active or multiplayer.is_server()

func host(port: int = -1, max_players: int = -1, requested_server_name: String = "") -> int:
	if network_active:
		return ERR_ALREADY_IN_USE
	host_port = Args.port if port <= 0 else clampi(port, 1, 65535)
	configured_max_players = MAX_CONNECTIONS + 1 if max_players <= 0 else clampi(max_players, 2, 64)
	server_name = requested_server_name.strip_edges()
	if server_name.is_empty():
		server_name = "Yalk Server"
	var max_clients := clampi(configured_max_players - 1, 1, 63)
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(host_port, max_clients)
	if error != OK:
		rep.error("Failed to host: %s" % error_string(error))
		return error
	multiplayer.multiplayer_peer = peer
	network_active = true
	local_player_id = 0 if Args.headless else 1
	rep.info("%s:%d" % [_get_host_ip(), host_port])
	return OK

func connect_to(address: String, port: int = -1) -> int:
	if network_active:
		return ERR_ALREADY_IN_USE
	if address.strip_edges().is_empty():
		return ERR_INVALID_PARAMETER
	var host_address := address.strip_edges()
	var target_port := Args.port if port <= 0 else clampi(port, 1, 65535)
	if port <= 0 and host_address.count(":") == 1:
		var parts := host_address.split(":")
		if parts.size() == 2 and String(parts[1]).is_valid_int():
			host_address = parts[0]
			target_port = clampi(int(parts[1]), 1, 65535)
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(host_address, target_port)
	if error != OK:
		rep.error("Failed to connect: %s" % error_string(error))
		return error
	multiplayer.multiplayer_peer = peer
	network_active = true
	return OK

func get_host_address() -> String:
	return "%s:%d" % [_get_host_ip(), host_port]

func set_pending_server_entry(entry: Dictionary) -> void:
	pending_server_entry = entry.duplicate(true)

func probe_server_info(ip: String, port: int) -> int:
	if network_active or server_probe_active:
		return ERR_ALREADY_IN_USE
	if ip.strip_edges().is_empty() or port < 1 or port > 65535:
		return ERR_INVALID_PARAMETER
	server_probe_active = true
	server_probe_generation += 1
	server_probe_ip = ip.strip_edges()
	server_probe_port = port
	pending_server_entry = {"ip": server_probe_ip, "port": server_probe_port}
	var error := connect_to(server_probe_ip, server_probe_port)
	if error != OK:
		_update_saved_server_status(server_probe_ip, server_probe_port, false)
		server_probe_active = false
		server_probe_ip = ""
		server_probe_port = -1
		pending_server_entry.clear()
		return error
	_wait_for_server_probe(server_probe_generation)
	return OK

func _wait_for_server_probe(generation: int) -> void:
	await get_tree().create_timer(5.0).timeout
	if server_probe_active and server_probe_generation == generation:
		_finish_server_probe(false)

func cancel_server_probe() -> void:
	if not server_probe_active:
		return
	server_probe_active = false
	server_probe_ip = ""
	server_probe_port = -1
	disconnect_network()

func _finish_server_probe(success: bool) -> void:
	if not server_probe_active:
		return
	var ip := server_probe_ip
	var port := server_probe_port
	server_probe_active = false
	server_probe_ip = ""
	server_probe_port = -1
	if not success:
		_update_saved_server_status(ip, port, false)
	disconnect_network()
	server_probe_finished.emit(ip, port, success)

func _update_saved_server_status(ip: String, port: int, online: bool) -> void:
	if not FileAccess.file_exists(SERVER_LIST_PATH):
		return
	var file := FileAccess.open(SERVER_LIST_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Array):
		return
	var entries: Array = parsed
	for i in range(entries.size()):
		if not (entries[i] is Dictionary):
			continue
		var entry: Dictionary = entries[i]
		if str(entry.get("ip", entry.get("address", ""))) != ip or int(entry.get("port", port)) != port:
			continue
		entry["status"] = "online" if online else "offline"
		if not online:
			entry["players"] = -1
			entry["max_players"] = -1
		entries[i] = entry
		break
	var output_file := FileAccess.open(SERVER_LIST_PATH, FileAccess.WRITE)
	if output_file != null:
		output_file.store_string(JSON.stringify(entries, "\t"))
		output_file.close()

@rpc("any_peer", "call_remote", "reliable", 10)
func request_server_info() -> void:
	if not is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id <= 1:
		return
	_register_peer(peer_id)
	server_info_received.rpc_id(peer_id, server_name, get_connected_peer_ids().size(), configured_max_players)

@rpc("any_peer", "call_remote", "reliable", 10)
func request_server_info_probe() -> void:
	if not is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id <= 1:
		return
	server_info_received.rpc_id(peer_id, server_name, get_connected_peer_ids().size(), configured_max_players)

func _register_peer(peer_id: int) -> void:
	if not is_server() or peer_id <= 1 or registered_peers.has(peer_id):
		return
	registered_peers[peer_id] = true
	last_player_state_time[peer_id] = 0
	last_player_sequence[peer_id] = 0
	if round_manager != null and round_manager.has_method("player_joined"):
		round_manager.player_joined(peer_id)
	if round_manager != null and round_manager.has_method("should_have_player") and round_manager.should_have_player(peer_id) and _get_player(peer_id) == null:
		_adopt_or_spawn_player(peer_id, false, _get_spawn_position(peer_id))
	for id in players.keys():
		var other := _get_player(int(id))
		if other != null and other.has_method("get_network_state"):
			var state_value: Variant = other.call("get_network_state")
			if state_value is Dictionary:
				var state: Dictionary = state_value
				state["id"] = int(id)
				state["sequence"] = int(last_player_sequence.get(int(id), 0))
				receive_initial_player_state.rpc_id(peer_id, state)
	for item_id in items.keys():
		var item := _get_item(int(item_id))
		if item != null:
			var state := _build_item_state(int(item_id), item)
			if not state.is_empty():
				receive_initial_item_state.rpc_id(peer_id, state)
	if round_manager != null and round_manager.has_method("send_state_to_peer"):
		round_manager.send_state_to_peer(peer_id)

@rpc("authority", "call_remote", "reliable", 10)
func server_info_received(received_name: String, player_count: int, max_players: int) -> void:
	if not is_client() or pending_server_entry.is_empty():
		return
	var ip := str(pending_server_entry.get("ip", ""))
	var port := int(pending_server_entry.get("port", Args.port))
	var entries: Array = []
	if FileAccess.file_exists(SERVER_LIST_PATH):
		var input_file := FileAccess.open(SERVER_LIST_PATH, FileAccess.READ)
		if input_file != null:
			var parsed: Variant = JSON.parse_string(input_file.get_as_text())
			input_file.close()
			if parsed is Array:
				entries = parsed
	var found := false
	for i in range(entries.size()):
		if not (entries[i] is Dictionary):
			continue
		var entry: Dictionary = entries[i]
		if str(entry.get("ip", entry.get("address", ""))) == ip and int(entry.get("port", port)) == port:
			entry["server_name"] = received_name
			entry["status"] = "online"
			entry["players"] = player_count
			entry["max_players"] = max_players
			entry["ip"] = ip
			entry["port"] = port
			entries[i] = entry
			found = true
			break
	if not found:
		entries.append({"name": "", "server_name": received_name, "ip": ip, "port": port, "players": player_count, "max_players": max_players, "status": "online"})
	var output_file := FileAccess.open(SERVER_LIST_PATH, FileAccess.WRITE)
	if output_file != null:
		output_file.store_string(JSON.stringify(entries, "\t"))
		output_file.close()
	pending_server_entry.clear()
	if server_probe_active:
		call_deferred("_finish_server_probe", true)

func disconnect_network():
	if multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	network_active = false
	disconnect_cleanup_scheduled = false
	local_player_id = 0
	prepared_scene = null
	players.clear()
	items.clear()
	spawn_claims.clear()
	registered_peers.clear()
	pending_server_entry.clear()
	last_player_state_time.clear()
	last_player_sequence.clear()
	last_correction_time.clear()
	player_timer = 0.0
	item_timer = 0.0
	last_bullet_id = 0
	clock_sync_timer = 0.0
	clock_offset_usec = 0
	clock_offset_initialized = false
	last_chat_message_msec.clear()
	pending_player_states.clear()
	last_client_round_number = 0
	cached_round_active.clear()
	cached_round_waiting.clear()
	cached_round_positions.clear()
	cached_round_number = 0
	cached_round_state_valid = false
	round_scene_synced = false
	if round_manager != null and is_instance_valid(round_manager):
		round_manager.set("started", false)
		round_manager.set("last_received_map_revision", -1)

func send_to_server(message: Dictionary):
	if not is_client():
		return
	server_message_rpc.rpc_id(1, message)

func send_player_state(state: Dictionary):
	if not is_client():
		return
	player_state_rpc.rpc_id(1, state)

func send_chat_message(message: String, _sender_position: Vector2 = Vector2.ZERO) -> void:
	var clean_message := _sanitize_chat_message(message)
	if clean_message.is_empty():
		return
	if not is_networked():
		var player := _find_offline_chat_player()
		var position := player.global_position if player != null else Vector2.ZERO
		_dispatch_chat_message(0, NicknameManager.get_nickname(0), clean_message, position)
		return
	if is_server():
		if local_player_id > 0:
			_accept_chat_message(local_player_id, clean_message)
		return
	if is_client():
		var player := _get_player(local_player_id)
		if player == null or player.get("is_dead") == true:
			return
		request_chat_message.rpc_id(1, clean_message)

func _find_offline_chat_player() -> CharacterBody2D:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	for node in scene.find_children("*", "", true, false):
		if node is CharacterBody2D and node.has_method("get_network_state") and node.get("local_player") == true:
			return node as CharacterBody2D
	return null

func _sanitize_chat_message(message: String) -> String:
	var clean_message := message.replace("\r", " ").replace("\n", " ").strip_edges()
	return clean_message.substr(0, CHAT_MAX_MESSAGE_LENGTH).strip_edges()

func _accept_chat_message(peer_id: int, message: String) -> void:
	if peer_id <= 0:
		return
	var player := _get_player(peer_id)
	if player == null or player.get("is_dead") == true:
		return
	var now := Time.get_ticks_msec()
	var previous := int(last_chat_message_msec.get(peer_id, 0))
	if previous != 0 and now - previous < CHAT_RATE_LIMIT_MSEC:
		return
	last_chat_message_msec[peer_id] = now
	var clean_message := _sanitize_chat_message(message)
	if clean_message.is_empty():
		return
	var nickname := str(NicknameManager.get_nickname(peer_id))
	if nickname.is_empty():
		nickname = "player"
	var sender_position := player.global_position
	_dispatch_chat_message(peer_id, nickname, clean_message, sender_position)
	receive_chat_message.rpc(peer_id, nickname, clean_message, sender_position)

func _dispatch_chat_message(sender_id: int, nickname: String, message: String, sender_position: Vector2) -> void:
	chat_message_received.emit(sender_id, nickname, message, sender_position)

@rpc("any_peer", "call_remote", "reliable", 8)
func request_chat_message(message: String) -> void:
	if not is_server():
		return
	_accept_chat_message(multiplayer.get_remote_sender_id(), message)

@rpc("authority", "call_remote", "reliable", 8)
func receive_chat_message(sender_id: int, nickname: String, message: String, sender_position: Vector2) -> void:
	if is_server():
		return
	_dispatch_chat_message(sender_id, nickname, _sanitize_chat_message(message), sender_position)

@rpc("any_peer", "call_remote", "reliable", 0)
func server_message_rpc(message: Dictionary):
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id > 0:
		server_message.emit(peer_id, message)

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func player_state_rpc(state: Dictionary):
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id <= 0:
		return
	var now := Time.get_ticks_usec()
	var previous := int(last_player_state_time.get(peer_id, 0))
	if previous != 0 and now - previous < PLAYER_STATE_MIN_INTERVAL_USEC:
		return
	last_player_state_time[peer_id] = now
	server_player_state.emit(peer_id, state)

func _create_round_manager():
	if round_manager != null and is_instance_valid(round_manager):
		return
	var script: Script = load("res://scripts/rounds/round_manager.gd")
	if script == null:
		return
	round_manager = Node.new()
	round_manager.name = "RoundManager"
	round_manager.set_script(script)
	add_child(round_manager)

func _ensure_host_player():
	if not is_server() or Args.headless:
		return
	if round_manager == null or not round_manager.has_method("should_have_player"):
		return
	if not round_manager.should_have_player(1):
		return
	if _get_player(1) == null:
		_adopt_or_spawn_player(1, true, _get_spawn_position(1))


func _prepare_scene():
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var scene_changed: bool = scene != prepared_scene
	if scene_changed:
		prepared_scene = scene
		round_scene_synced = false
	var map_manager := scene.get_node_or_null("MapManager")
	var map_loaded := false
	if is_server() and map_manager != null and map_manager.has_method("initialize_for_server"):
		if map_manager.get("initialized") != true:
			map_loaded = map_manager.call("initialize_for_server") == true
	if scene_changed and not map_loaded:
		if is_server():
			_register_items()
		else:
			_clear_client_item_registry()
	if is_server() and map_manager != null and round_manager != null and round_manager.get("started") != true and round_manager.has_method("start_host_rounds"):
		round_manager.call("start_host_rounds")
	if is_server():
		_ensure_host_player()
	elif is_client() and local_player_id > 0 and cached_round_state_valid and not round_scene_synced:
		sync_round_entities(cached_round_active, cached_round_waiting, cached_round_positions, cached_round_number)
	elif is_client() and local_player_id > 0 and round_manager != null and round_manager.has_method("should_have_player") and round_manager.get("started") == true:
		if round_manager.should_have_player(local_player_id):
			_remove_local_ghost()
		else:
			_destroy_player(local_player_id)
			_ensure_local_ghost()

func get_map_manager() -> Node:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("MapManager")

func on_map_loaded():
	spawn_claims.clear()
	if is_server():
		_register_items()
	else:
		_clear_client_item_registry()

func _clear_client_item_registry():
	items.clear()
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	for node: Node in scene.find_children("*", "", true, false):
		if node is RigidBody2D and node.has_meta("network_item_id"):
			node.remove_meta("network_item_id")

func _allocate_network_item_id() -> int:
	var item_id := next_network_item_id
	next_network_item_id += 1
	return item_id

func move_players_to_map_spawns(peer_ids: Array[int]) -> Dictionary:
	if not is_server():
		return {}
	spawn_claims.clear()
	var positions: Dictionary = {}
	for peer_id in peer_ids:
		var id := int(peer_id)
		var player := _get_player(id)
		if player == null:
			continue
		var spawn_position := _get_spawn_position(id)
		player.global_position = spawn_position
		player.velocity = Vector2.ZERO
		player.set("network_position", spawn_position)
		player.set("network_velocity", Vector2.ZERO)
		player.rotation = 0.0
		positions[id] = spawn_position
	return positions


func _destroy_player(peer_id: int):
	var player := _get_player(peer_id)
	if player == null:
		return
	GC.destroy(player)
	players.erase(peer_id)

func get_player(peer_id: int) -> CharacterBody2D:
	return _get_player(peer_id)

func get_connected_peer_ids() -> Array[int]:
	var result: Array[int] = []
	if is_server() and not Args.headless:
		result.append(1)
	if is_server():
		for peer_id in multiplayer.get_peers():
			if registered_peers.has(int(peer_id)):
				result.append(int(peer_id))
	return result

func begin_round_entities(peer_ids: Array[int], roles: Dictionary):
	if not is_server():
		return
	_cleanup_ghosts()
	spawn_claims.clear()
	for peer_id in players.keys().duplicate():
		if not peer_ids.has(int(peer_id)):
			_destroy_player(int(peer_id))
	for peer_id in peer_ids:
		var id := int(peer_id)
		var spawn_position := _get_spawn_position(id)
		var player := _get_player(id)
		if player == null:
			player = _adopt_or_spawn_player(id, id == 1 and not Args.headless, spawn_position)
		else:
			if player.has_method("drop_all_items"):
				player.call("drop_all_items")
			player.global_position = spawn_position
			player.velocity = Vector2.ZERO
			if player.has_method("reset_for_round"):
				player.call("reset_for_round")
			if player.has_method("set_local_player"):
				player.call("set_local_player", id == 1 and not Args.headless)
		if player != null and player.has_method("set_round_role"):
			player.call("set_round_role", roles.get(id, ""))


func begin_waiting_entities(peer_ids: Array[int], positions: Dictionary = {}):
	if not is_server():
		return
	for peer_id in peer_ids:
		var id := int(peer_id)
		if _get_player(id) != null:
			continue
		var position: Vector2 = positions.get(id, _get_spawn_position(id))
		_adopt_or_spawn_player(id, id == 1 and not Args.headless, position)

func prepare_waiting_entities() -> Dictionary:
	if not is_server():
		return {"players": [], "positions": {}}
	var result: Array[int] = []
	var positions: Dictionary = {}
	for peer_id in players.keys().duplicate():
		var id := int(peer_id)
		var player := _get_player(id)
		if player == null:
			continue
		positions[id] = player.global_position
		var dead_value: Variant = player.get("is_dead")
		if dead_value is bool and not dead_value:
			result.append(id)
			continue
		_destroy_player(id)
	return {"players": result, "positions": positions}


func sync_round_entities(peer_ids: Array[int], waiting_ids: Array[int], positions: Dictionary, round_number: int = 0, force_positions: bool = false):
	if not is_client():
		return
	cached_round_active = peer_ids.duplicate()
	cached_round_waiting = waiting_ids.duplicate()
	cached_round_positions = positions.duplicate()
	cached_round_number = round_number
	cached_round_state_valid = true
	var scene: Node = get_tree().current_scene
	if scene == null or local_player_id <= 0:
		round_scene_synced = false
		return
	round_scene_synced = true
	var wanted: Dictionary = {}
	for peer_id in peer_ids:
		wanted[int(peer_id)] = true
	for peer_id in waiting_ids:
		wanted[int(peer_id)] = true
	for peer_id in players.keys().duplicate():
		if not wanted.has(int(peer_id)):
			_destroy_player(int(peer_id))
	var new_round: bool = round_number > 0 and round_number != last_client_round_number
	if round_number > 0:
		last_client_round_number = round_number
	for peer_id in wanted.keys():
		var id := int(peer_id)
		var player := _get_player(id)
		var created := player == null
		if created:
			var spawn_position: Vector2 = positions.get(id, Vector2.ZERO)
			player = _adopt_or_spawn_player(id, id == local_player_id, spawn_position)
		if player == null:
			continue
		var in_active: bool = peer_ids.has(id)
		if new_round and in_active and player.has_method("reset_for_round"):
			player.call("reset_for_round")
		if positions.has(id) and (created or force_positions or (new_round and in_active)):
			var authoritative_position: Vector2 = positions[id]
			player.global_position = authoritative_position
			player.set("network_position", authoritative_position)
		if player.has_method("set_local_player"):
			player.call("set_local_player", id == local_player_id)
		if in_active and player.has_method("set_network_spawn_ready"):
			player.call("set_network_spawn_ready", true)
	if peer_ids.has(local_player_id) or waiting_ids.has(local_player_id):
		_remove_local_ghost()
	else:
		_ensure_local_ghost(positions.get(local_player_id, Vector2.ZERO))

func _ensure_local_ghost(position: Vector2 = Vector2.ZERO):
	if local_player_id <= 0 or not is_client():
		return
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	if ghosts.has(local_player_id) and is_instance_valid(ghosts[local_player_id]):
		return
	for node: Node in scene.find_children("Ghost_*", "", true, false):
		if node is CharacterBody2D and int(node.get_meta("network_ghost_id", -1)) == local_player_id:
			ghosts[local_player_id] = node
			var camera := node.get_node_or_null("Camera2D") as Camera2D
			if camera != null:
				camera.enabled = true
			return
	var packed := load("res://prefabs/ghost.tscn") as PackedScene
	if packed == null:
		return
	var ghost := packed.instantiate() as CharacterBody2D
	if ghost == null:
		return
	ghost.name = "Ghost_%d" % local_player_id
	ghost.set_meta("network_ghost_id", local_player_id)
	ghost.global_position = position
	scene.add_child(ghost)
	var camera := ghost.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.enabled = true
	ghosts[local_player_id] = ghost

func _remove_local_ghost():
	if local_player_id <= 0:
		return
	var value: Variant = ghosts.get(local_player_id, null)
	if value != null and is_instance_valid(value):
		GC.destroy(value)
	ghosts.erase(local_player_id)
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	for node: Node in scene.find_children("*", "", true, false):
		if not node is CharacterBody2D:
			continue
		if int(node.get_meta("network_ghost_id", -1)) == local_player_id or node.name == "Ghost":
			GC.destroy(node)

func _cleanup_ghosts():
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	for node: Node in scene.find_children("*", "", true, false):
		if node is CharacterBody2D and (node.name == "Ghost" or node.name.begins_with("Ghost_")):
			GC.destroy(node)
	ghosts.clear()

func _adopt_or_spawn_player(peer_id: int, local: bool, position: Vector2) -> CharacterBody2D:
	var existing := _get_player(peer_id)
	if existing != null:
		if existing.has_method("set_local_player"):
			existing.call("set_local_player", local)
		return existing
	var scene: Node = get_tree().current_scene
	if scene == null:
		return null
	var packed := load("res://prefabs/player.tscn") as PackedScene
	if packed == null:
		return null
	var player := packed.instantiate() as CharacterBody2D
	if player == null:
		return null
	player.name = "%s%d" % [PLAYER_NAME_PREFIX, peer_id]
	if player.has_method("set_network_player_id"):
		player.call("set_network_player_id", peer_id)
	else:
		player.set("network_player_id", peer_id)
	if player.has_method("set_local_player"):
		player.call("set_local_player", local)
	else:
		player.set("local_player", local)
	player.set("network_position", position)
	player.set("network_velocity", Vector2.ZERO)
	player.global_position = position
	players[peer_id] = player
	scene.add_child(player)
	return player

func _get_player(peer_id: int) -> CharacterBody2D:
	var value: Variant = players.get(peer_id, null)
	if value == null or not is_instance_valid(value):
		players.erase(peer_id)
		return null
	var player := value as CharacterBody2D
	if player == null or player.is_queued_for_deletion():
		players.erase(peer_id)
		return null
	var owner_value: Variant = player.get("network_player_id")
	if owner_value is int and int(owner_value) != peer_id:
		players.erase(peer_id)
		return null
	for other_peer_id in players.keys():
		if int(other_peer_id) != peer_id and players.get(other_peer_id) == player:
			players.erase(peer_id)
			return null
	return player

func _register_items():
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	items.clear()
	var candidates: Array[Node] = []
	for node: Node in scene.find_children("*", "", true, false):
		if not node is RigidBody2D or node.is_queued_for_deletion():
			continue
		if node.has_method("get_network_state") or node.find_child("AmmoComponent", true, false) != null:
			candidates.append(node)
	candidates.sort_custom(func(a: Node, b: Node): return str(a.get_path()) < str(b.get_path()))
	for item_value in candidates:
		var item: Node = item_value
		var id := _allocate_network_item_id()
		items[id] = item
		item.set_meta("network_item_id", id)
		var scene_path := str(item.scene_file_path)
		if scene_path.is_empty():
			scene_path = str(item.get_meta("network_scene_path", ""))
		if not scene_path.is_empty():
			item.set_meta("network_scene_path", scene_path)
		item.set_meta("round_granted_item", item.get_meta("round_granted_item", false) == true)

func _get_spawn_position(peer_id: int) -> Vector2:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return Vector2.ZERO
	var map_manager := scene.get_node_or_null("MapManager")
	if map_manager != null:
		var spawns_node := map_manager.find_child("Spawns", true, false)
		if spawns_node != null:
			var spawns: Array[Node2D] = []
			for child: Node in spawns_node.get_children():
				if child is Node2D:
					spawns.append(child as Node2D)
			if not spawns.is_empty():
				var free_spawns: Array[Node2D] = []
				for spawn: Node2D in spawns:
					if not spawn_claims.values().has(spawn.get_path()):
						free_spawns.append(spawn)
				if not free_spawns.is_empty():
					var spawn: Node2D = free_spawns.pick_random()
					spawn_claims[peer_id] = spawn.get_path()
					return spawn.global_position
				var fallback_spawn: Node2D = spawns.pick_random()
				var angle := float(peer_id) * 2.399963229728653
				var radius := 44.0 + 12.0 * float(peer_id % 3)
				return fallback_spawn.global_position + Vector2(cos(angle), sin(angle)) * radius
	return Vector2.ZERO

func broadcast_player_states():
	if not is_server():
		return
	for peer_id in players.keys().duplicate():
		var player := _get_player(int(peer_id))
		if player == null or not player.has_method("get_network_state"):
			continue
		var state_value: Variant = player.call("get_network_state")
		if not state_value is Dictionary:
			continue
		var state: Dictionary = state_value
		var id := int(peer_id)
		var sequence := int(last_player_sequence.get(id, 0)) + 1
		last_player_sequence[id] = sequence
		state["id"] = id
		state["sequence"] = sequence
		receive_player_state.rpc(state)

func broadcast_item_states():
	if not is_server():
		return
	var invalid: Array[int] = []
	for item_id in items.keys():
		var id := int(item_id)
		var item := _get_item(id)
		if item == null:
			invalid.append(id)
			continue
		var state := _build_item_state(id, item)
		if not state.is_empty():
			receive_item_state.rpc(state)
	for id: int in invalid:
		item_destroyed.rpc(id)
		items.erase(id)


func spawn_item_in_slot(peer_id: int, slot_index: int, scene_path: String) -> bool:
	if not is_server() or slot_index < 0 or slot_index > 1:
		return false
	var normalized_path := scene_path.strip_edges()
	if not normalized_path.begins_with("res://") or normalized_path.contains("..") or not ResourceLoader.exists(normalized_path):
		return false
	var player := _get_player(peer_id)
	if player == null:
		return false
	var pockets := player.get_node_or_null("Pockets")
	if pockets == null or not pockets.has_method("get_slot"):
		return false
	var slot := pockets.call("get_slot", slot_index) as Marker2D
	if slot == null:
		return false
	var slot_values: Variant = pockets.get("slots")
	if slot_values is Array and slot_index < slot_values.size():
		var current_item: Variant = slot_values[slot_index]
		if current_item != null and is_instance_valid(current_item):
			return false
	var packed := ResourceLoader.load(normalized_path) as PackedScene
	if packed == null:
		return false
	var item := packed.instantiate() as RigidBody2D
	if item == null or not item.has_method("place_in_pocket"):
		if item != null:
			item.free()
		return false
	var scene: Node = get_tree().current_scene
	if scene == null:
		item.free()
		return false
	var item_id := _allocate_network_item_id()
	item.set_meta("network_item_id", item_id)
	item.set_meta("network_scene_path", normalized_path)
	item.set_meta("round_granted_item", true)
	scene.add_child(item)
	if item.call("place_in_pocket", slot, player) != true:
		GC.destroy(item)
		return false
	items[item_id] = item
	var state := _build_item_state(item_id, item)
	if not state.is_empty():
		receive_initial_item_state.rpc(state)
	return true

func clear_round_items():
	if not is_server():
		return
	for item_id_value in items.keys().duplicate():
		var item_id := int(item_id_value)
		var item := _get_item(item_id)
		if item == null or item.get_meta("round_granted_item", false) != true:
			continue
		var holder_value: Variant = item.get("holder_player")
		if holder_value is CharacterBody2D and is_instance_valid(holder_value) and holder_value.has_method("clear_item_reference"):
			holder_value.call("clear_item_reference", item)
		var current: Node = item.get_parent()
		while current != null:
			if current.name == "Pockets" and current.has_method("clear_network_item"):
				current.call("clear_network_item", item)
			current = current.get_parent()
		item_destroyed.rpc(item_id)
		items.erase(item_id)
		GC.destroy(item)

func _ensure_item_from_state(state: Dictionary) -> Node:
	var item_id := int(state.get("id", 0))
	if item_id <= 0:
		return null
	var scene_path := str(state.get("scene_path", ""))
	var existing := _get_item(item_id)
	if existing == null:
		existing = _find_unregistered_scene_item(state, scene_path, item_id)
		if existing != null:
			items[item_id] = existing
			existing.set_meta("network_item_id", item_id)
			if not scene_path.is_empty():
				existing.set_meta("network_scene_path", scene_path)
			var reference_key := str(state.get("map_reference_key", ""))
			if not reference_key.is_empty():
				existing.set_meta("map_reference_key", reference_key)
			existing.set_meta("round_granted_item", state.get("round_granted_item", false) == true)
	if existing != null:
		var existing_path := str(existing.get_meta("network_scene_path", existing.scene_file_path))
		var existing_granted: bool = existing.get_meta("round_granted_item", false) == true
		var incoming_granted: bool = state.get("round_granted_item", false) == true
		var existing_reference_key := str(existing.get_meta("map_reference_key", ""))
		var incoming_reference_key := str(state.get("map_reference_key", ""))
		if scene_path.is_empty() or existing_path == scene_path and existing_granted == incoming_granted and existing_reference_key == incoming_reference_key:
			return existing
		var holder_value: Variant = existing.get("holder_player")
		if holder_value is Node and is_instance_valid(holder_value) and holder_value.has_method("clear_item_reference"):
			holder_value.call("clear_item_reference", existing)
		var current: Node = existing.get_parent()
		while current != null:
			if current.name == "Pockets" and current.has_method("clear_network_item"):
				current.call("clear_network_item", existing)
			current = current.get_parent()
		items.erase(item_id)
		GC.destroy(existing)
	if not scene_path.begins_with("res://") or scene_path.contains("..") or not ResourceLoader.exists(scene_path):
		return null
	var packed := ResourceLoader.load(scene_path) as PackedScene
	if packed == null:
		return null
	var item := packed.instantiate() as RigidBody2D
	var scene: Node = get_tree().current_scene
	if item == null or scene == null:
		if item != null:
			item.free()
		return null
	item.set_meta("network_item_id", item_id)
	item.set_meta("network_scene_path", scene_path)
	var reference_key := str(state.get("map_reference_key", ""))
	if not reference_key.is_empty():
		item.set_meta("map_reference_key", reference_key)
	item.set_meta("round_granted_item", state.get("round_granted_item", false) == true)
	scene.add_child(item)
	items[item_id] = item
	return item

func _find_unregistered_scene_item(state: Dictionary, scene_path: String, item_id: int) -> Node:
	if scene_path.is_empty():
		return null
	var scene: Node = get_tree().current_scene
	if scene == null:
		return null
	var position_value: Variant = state.get("position", Vector2.ZERO)
	var target_position: Vector2 = position_value if position_value is Vector2 else Vector2.ZERO
	var target_reference_key := str(state.get("map_reference_key", ""))
	var target_granted: bool = state.get("round_granted_item", false) == true
	var best_item: Node = null
	var best_distance := INF
	for candidate: Node in scene.find_children("*", "", true, false):
		if not candidate is RigidBody2D or candidate.is_queued_for_deletion():
			continue
		var registered_id := int(candidate.get_meta("network_item_id", 0))
		var registered_item: Variant = items.get(registered_id, null) if registered_id > 0 else null
		if registered_item == candidate and is_instance_valid(candidate):
			continue
		var candidate_path := str(candidate.get_meta("network_scene_path", candidate.scene_file_path))
		if candidate_path != scene_path:
			continue
		if str(candidate.get_meta("map_reference_key", "")) != target_reference_key:
			continue
		if (candidate.get_meta("round_granted_item", false) == true) != target_granted:
			continue
		var distance := (candidate as Node2D).global_position.distance_squared_to(target_position)
		if distance < best_distance:
			best_distance = distance
			best_item = candidate
	return best_item

func _get_item(item_id: int) -> Node:
	var value: Variant = items.get(item_id, null)
	if value == null or not is_instance_valid(value):
		items.erase(item_id)
		return null
	var item := value as Node
	if item == null or item.is_queued_for_deletion():
		items.erase(item_id)
		return null
	return item

func _build_item_state(item_id: int, item: Node) -> Dictionary:
	if item == null or not is_instance_valid(item):
		return {}
	if item.has_method("get_network_state"):
		var value: Variant = item.call("get_network_state")
		if value is Dictionary:
			var state: Dictionary = value.duplicate(true)
			var scene_path := str(item.get_meta("network_scene_path", item.scene_file_path))
			if not scene_path.is_empty():
				state["scene_path"] = scene_path
			state["round_granted_item"] = item.get_meta("round_granted_item", false) == true
			var reference_key := str(item.get_meta("map_reference_key", ""))
			if not reference_key.is_empty():
				state["map_reference_key"] = reference_key
			return state
	var ammo := item.find_child("AmmoComponent", true, false)
	if ammo == null:
		return {}
	var state := {"id": item_id, "alive": true, "position": item.global_position, "rotation": item.global_rotation, "visible": item.visible, "ammo_amount": int(ammo.get("ammo_amount"))}
	var scene_path := str(item.get_meta("network_scene_path", item.scene_file_path))
	if not scene_path.is_empty():
		state["scene_path"] = scene_path
	state["round_granted_item"] = item.get_meta("round_granted_item", false) == true
	var reference_key := str(item.get_meta("map_reference_key", ""))
	if not reference_key.is_empty():
		state["map_reference_key"] = reference_key
	return state

@rpc("authority", "call_remote", "reliable", 2)
func receive_initial_player_state(state: Dictionary):
	if multiplayer.is_server():
		return
	_receive_player_state_data(state)

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func receive_player_state(state: Dictionary):
	if multiplayer.is_server():
		return
	_receive_player_state_data(state)

func _receive_player_state_data(state: Dictionary):
	var peer_id := int(state.get("id", 0))
	if peer_id <= 0:
		return
	if local_player_id <= 0 or round_manager == null or not is_instance_valid(round_manager) or round_manager.get("started") != true:
		_cache_pending_player_state(peer_id, state)
		return
	if not round_manager.should_have_player(peer_id):
		pending_player_states.erase(peer_id)
		return
	_apply_received_player_state(peer_id, state)

func _cache_pending_player_state(peer_id: int, state: Dictionary):
	var old_value: Variant = pending_player_states.get(peer_id, null)
	if old_value is Dictionary and int(old_value.get("sequence", -1)) > int(state.get("sequence", -1)):
		return
	pending_player_states[peer_id] = state.duplicate(true)

func _apply_received_player_state(peer_id: int, state: Dictionary):
	var player := _get_player(peer_id)
	if player == null:
		var position_value: Variant = state.get("position", Vector2.ZERO)
		var spawn_position := Vector2.ZERO
		if position_value is Vector2 and position_value.is_finite():
			spawn_position = position_value
		player = _adopt_or_spawn_player(peer_id, peer_id == local_player_id, spawn_position)
	if player == null:
		return
	if player.has_method("set_local_player"):
		player.call("set_local_player", peer_id == local_player_id)
	if player.has_method("apply_network_state"):
		player.call("apply_network_state", state)
	pending_player_states.erase(peer_id)

func flush_pending_player_states():
	_flush_pending_player_states()

func _flush_pending_player_states():
	if not is_client() or local_player_id <= 0 or round_manager == null or not is_instance_valid(round_manager) or round_manager.get("started") != true:
		return
	for peer_id_value in pending_player_states.keys().duplicate():
		var peer_id := int(peer_id_value)
		if not round_manager.should_have_player(peer_id):
			pending_player_states.erase(peer_id)
			continue
		var state_value: Variant = pending_player_states.get(peer_id, null)
		if state_value is Dictionary:
			_apply_received_player_state(peer_id, state_value)
		else:
			pending_player_states.erase(peer_id)

@rpc("authority", "call_remote", "reliable", 2)
func receive_initial_item_state(state: Dictionary):
	if multiplayer.is_server():
		return
	var item_id := int(state.get("id", 0))
	if item_id <= 0:
		return
	var item := _ensure_item_from_state(state)
	if item == null:
		return
	if item.has_method("apply_network_state"):
		item.call("apply_network_state", state, players)
		return
	var ammo := item.find_child("AmmoComponent", true, false)
	if ammo != null and state.has("ammo_amount"):
		ammo.set("ammo_amount", int(state["ammo_amount"]))
	item.global_position = state.get("position", item.global_position)
	item.global_rotation = float(state.get("rotation", item.global_rotation))
	item.visible = state.get("visible", item.visible)
	item.freeze = true

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func receive_item_state(state: Dictionary):
	if multiplayer.is_server():
		return
	var item_id := int(state.get("id", 0))
	if item_id <= 0:
		return
	var item := _ensure_item_from_state(state)
	if item == null:
		return
	if item.has_method("apply_network_state"):
		item.call("apply_network_state", state, players)
		return
	var ammo := item.find_child("AmmoComponent", true, false)
	if ammo != null and state.has("ammo_amount"):
		ammo.set("ammo_amount", int(state["ammo_amount"]))
	item.global_position = state.get("position", item.global_position)
	item.global_rotation = float(state.get("rotation", item.global_rotation))
	item.visible = state.get("visible", item.visible)
	item.freeze = true

func send_correction(peer_id: int, position: Vector2, velocity: Vector2):
	if not is_server() or peer_id <= 0:
		return
	var now := Time.get_ticks_usec()
	var previous := int(last_correction_time.get(peer_id, 0))
	if previous != 0 and now - previous < 100000:
		return
	last_correction_time[peer_id] = now
	receive_correction.rpc_id(peer_id, position, velocity)

@rpc("authority", "call_remote", "reliable", 4)
func receive_correction(position: Vector2, velocity: Vector2):
	if multiplayer.is_server():
		return
	var player := _get_player(local_player_id)
	if player != null and player.has_method("apply_local_network_correction"):
		player.call("apply_local_network_correction", position, velocity)

func register_bullet(bullet: Node) -> int:
	if not is_server() or bullet == null or not is_instance_valid(bullet):
		return 0
	last_bullet_id += 1
	var direction := Vector2.RIGHT
	var value: Variant = bullet.get("direction")
	if value is Vector2 and value.length_squared() > 0.000001:
		direction = value.normalized()
	bullet.set_meta("network_bullet_id", last_bullet_id)
	spawn_bullet.rpc(last_bullet_id, bullet.global_position, direction)
	return last_bullet_id

@rpc("authority", "call_remote", "reliable", 5)
func spawn_bullet(bullet_id: int, position: Vector2, direction: Vector2):
	if multiplayer.is_server():
		return
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var packed := load("res://prefabs/weapons/bullet.tscn") as PackedScene
	if packed == null:
		return
	var bullet := packed.instantiate() as Node
	if bullet == null:
		return
	bullet.set_meta("network_bullet_id", bullet_id)
	scene.add_child(bullet)
	if bullet.has_method("set_network_visual"):
		bullet.call("set_network_visual", bullet_id, position, direction)

func finish_bullet(bullet_id: int):
	if is_server() and bullet_id > 0:
		bullet_destroyed.rpc(bullet_id)

@rpc("authority", "call_remote", "reliable", 5)
func bullet_destroyed(bullet_id: int):
	if multiplayer.is_server():
		return
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	for node: Node in scene.find_children("*", "", true, false):
		if int(node.get_meta("network_bullet_id", 0)) == bullet_id:
			GC.destroy(node)
			return

func broadcast_hit(player: Node, region: int, hit_position: Vector2, radius: float, penetration: float, hit_direction: Vector2 = Vector2.ZERO):
	if not is_server() or player == null or not is_instance_valid(player):
		return
	var peer_id := int(player.get("network_player_id"))
	if peer_id > 0:
		receive_hit.rpc(peer_id, region, hit_position, radius, penetration, hit_direction)

@rpc("authority", "call_remote", "reliable", 6)
func receive_hit(peer_id: int, region: int, hit_position: Vector2, radius: float, penetration: float, hit_direction: Vector2 = Vector2.ZERO):
	if multiplayer.is_server():
		return
	var player := _get_player(peer_id)
	if player == null:
		return
	var violence := player.get_node_or_null("UltraViolence")
	if violence != null and violence.has_method("apply_network_hit"):
		violence.call("apply_network_hit", region, hit_position, radius, penetration, hit_direction)

func broadcast_sharp_hit(player: Node, region: int, hit_position: Vector2, radius: float, sharpness: float, impact_speed: float, impact_direction: Vector2 = Vector2.ZERO):
	if not is_server() or player == null or not is_instance_valid(player):
		return
	var peer_id := int(player.get("network_player_id"))
	if peer_id > 0:
		receive_sharp_hit.rpc(peer_id, region, hit_position, radius, sharpness, impact_speed, impact_direction)

@rpc("authority", "call_remote", "reliable", 6)
func receive_sharp_hit(peer_id: int, region: int, hit_position: Vector2, radius: float, sharpness: float, impact_speed: float, impact_direction: Vector2 = Vector2.ZERO):
	if multiplayer.is_server():
		return
	var player := _get_player(peer_id)
	if player == null:
		return
	var violence := player.get_node_or_null("UltraViolence")
	if violence != null and violence.has_method("apply_network_sharp_hit"):
		violence.call("apply_network_sharp_hit", region, hit_position, radius, sharpness, impact_speed, impact_direction)

func broadcast_gunshot(item_id: int, shot_direction: Vector2):
	if not is_server() or item_id <= 0 or shot_direction.length_squared() < 0.001:
		return
	gunshot_fired.rpc(item_id, shot_direction.normalized())

@rpc("authority", "call_remote", "unreliable", 5)
func gunshot_fired(item_id: int, shot_direction: Vector2):
	if multiplayer.is_server():
		return
	var item := _get_item(item_id)
	if item == null:
		return
	var gun := item.find_child("GunComponent", true, false)
	if gun != null and gun.has_method("play_remote_shot"):
		gun.call("play_remote_shot", shot_direction)

@rpc("authority", "call_remote", "reliable", 7)
func item_destroyed(item_id: int):
	if multiplayer.is_server():
		return
	var item := _get_item(item_id)
	if item != null:
		GC.destroy(item)
	items.erase(item_id)

func _on_peer_disconnected(peer_id: int):
	var was_registered := registered_peers.has(peer_id)
	registered_peers.erase(peer_id)
	var player := _get_player(peer_id)
	if player != null:
		if player.has_method("drop_all_items"):
			player.call("drop_all_items")
		GC.destroy(player)
	players.erase(peer_id)
	spawn_claims.erase(peer_id)
	last_player_state_time.erase(peer_id)
	last_player_sequence.erase(peer_id)
	pending_player_states.erase(peer_id)
	last_correction_time.erase(peer_id)
	if was_registered and round_manager != null and round_manager.has_method("player_left"):
		round_manager.player_left(peer_id)

func _on_connected_to_server():
	local_player_id = multiplayer.get_unique_id()
	if is_client():
		if server_probe_active:
			request_server_info_probe.rpc_id(1)
		else:
			request_server_info.rpc_id(1)
	if server_probe_active:
		return
	if cached_round_state_valid:
		sync_round_entities(cached_round_active, cached_round_waiting, cached_round_positions, cached_round_number)
	_flush_pending_player_states()

func _on_connection_failed():
	if server_probe_active:
		_finish_server_probe(false)
		return
	rep.warn("Connection failed")
	_schedule_disconnect_cleanup()

func _on_server_disconnected():
	if server_probe_active:
		_finish_server_probe(false)
		return
	if not network_active:
		return
	rep.info("Disconnected from host")
	_schedule_disconnect_cleanup()

func _schedule_disconnect_cleanup():
	if disconnect_cleanup_scheduled:
		return
	disconnect_cleanup_scheduled = true
	network_active = false
	call_deferred("_finish_disconnect_cleanup")

func _finish_disconnect_cleanup():
	disconnect_cleanup_scheduled = false
	var current_scene := get_tree().current_scene
	var return_to_menu := current_scene != null and current_scene.scene_file_path == "res://scenes/game.tscn"
	disconnect_network()
	if return_to_menu:
		get_tree().call_deferred("change_scene_to_file", "res://scenes/menu.tscn")

func _get_host_ip() -> String:
	var addresses := IP.get_local_addresses()
	for address in addresses:
		if _is_lan_ipv4(address, 192, 168):
			return address
	for address in addresses:
		if _is_lan_ipv4(address, 10, -1):
			return address
	for address in addresses:
		if address != "127.0.0.1" and address != "::1" and not address.begins_with("172."):
			return address
	return "127.0.0.1"

func _is_lan_ipv4(address: String, first: int, second: int) -> bool:
	var parts := address.split(".")
	if parts.size() != 4:
		return false
	for part in parts:
		if not part.is_valid_int():
			return false
	var a := int(parts[0])
	var b := int(parts[1])
	return a == first and (second < 0 or b == second)
