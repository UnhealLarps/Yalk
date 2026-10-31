extends Node

const DEFAULT_PORT := 27015

var host := false
var connect_address := ""
var port := DEFAULT_PORT
var headless := false
var player_name := "player"

func _ready():
	var arguments := OS.get_cmdline_args()
	for i in range(arguments.size()):
		var argument: String = arguments[i]
		if argument == "--host":
			host = true
		elif argument == "--headless":
			headless = true
		elif argument == "--name" and i + 1 < arguments.size():
			player_name = arguments[i + 1].strip_edges()
		elif argument.begins_with("--name="):
			player_name = argument.substr(7).strip_edges()
		elif argument == "--connect" and i + 1 < arguments.size():
			connect_address = arguments[i + 1]
		elif argument.begins_with("--connect="):
			connect_address = argument.substr(10)
		elif argument == "--port" and i + 1 < arguments.size() and String(arguments[i + 1]).is_valid_int():
			port = clampi(int(arguments[i + 1]), 1, 65535)
		elif argument.begins_with("--port="):
			var port_value := argument.substr(7)
			if port_value.is_valid_int():
				port = clampi(int(port_value), 1, 65535)

	if player_name.is_empty():
		player_name = "player"
	player_name = player_name.substr(0, 24)

	if DisplayServer.get_name() == "headless":
		headless = true
	if host:
		connect_address = ""

func is_network_requested() -> bool:
	return host or not connect_address.is_empty()
