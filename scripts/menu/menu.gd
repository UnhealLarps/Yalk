extends Node2D

var rep := Reporter.new("Menu")

const GAME_SCENE := "res://scenes/game.tscn"
const SERVERS_PATH := "user://servers.json"
const NICK_PATH := "user://nickname.txt"
const DEFAULT_PORT := 27015
const SERVER_REFRESH_INTERVAL_MSEC := 60000

@onready var connect_button: Button = $MenuUI/Root/HBoxContainer/Connect
@onready var host_button: Button = $MenuUI/Root/HBoxContainer/Host
@onready var exit_button: Button = $MenuUI/Root/HBoxContainer/Exit
@onready var tutorial_button: Button = $MenuUI/Root/HBoxContainer/Host2
@onready var connect_window: Window = $MenuUI/Root/ConnectWindow
@onready var ip_input_window: Window = $MenuUI/Root/IPInputWindow
@onready var host_window: Window = $MenuUI/Root/HostWindow
@onready var server_list: VBoxContainer = $MenuUI/Root/ConnectWindow/MainLayout/ScrollContainer/ServerListContainer
@onready var server_template: PanelContainer = $MenuUI/Root/ConnectWindow/MainLayout/ScrollContainer/ServerListContainer/ServerTemplate
@onready var host_name_input: LineEdit = $MenuUI/Root/HostWindow/Margin/VBox/ServerNameInput
@onready var max_players_input: SpinBox = $MenuUI/Root/HostWindow/Margin/VBox/MaxPlayersSpinBox
@onready var host_create_button: Button = $MenuUI/Root/HostWindow/Margin/VBox/Buttons/CreateButton
@onready var host_ip_label: Label = $MenuUI/Root/HostWindow/Margin/VBox/Label
@onready var window_node: Window = $MenuUI/Root/NicknameWindow
@onready var line_edit: LineEdit = $MenuUI/Root/NicknameWindow/Margin/VBox/NameLineEdit
@onready var nick_done_button: Button = $MenuUI/Root/NicknameWindow/Margin/VBox/DoneButton

var servers: Array[Dictionary] = []
var hosting_started := false
var server_refresh_running := false
var server_refresh_queue: Array[Dictionary] = []
var server_refresh_index := 0
var last_server_refresh_msec := -SERVER_REFRESH_INTERVAL_MSEC
var ip_input: LineEdit

func _ready() -> void:
	_check_nickname_on_start()
	nick_done_button.pressed.connect(_on_done_pressed)
	
	ip_input = ip_input_window.find_child("IPLineEdit", true, false) as LineEdit
	if ip_input == null:
		push_error("IPInputWindow must contain a LineEdit named IPLineEdit.")
		return
	connect_button.pressed.connect(_open_connect_window)
	host_button.pressed.connect(_open_host_window)
	tutorial_button.pressed.connect(_open_tutorial)
	exit_button.pressed.connect(_exit_game)
	NetworkManager.server_probe_finished.connect(_on_server_probe_finished)
	$MenuUI/Root/ConnectWindow/MainLayout/BottomToolbar/PlusButton.pressed.connect(_open_ip_input_window)
	$MenuUI/Root/IPInputWindow/Margin/VBox/DoneButton.pressed.connect(_save_server_from_input)
	host_create_button.pressed.connect(_create_or_enter_host)
	connect_window.close_requested.connect(_close_connect_window)
	ip_input_window.close_requested.connect(_close_ip_input_window)
	host_window.close_requested.connect(_close_host_window)
	server_template.visible = false
	host_name_input.text = "Yalk Server"
	_load_servers()
	_refresh_server_list()

func _process(_delta: float) -> void:
	if connect_window.visible and not ip_input_window.visible and not server_refresh_running and Time.get_ticks_msec() - last_server_refresh_msec >= SERVER_REFRESH_INTERVAL_MSEC:
		_start_server_refresh()

func _open_connect_window() -> void:
	_refresh_server_list()
	connect_window.popup_centered()
	_start_server_refresh()

func _open_tutorial() -> void:
	_stop_server_refresh()
	if NetworkManager.is_networked():
		NetworkManager.disconnect_network()
	hosting_started = false
	get_tree().change_scene_to_file("res://scenes/tutorial.tscn")

func _open_host_window() -> void:
	if NetworkManager.is_networked() and NetworkManager.is_server():
		hosting_started = true
		host_create_button.text = "ENTER GAME"
		host_ip_label.text = "Your IP for connect:\n%s" % NetworkManager.get_host_address()
	else:
		hosting_started = false
		host_create_button.text = "CREATE"
		host_ip_label.text = "Your IP for connect:"
	host_window.popup_centered()

func _exit_game() -> void:
	get_tree().quit()

func _open_ip_input_window() -> void:
	if ip_input == null:
		return
	_stop_server_refresh()
	ip_input.text = ""
	ip_input_window.popup_centered()

func _save_server_from_input() -> void:
	if ip_input == null:
		return
	var address := ip_input.text.strip_edges()
	if address.is_empty():
		ip_input.grab_focus()
		return
	var ip := address
	var port := DEFAULT_PORT
	if address.begins_with("["):
		var closing_bracket := address.find("]")
		if closing_bracket <= 1:
			ip_input.grab_focus()
			return
		ip = address.substr(1, closing_bracket - 1)
		var suffix := address.substr(closing_bracket + 1).strip_edges()
		if not suffix.is_empty():
			if not suffix.begins_with(":") or not suffix.substr(1).is_valid_int():
				ip_input.grab_focus()
				return
			port = int(suffix.substr(1))
	elif address.count(":") == 1:
		var parts := address.split(":")
		if not parts[1].is_valid_int():
			ip_input.grab_focus()
			return
		ip = parts[0].strip_edges()
		port = int(parts[1])
	if ip.is_empty() or port < 1 or port > 65535:
		ip_input.grab_focus()
		return
	var updated := false
	for i in range(servers.size()):
		var existing: Dictionary = servers[i]
		if str(existing.get("ip", "")) == ip and int(existing.get("port", DEFAULT_PORT)) == port:
			servers[i] = existing
			updated = true
			break
	if not updated:
		servers.append({"name": "", "server_name": "", "ip": ip, "port": port, "players": -1, "max_players": -1, "status": "unknown"})
	_save_servers()
	_refresh_server_list()
	last_server_refresh_msec = -SERVER_REFRESH_INTERVAL_MSEC
	ip_input_window.hide()
	connect_window.popup_centered()
	_start_server_refresh()

func _load_servers() -> void:
	servers.clear()
	if not FileAccess.file_exists(SERVERS_PATH):
		_save_servers()
		return
	var file := FileAccess.open(SERVERS_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Array):
		return
	for value in parsed:
		if not (value is Dictionary):
			continue
		var data: Dictionary = value
		var ip := str(data.get("ip", data.get("address", ""))).strip_edges()
		var port := int(data.get("port", DEFAULT_PORT))
		if ip.is_empty() or port < 1 or port > 65535:
			continue
		if ip.count(":") == 1 and ip.split(":").size() == 2:
			var endpoint_parts := ip.split(":")
			if endpoint_parts[1].is_valid_int():
				port = clampi(int(endpoint_parts[1]), 1, 65535)
				ip = endpoint_parts[0]
		servers.append({
				"name": str(data.get("name", "")),
				"server_name": str(data.get("server_name", "")),
				"ip": ip,
				"port": port,
				"players": int(data.get("players", -1)),
				"max_players": int(data.get("max_players", -1)),
				"status": str(data.get("status", "unknown"))
			})

func _save_servers() -> void:
	var file := FileAccess.open(SERVERS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not open %s for writing." % SERVERS_PATH)
		return
	file.store_string(JSON.stringify(servers, "\t"))
	file.close()

func _refresh_server_list() -> void:
	for child in server_list.get_children():
		if child != server_template and not child.is_queued_for_deletion():
			child.queue_free()
	for i in range(servers.size()):
		var server: Dictionary = servers[i]
		var row := server_template.duplicate() as PanelContainer
		row.name = "Server_%d" % i
		row.visible = true
		server_list.add_child(row)
		var row_name := row.get_node("Margin/HBox/ServerName") as Label
		var player_count := row.get_node("Margin/HBox/PlayerCount") as Label
		var row_connect := row.get_node("Margin/HBox/ConnectButton") as Button
		var row_delete := row.get_node("Margin/HBox/DeleteButton") as Button
		var ip := str(server.get("ip", ""))
		var port := int(server.get("port", DEFAULT_PORT))
		var display_name := str(server.get("name", "")).strip_edges()
		if display_name.is_empty():
			display_name = str(server.get("server_name", "")).strip_edges()
		if display_name.is_empty():
			display_name = ip
		row_name.text = "%s  [%s:%d]" % [display_name, ip, port]
		row_name.tooltip_text = "%s:%d" % [ip, port]
		var players := int(server.get("players", -1))
		var max_players := int(server.get("max_players", -1))
		var status := str(server.get("status", "unknown"))
		if status == "offline":
			player_count.text = "OFFLINE"
		elif players >= 0 and max_players > 0:
			player_count.text = "Players: %d/%d" % [players, max_players]
		else:
			player_count.text = "Players: ?/?"
		row_connect.text = "Join"
		row_delete.text = "Delete"
		row_connect.pressed.connect(_connect_to_server.bind(server.duplicate(true)))
		row_delete.pressed.connect(_delete_server.bind(server.duplicate(true)))

func _start_server_refresh() -> void:
	if server_refresh_running or NetworkManager.is_networked() or servers.is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - last_server_refresh_msec < SERVER_REFRESH_INTERVAL_MSEC:
		return
	last_server_refresh_msec = now
	server_refresh_running = true
	server_refresh_queue.clear()
	for server in servers:
		server_refresh_queue.append(server.duplicate(true))
	server_refresh_index = 0
	_refresh_next_server()

func _refresh_next_server() -> void:
	if not server_refresh_running:
		return
	if server_refresh_index >= server_refresh_queue.size():
		server_refresh_running = false
		last_server_refresh_msec = Time.get_ticks_msec()
		_load_servers()
		_refresh_server_list()
		return
	var server := server_refresh_queue[server_refresh_index]
	server_refresh_index += 1
	var error := NetworkManager.probe_server_info(str(server.get("ip", "")), int(server.get("port", DEFAULT_PORT)))
	if error != OK:
		call_deferred("_refresh_next_server")

func _on_server_probe_finished(_ip: String, _port: int, _success: bool) -> void:
	if not server_refresh_running:
		return
	call_deferred("_apply_server_probe_result")

func _apply_server_probe_result() -> void:
	if not server_refresh_running:
		return
	_load_servers()
	_refresh_server_list()
	_refresh_next_server()

func _stop_server_refresh() -> void:
	server_refresh_running = false
	server_refresh_queue.clear()
	server_refresh_index = 0
	NetworkManager.cancel_server_probe()

func _delete_server(server: Dictionary) -> void:
	_stop_server_refresh()
	var ip := str(server.get("ip", ""))
	var port := int(server.get("port", DEFAULT_PORT))
	for i in range(servers.size() - 1, -1, -1):
		if str(servers[i].get("ip", "")) == ip and int(servers[i].get("port", DEFAULT_PORT)) == port:
			servers.remove_at(i)
			break
	_save_servers()
	call_deferred("_refresh_server_list")
	last_server_refresh_msec = -SERVER_REFRESH_INTERVAL_MSEC

func _connect_to_server(server: Dictionary) -> void:
	_stop_server_refresh()
	var ip := str(server.get("ip", "")).strip_edges()
	var port := int(server.get("port", DEFAULT_PORT))
	var error := NetworkManager.connect_to(ip, port)
	if error != OK:
		connect_window.title = "Server Browser — %s" % error_string(error)
		return
	NetworkManager.set_pending_server_entry(server)
	var change_error := get_tree().change_scene_to_file(GAME_SCENE)
	if change_error != OK:
		NetworkManager.disconnect_network()
		connect_window.title = "Server Browser — %s" % error_string(change_error)

func _create_or_enter_host() -> void:
	_stop_server_refresh()
	if hosting_started and NetworkManager.is_networked() and NetworkManager.is_server():
		var change_error := get_tree().change_scene_to_file(GAME_SCENE)
		if change_error != OK:
			host_ip_label.text = "Could not open game: %s" % error_string(change_error)
		return
	var server_name := host_name_input.text.strip_edges()
	if server_name.is_empty():
		server_name = "Yalk Server"
	var max_players := clampi(int(max_players_input.value), 2, 64)
	var error := NetworkManager.host(DEFAULT_PORT, max_players, server_name)
	if error != OK:
		host_ip_label.text = "Could not host: %s" % error_string(error)
		return
	hosting_started = true
	host_create_button.text = "ENTER GAME"
	host_ip_label.text = "Your IP for connect:\n%s" % NetworkManager.get_host_address()

func _close_connect_window() -> void:
	_stop_server_refresh()
	connect_window.hide()

func _close_ip_input_window() -> void:
	ip_input_window.hide()

func _close_host_window() -> void:
	host_window.hide()
	if hosting_started and get_tree().current_scene == self:
		NetworkManager.disconnect_network()
		hosting_started = false
		host_create_button.text = "CREATE"
		host_ip_label.text = "Your IP for connect:"

func _check_nickname_on_start() -> void:
	if not FileAccess.file_exists(NICK_PATH):
		window_node.show()
		return
		
	var file = FileAccess.open(NICK_PATH, FileAccess.READ)
	var current_name = file.get_as_text().strip_edges()
	file.close()
	
	if current_name == "" or current_name.to_lower() == "player":
		window_node.show()
	else:
		window_node.hide()
		
func _on_done_pressed() -> void:
	var entered_text = line_edit.text.strip_edges()
	if entered_text == "":
		return
		
	var file = FileAccess.open(NICK_PATH, FileAccess.WRITE)
	file.store_string(entered_text)
	file.close()
	
	window_node.hide()
	rep.info("New nickname: {entered_text}")
