extends Node

enum AccessLevel { ALL, HOST }

const ACCESS_ALL := AccessLevel.ALL
const ACCESS_HOST := AccessLevel.HOST

var commands: Dictionary = {}

func _ready() -> void:
	register_command("help", "Lists available commands", "/help", ACCESS_ALL, Callable(self, "_command_help"))
	register_command("players", "Lists connected players and their IDs", "/players", ACCESS_ALL, Callable(self, "_command_players"))
	register_command("ban", "Bans a player by cryptographic identity", "/ban <id> <reason>", ACCESS_HOST, Callable(self, "_command_ban"))
	register_command("unban", "Removes a ban by fingerprint or unique prefix", "/unban <fingerprint>", ACCESS_HOST, Callable(self, "_command_unban"))
	register_command("kick", "Disconnects a player from the server", "/kick <id> <reason>", ACCESS_HOST, Callable(self, "_command_kick"))

func register_command(command_name: String, description: String, usage: String, access: int, callback: Callable) -> bool:
	var normalized := command_name.strip_edges().to_lower()
	if normalized.is_empty() or normalized.contains(" ") or not callback.is_valid() or access not in [ACCESS_ALL, ACCESS_HOST]:
		return false
	commands[normalized] = {
		"description": description,
		"usage": usage,
		"access": access,
		"callback": callback
	}
	return true

func process_command(sender_id: int, message: String) -> void:
	if NetworkManager.is_networked() and not NetworkManager.is_server():
		return
	var source := message.strip_edges()
	if not source.begins_with("/"):
		return
	var arguments := _tokenize(source.substr(1))
	if arguments.is_empty():
		_send_output(sender_id, "Empty command. Use /help")
		return
	var command_name: String = str(arguments.pop_front()).to_lower()
	if not commands.has(command_name):
		_send_output(sender_id, "Unknown command: /%s. Use /help" % command_name)
		return
	var command: Dictionary = commands[command_name]
	if int(command.get("access", ACCESS_ALL)) == ACCESS_HOST and not _is_host_sender(sender_id):
		_send_output(sender_id, "Permission denied: this command is host-only")
		return
	var callback: Callable = command.get("callback", Callable())
	if callback.is_valid():
		callback.call(sender_id, arguments)

func _is_host_sender(sender_id: int) -> bool:
	return NetworkManager.is_server() and sender_id == 1

func _tokenize(source: String) -> Array[String]:
	var result: Array[String] = []
	var token := ""
	var quoted := false
	for i in range(source.length()):
		var character := source.substr(i, 1)
		if character == "\"":
			quoted = not quoted
		elif (character == " " or character == "\t") and not quoted:
			if not token.is_empty():
				result.append(token)
				token = ""
		else:
			token += character
	if not token.is_empty():
		result.append(token)
	return result

func _command_help(sender_id: int, _arguments: Array[String]) -> void:
	var names: Array[String] = []
	for command_name in commands.keys():
		names.append(str(command_name))
	names.sort()
	var lines := PackedStringArray(["Commands:"])
	for command_name in names:
		var command: Dictionary = commands[command_name]
		var access_label := "(host only)" if int(command.get("access", ACCESS_ALL)) == ACCESS_HOST else "[everyone]"
		lines.append("%s — %s %s" % [str(command.get("usage", "/" + command_name)), str(command.get("description", "")), access_label])
	_send_output(sender_id, "\n".join(lines))

func _command_players(sender_id: int, _arguments: Array[String]) -> void:
	if not NetworkManager.is_networked():
		var offline_player := NetworkManager._find_offline_chat_player()
		if offline_player == null:
			_send_output(sender_id, "No players")
		else:
			_send_output(sender_id, "ID 0 — %s (local player)" % NicknameManager.get_nickname(0))
		return
	var peer_ids := NetworkManager.get_connected_peer_ids()
	if peer_ids.is_empty():
		_send_output(sender_id, "No connected players")
		return
	peer_ids.sort()
	var lines := PackedStringArray(["Players:"])
	for peer_id in peer_ids:
		var nickname := str(NicknameManager.get_nickname(peer_id))
		var player := NetworkManager.get_player(peer_id)
		var state := "in game" if player != null else "waiting for round"
		lines.append("ID %d — %s (%s)" % [peer_id, nickname, state])
	_send_output(sender_id, "\n".join(lines))

func _command_ban(sender_id: int, arguments: Array[String]) -> void:
	if arguments.is_empty() or not arguments[0].is_valid_int():
		_send_output(sender_id, "Usage: /ban <id> <reason>")
		return
	var peer_id := int(arguments[0])
	if not _is_valid_remote_target(peer_id):
		_send_output(sender_id, "Player ID not found or target is the host")
		return
	var fingerprint := NetworkManager.get_peer_fingerprint(peer_id)
	if fingerprint.is_empty():
		_send_output(sender_id, "Player has no verified cryptographic identity")
		return
	var reason := _join_arguments(arguments, 1)
	if reason.is_empty():
		reason = "Banned by host"
	var nickname := str(NicknameManager.get_nickname(peer_id))
	if not NetworkManager.identity.add_ban(fingerprint, nickname, reason):
		_send_output(sender_id, "Failed to save ban to user://banlist.json")
		return
	NetworkManager.kick_player(peer_id, "You are banned: " + reason)
	_send_output(sender_id, "Player %s (ID %d) banned. Fingerprint: %s" % [nickname, peer_id, fingerprint])

func _command_unban(sender_id: int, arguments: Array[String]) -> void:
	if arguments.is_empty():
		_send_output(sender_id, "Usage: /unban <fingerprint>")
		return
	var result: Dictionary = NetworkManager.identity.remove_ban(arguments[0])
	if result.get("success", false) == true:
		_send_output(sender_id, "Ban removed: %s" % str(result.get("fingerprint", "")))
	else:
		_send_output(sender_id, str(result.get("reason", "Failed to remove ban")))

func _command_kick(sender_id: int, arguments: Array[String]) -> void:
	if arguments.is_empty() or not arguments[0].is_valid_int():
		_send_output(sender_id, "Usage: /kick <id> <reason>")
		return
	var peer_id := int(arguments[0])
	if not _is_valid_remote_target(peer_id):
		_send_output(sender_id, "Player ID not found or target is the host")
		return
	var reason := _join_arguments(arguments, 1)
	if reason.is_empty():
		reason = "Kicked by host"
	var nickname := str(NicknameManager.get_nickname(peer_id))
	if NetworkManager.kick_player(peer_id, reason):
		_send_output(sender_id, "Player %s (ID %d) kicked" % [nickname, peer_id])
	else:
		_send_output(sender_id, "Failed to kick player")

func _is_valid_remote_target(peer_id: int) -> bool:
	return peer_id > 1 and NetworkManager.is_server() and NetworkManager.registered_peers.has(peer_id)

func _join_arguments(arguments: Array[String], start_index: int) -> String:
	if arguments.size() <= start_index:
		return ""
	var values := PackedStringArray()
	for i in range(start_index, arguments.size()):
		values.append(arguments[i])
	return " ".join(values).strip_edges().substr(0, 160)

func _send_output(sender_id: int, message: String) -> void:
	NetworkManager.send_console_output(sender_id, message)
