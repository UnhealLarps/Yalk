extends CanvasLayer

const CHAT_RANGE := 420.0
const CHAT_DURATION := 4.0
const MAX_MESSAGE_LENGTH := 200
const MAX_HISTORY_LINES := 5

@onready var input_panel: Panel = $Root/InputPanel
@onready var input: LineEdit = $Root/InputPanel/Input
@onready var history: RichTextLabel = $Root/ChatHistory

var chat_open := false
var suppress_open := false
var chat_player: CharacterBody2D
var history_lines: Array[String] = []
var bubble_timers: Dictionary = {}

func _ready() -> void:
	input_panel.visible = false
	history.visible = false
	input.text_submitted.connect(_on_text_submitted)
	if not NetworkManager.chat_message_received.is_connected(_on_chat_message_received):
		NetworkManager.chat_message_received.connect(_on_chat_message_received)

func _process(delta: float) -> void:
	if chat_open and not _can_write():
		_close_chat()
	if chat_open:
		if Input.is_action_just_pressed("cancel") or Input.is_action_just_pressed("ui_cancel"):
			_close_chat()
		_update_bubbles(delta)
		return
	if suppress_open:
		if not Input.is_action_pressed("chat"):
			suppress_open = false
		_update_bubbles(delta)
		return
	if Input.is_action_just_pressed("chat") and _can_write():
		_open_chat()
	_update_bubbles(delta)

func _find_local_live_player() -> CharacterBody2D:
	if NetworkManager.local_player_id > 0:
		var player := NetworkManager.get_player(NetworkManager.local_player_id)
		if player != null and player.get("is_dead") != true:
			return player
		if NetworkManager.is_networked():
			return null
	var scene := get_tree().current_scene
	if scene == null:
		return null
	for node in scene.find_children("*", "", true, false):
		if not node is CharacterBody2D or not node.has_method("get_network_state"):
			continue
		if node.get("local_player") == true and node.get("is_dead") != true:
			return node as CharacterBody2D
	return null

func _find_local_viewer() -> Node2D:
	var player := _find_local_live_player()
	if player != null:
		return player
	if NetworkManager.local_player_id > 0:
		var ghost_value: Variant = NetworkManager.ghosts.get(NetworkManager.local_player_id, null)
		if ghost_value is Node2D and is_instance_valid(ghost_value):
			return ghost_value as Node2D
		var dead_player := NetworkManager.get_player(NetworkManager.local_player_id)
		if dead_player != null:
			return dead_player
	var scene := get_tree().current_scene
	if scene != null:
		for node in scene.find_children("*", "", true, false):
			if node is CharacterBody2D and node.has_method("get_network_state") and node.get("local_player") == true:
				return node as Node2D
	return null

func _is_ghost(viewer: Node2D) -> bool:
	if viewer == null:
		return false
	if int(viewer.get_meta("network_ghost_id", -1)) >= 0 or viewer.name.begins_with("Ghost"):
		return true
	return viewer.get("is_dead") == true

func _can_write() -> bool:
	if Args.headless:
		return false
	return _find_local_live_player() != null

func _open_chat() -> void:
	var player := _find_local_live_player()
	if chat_open or player == null:
		return
	chat_open = true
	chat_player = player
	input_panel.visible = true
	input.text = ""
	player.call("set_chat_input_active", true)
	input.grab_focus()

func _close_chat() -> void:
	chat_open = false
	input_panel.visible = false
	input.release_focus()
	if chat_player != null and is_instance_valid(chat_player) and chat_player.has_method("set_chat_input_active"):
		chat_player.call("set_chat_input_active", false)
	chat_player = null

func _on_text_submitted(value: String) -> void:
	if not chat_open or not _can_write():
		return
	var message := value.strip_edges().substr(0, MAX_MESSAGE_LENGTH)
	if not message.is_empty():
		NetworkManager.send_chat_message(message)
	_close_chat()
	suppress_open = true

func _on_chat_message_received(sender_id: int, nickname: String, message: String, sender_position: Vector2) -> void:
	var viewer := _find_local_viewer()
	if viewer == null:
		return
	var nearby := viewer.global_position.distance_to(sender_position) <= CHAT_RANGE
	if not _is_ghost(viewer) and not nearby:
		return
	var line := "%s: %s" % [nickname, message]
	history_lines.append(line)
	while history_lines.size() > MAX_HISTORY_LINES:
		history_lines.pop_front()
	_render_history()
	if nearby:
		var sender := _find_sender(sender_id)
		if sender != null:
			_show_bubble(sender, message)

func _find_sender(sender_id: int) -> CharacterBody2D:
	if sender_id > 0:
		return NetworkManager.get_player(sender_id)
	var viewer := _find_local_viewer()
	return viewer as CharacterBody2D if viewer is CharacterBody2D and viewer.has_method("get_network_state") else null

func _render_history() -> void:
	var lines := PackedStringArray()
	for line in history_lines:
		lines.append("[outline_size=2][outline_color=#000000][color=#ffffff]%s[/color][/outline_color][/outline_size]" % _escape_bbcode(line))
	history.text = "\n".join(lines)
	history.visible = not history_lines.is_empty()

func _show_bubble(sender: CharacterBody2D, message: String) -> void:
	var bubble := sender.get_node_or_null("ChatBubble") as RichTextLabel
	if bubble == null:
		return
	bubble.text = "[outline_size=3][outline_color=#000000][color=#ffffff]%s[/color][/outline_color][/outline_size]" % _escape_bbcode(message)
	bubble.visible = true
	bubble_timers[bubble.get_instance_id()] = {"label": bubble, "remaining": CHAT_DURATION}

func _update_bubbles(delta: float) -> void:
	for id_value in bubble_timers.keys().duplicate():
		var id := int(id_value)
		var entry_value: Variant = bubble_timers.get(id, null)
		if not entry_value is Dictionary:
			bubble_timers.erase(id)
			continue
		var entry: Dictionary = entry_value
		var label_value: Variant = entry.get("label", null)
		if not label_value is RichTextLabel or not is_instance_valid(label_value):
			bubble_timers.erase(id)
			continue
		var label := label_value as RichTextLabel
		var remaining := float(entry.get("remaining", 0.0)) - delta
		if remaining <= 0.0:
			label.visible = false
			bubble_timers.erase(id)
		else:
			entry["remaining"] = remaining
			bubble_timers[id] = entry

func _escape_bbcode(value: String) -> String:
	return value.replace("[", "[lb]").replace("]", "[rb]")
