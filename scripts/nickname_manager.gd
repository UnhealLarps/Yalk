extends Node

const DEFAULT_NICKNAME := "player"
const MAX_NICKNAME_LENGTH := 24
const NICKNAME_PATH := "user://nickname.txt"

var nicknames: Dictionary = {}
var own_name_request_sent := false
var local_nickname := DEFAULT_NICKNAME

func _ready() -> void:
	_load_local_nickname()

func _load_local_nickname() -> void:
	if FileAccess.file_exists(NICKNAME_PATH):
		var file := FileAccess.open(NICKNAME_PATH, FileAccess.READ)
		if file != null:
			local_nickname = file.get_as_text().strip_edges().substr(0, MAX_NICKNAME_LENGTH)
			file.close()
	if local_nickname.is_empty():
		local_nickname = DEFAULT_NICKNAME
	if not FileAccess.file_exists(NICKNAME_PATH):
		var file := FileAccess.open(NICKNAME_PATH, FileAccess.WRITE)
		if file != null:
			file.store_string(local_nickname)
			file.close()

func _process(_delta: float):
	var network_manager: Node = get_node_or_null("/root/NetworkManager")
	if network_manager == null or network_manager.call("is_networked") != true:
		own_name_request_sent = false
		return
	if network_manager.call("is_server") == true:
		if not Args.headless and not nicknames.has(1):
			_assign_nickname(1, local_nickname)
		return
	if network_manager.call("is_client") == true and not own_name_request_sent:
		var peer: MultiplayerPeer = multiplayer.multiplayer_peer
		if peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			request_nickname.rpc_id(1, local_nickname)
			own_name_request_sent = true

func get_nickname(peer_id: int) -> String:
	if nicknames.has(peer_id):
		return str(nicknames[peer_id])
	var network_manager: Node = get_node_or_null("/root/NetworkManager")
	if network_manager == null or network_manager.call("is_networked") != true:
		return local_nickname
	if network_manager.call("is_server") == true and peer_id == 1 and not Args.headless:
		return local_nickname
	if network_manager.call("is_client") == true and peer_id == int(network_manager.get("local_player_id")):
		return local_nickname
	return DEFAULT_NICKNAME

func apply_to_player(player: Node, peer_id: int):
	if player == null or not is_instance_valid(player):
		return
	var nickname := get_nickname(peer_id)
	var network_manager: Node = get_node_or_null("/root/NetworkManager")
	if network_manager == null or network_manager.call("is_networked") != true or peer_id <= 0:
		nickname = local_nickname
	if player.has_method("set_nickname"):
		player.call("set_nickname", nickname)

@rpc("any_peer", "call_remote", "reliable")
func request_nickname(requested_name: String):
	var network_manager: Node = get_node_or_null("/root/NetworkManager")
	if network_manager == null or network_manager.call("is_server") != true:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id <= 1:
		return
	for existing_id_value in nicknames.keys():
		var existing_id := int(existing_id_value)
		if existing_id == peer_id:
			continue
		nickname_assigned.rpc_id(peer_id, existing_id, str(nicknames[existing_id]))
	_assign_nickname(peer_id, requested_name)

func _assign_nickname(peer_id: int, requested_name: String):
	if peer_id <= 0:
		return
	var nickname := _make_unique_nickname(requested_name, peer_id)
	nicknames[peer_id] = nickname
	_apply_to_peer(peer_id)
	nickname_assigned.rpc(peer_id, nickname)

func _make_unique_nickname(requested_name: String, peer_id: int) -> String:
	var base := requested_name.strip_edges().substr(0, MAX_NICKNAME_LENGTH)
	if base.is_empty():
		base = DEFAULT_NICKNAME
	var suffix := 2
	var candidate := base
	while _nickname_taken(candidate, peer_id):
		var tail := str(suffix)
		candidate = base.substr(0, MAX_NICKNAME_LENGTH - tail.length()) + tail
		suffix += 1
	return candidate

func _nickname_taken(candidate: String, excluded_peer_id: int) -> bool:
	for peer_id_value in nicknames.keys():
		var peer_id := int(peer_id_value)
		if peer_id == excluded_peer_id:
			continue
		if str(nicknames[peer_id]).to_lower() == candidate.to_lower():
			return true
	return false

func _apply_to_peer(peer_id: int):
	var network_manager: Node = get_node_or_null("/root/NetworkManager")
	if network_manager == null or not network_manager.has_method("get_player"):
		return
	var player: Node = network_manager.call("get_player", peer_id)
	if player != null:
		apply_to_player(player, peer_id)

func remove_player(peer_id: int):
	var network_manager: Node = get_node_or_null("/root/NetworkManager")
	if network_manager == null or network_manager.call("is_server") != true or not nicknames.has(peer_id):
		return
	nicknames.erase(peer_id)
	nickname_removed.rpc(peer_id)

@rpc("authority", "call_remote", "reliable")
func nickname_assigned(peer_id: int, nickname: String):
	var network_manager: Node = get_node_or_null("/root/NetworkManager")
	if network_manager != null and network_manager.call("is_server") == true:
		return
	nicknames[peer_id] = nickname
	_apply_to_peer(peer_id)

@rpc("authority", "call_remote", "reliable")
func nickname_removed(peer_id: int):
	var network_manager: Node = get_node_or_null("/root/NetworkManager")
	if network_manager != null and network_manager.call("is_server") == true:
		return
	nicknames.erase(peer_id)
