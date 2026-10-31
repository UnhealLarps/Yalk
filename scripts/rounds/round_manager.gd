
extends Node

enum Phase {
	WAITING,
	INTRO,
	PLAYING
}

const WAITING_TIME := 10.0
const INTRO_TIME := 5.0
const MIN_PLAYERS := 2
const ROUND_START_SCENE = preload("res://prefabs/ui/roundStart.tscn")
const ROUND_RESULT_SCENE = preload("res://prefabs/ui/roundResult.tscn")
const MURDERER_MODE = preload("res://scripts/rounds/murderer.gd")
const MASSACRE_MODE = preload("res://scripts/rounds/massacre.gd")
const DEATHMATCH_MODE = preload("res://scripts/rounds/deathmatch.gd")

var mode: Resource = MURDERER_MODE.new()
var phase: int = Phase.WAITING
var phase_time := WAITING_TIME
var round_elapsed := 0.0
var round_number := 0
var winner := ""
var started := false
var active_players: Array[int] = []
var waiting_players: Array[int] = []
var waiting_positions: Dictionary = {}
var roles: Dictionary = {}
var round_start_ui: CanvasLayer = null
var round_result_ui: CanvasLayer = null
var state_timer := 0.0
var completed_rounds := 0
var client_sync_phase_time := WAITING_TIME
var client_sync_round_elapsed := 0.0
var client_sync_received_usec := 0
var phase_end_server_usec := 0
var round_start_server_usec := 0
var last_received_map_revision := -1
var map_reset_pending := false
var shooter_music_player: AudioStreamPlayer = null
var shooter_music_path := ""

func _ready():
	if NetworkManager.is_server():
		start_host_rounds()

func _process(delta: float):
	if not started:
		return
	if NetworkManager.is_server():
		var now_usec := Time.get_ticks_usec()
		if phase == Phase.WAITING or phase == Phase.INTRO:
			phase_time = maxf(float(phase_end_server_usec - now_usec) / 1000000.0, 0.0) if phase_end_server_usec > 0 else 0.0
			if phase_time <= 0.0:
				_advance_phase()
		elif phase == Phase.PLAYING:
			round_elapsed = maxf(float(now_usec - round_start_server_usec) / 1000000.0, 0.0) if round_start_server_usec > 0 else 0.0
			_process_mode_round()
			_check_round_end()
		_update_ui()
		state_timer += delta
		if state_timer >= 0.1:
			state_timer = 0.0
			broadcast_state()
	else:
		_update_client_clock()
		_update_ui()

func _update_client_clock():
	var estimated_server_time := NetworkManager.get_estimated_server_time_usec()
	if estimated_server_time > 0:
		if (phase == Phase.WAITING or phase == Phase.INTRO) and phase_end_server_usec > 0:
			phase_time = maxf(float(phase_end_server_usec - estimated_server_time) / 1000000.0, 0.0)
			round_elapsed = 0.0
			return
		if phase == Phase.PLAYING and round_start_server_usec > 0:
			phase_time = 0.0
			round_elapsed = maxf(float(estimated_server_time - round_start_server_usec) / 1000000.0, 0.0)
			return
	if client_sync_received_usec <= 0:
		return
	var elapsed_since_sync := float(Time.get_ticks_usec() - client_sync_received_usec) / 1000000.0
	if phase == Phase.WAITING or phase == Phase.INTRO:
		phase_time = maxf(client_sync_phase_time - elapsed_since_sync, 0.0)
	else:
		phase_time = 0.0
	if phase == Phase.PLAYING:
		round_elapsed = client_sync_round_elapsed + elapsed_since_sync
	else:
		round_elapsed = 0.0

func start_host_rounds():
	if not NetworkManager.is_server() or started:
		return
	started = true
	phase = Phase.WAITING
	phase_time = WAITING_TIME
	phase_end_server_usec = Time.get_ticks_usec() + int(WAITING_TIME * 1000000.0)
	round_start_server_usec = 0
	round_elapsed = 0.0
	round_number = 0
	completed_rounds = 0
	map_reset_pending = false
	winner = ""
	active_players.clear()
	waiting_players = NetworkManager.get_connected_peer_ids()
	waiting_positions.clear()
	roles.clear()
	NetworkManager.begin_waiting_entities(waiting_players, waiting_positions)
	_update_ui()

func player_joined(peer_id: int):
	if not NetworkManager.is_server():
		return
	if phase != Phase.WAITING:
		return
	if not waiting_players.has(peer_id):
		waiting_players.append(peer_id)
	NetworkManager.begin_waiting_entities([peer_id])
	broadcast_state()

func player_left(peer_id: int):
	if not NetworkManager.is_server():
		return
	active_players.erase(peer_id)
	waiting_players.erase(peer_id)
	waiting_positions.erase(peer_id)
	if phase == Phase.PLAYING:
		_check_round_end()

func should_have_player(peer_id: int) -> bool:
	if not started:
		return false
	if phase == Phase.INTRO or phase == Phase.PLAYING:
		return active_players.has(peer_id)
	return waiting_players.has(peer_id)

func is_player_active(peer_id: int) -> bool:
	return started and (phase == Phase.INTRO or phase == Phase.PLAYING) and active_players.has(peer_id)

func get_role(peer_id: int) -> String:
	var value: Variant = roles.get(peer_id, "")
	return value if value is String else ""

func _advance_phase():
	match phase:
		Phase.WAITING:
			if not _can_start_round():
				phase_time = WAITING_TIME
				phase_end_server_usec = Time.get_ticks_usec() + int(WAITING_TIME * 1000000.0)
				round_start_server_usec = 0
				broadcast_state()
				return
			_start_intro()
		Phase.INTRO:
			_start_playing()
		Phase.PLAYING:
			return

func _can_start_round() -> bool:
	var peer_ids := NetworkManager.get_connected_peer_ids()
	if peer_ids.size() < MIN_PLAYERS:
		return false
	var map_manager := NetworkManager.get_map_manager()
	if map_manager == null:
		if map_reset_pending and NetworkManager.has_method("clear_round_items"):
			NetworkManager.clear_round_items()
		map_reset_pending = false
		return true
	if map_reset_pending and NetworkManager.has_method("clear_round_items"):
		NetworkManager.clear_round_items()
	var old_revision := int(map_manager.get("map_revision"))
	var map_ready := false
	if map_reset_pending:
		if completed_rounds % 3 == 0 and map_manager.has_method("change_to_random_map"):
			map_ready = map_manager.call("change_to_random_map", peer_ids.size()) == true
		elif map_manager.has_method("reset_current_map"):
			map_ready = map_manager.call("reset_current_map", peer_ids.size()) == true
		if not map_ready and map_manager.has_method("ensure_map_for_player_count"):
			map_ready = map_manager.call("ensure_map_for_player_count", peer_ids.size()) == true
		if not map_ready:
			return false
		map_reset_pending = false
	elif map_manager.has_method("ensure_map_for_player_count"):
		map_ready = map_manager.call("ensure_map_for_player_count", peer_ids.size()) == true
		if not map_ready:
			return false
	if int(map_manager.get("map_revision")) != old_revision:
		waiting_positions = NetworkManager.move_players_to_map_spawns(peer_ids)
	return true

func _start_intro():
	mode = _choose_random_mode()
	round_number += 1
	phase = Phase.INTRO
	phase_time = INTRO_TIME
	phase_end_server_usec = Time.get_ticks_usec() + int(INTRO_TIME * 1000000.0)
	round_start_server_usec = 0
	round_elapsed = 0.0
	winner = ""
	waiting_players.clear()
	waiting_positions.clear()
	active_players = NetworkManager.get_connected_peer_ids()
	if mode.has_method("assign_roles"):
		roles = mode.call("assign_roles", active_players)
	else:
		roles = {}
	NetworkManager.begin_round_entities(active_players, roles)
	_give_team_items()
	_apply_team_outlines()
	_show_round_start()
	broadcast_state()

func _start_playing():
	phase = Phase.PLAYING
	phase_time = 0.0
	phase_end_server_usec = 0
	round_start_server_usec = Time.get_ticks_usec()
	round_elapsed = 0.0
	_hide_round_start()
	broadcast_state()

func _end_round(result: String):
	if not NetworkManager.is_server():
		return
	var waiting_state: Dictionary = NetworkManager.prepare_waiting_entities()
	winner = result
	waiting_players = _read_player_ids(waiting_state.get("players", []))
	var old_positions: Dictionary = waiting_state.get("positions", {}) if waiting_state.get("positions", {}) is Dictionary else {}
	waiting_positions.clear()
	for peer_id in waiting_players:
		if old_positions.has(peer_id):
			waiting_positions[peer_id] = old_positions[peer_id]
	completed_rounds += 1
	map_reset_pending = true
	phase = Phase.WAITING
	phase_time = WAITING_TIME
	phase_end_server_usec = Time.get_ticks_usec() + int(WAITING_TIME * 1000000.0)
	round_start_server_usec = 0
	round_elapsed = 0.0
	active_players.clear()
	broadcast_state()
	_update_ui()


func _get_team_definition(team_name: String) -> Dictionary:
	if mode.has_method("get_team"):
		var configured_team: Variant = mode.call("get_team", team_name)
		if configured_team is Dictionary:
			return configured_team
	var teams_value: Variant = mode.get("teams")
	if not teams_value is Array:
		return {}
	for team_value in teams_value:
		if team_value is Dictionary and str(team_value.get("name", "")) == team_name:
			return team_value
	return {}

func _give_team_items():
	if not NetworkManager.is_server():
		return
	for peer_id in active_players:
		_give_items_to_player(int(peer_id), str(roles.get(peer_id, "")))

func _give_items_to_player(peer_id: int, team_name: String):
	if not NetworkManager.is_server():
		return
	var item_paths: Variant
	if mode.has_method("get_items_for_player"):
		item_paths = mode.call("get_items_for_player", peer_id, team_name)
	else:
		item_paths = _get_team_definition(team_name).get("items", [])
	if not item_paths is Array:
		return
	for slot_index in range(mini(item_paths.size(), 2)):
		var scene_path := str(item_paths[slot_index]).strip_edges()
		if scene_path.is_empty():
			continue
		if not NetworkManager.has_method("spawn_item_in_slot") or not NetworkManager.spawn_item_in_slot(peer_id, slot_index, scene_path):
			push_warning("Could not give '%s' to team '%s', slot %d, player %d" % [scene_path, team_name, slot_index + 1, peer_id])

func _process_mode_round():
	if not mode.has_method("get_players_to_promote"):
		return
	var promoted_value: Variant = mode.call("get_players_to_promote", round_elapsed, active_players, roles)
	if not promoted_value is Array or promoted_value.is_empty():
		return
	var promotion_team := str(mode.get("promotion_team"))
	if promotion_team.is_empty():
		return
	var changed := false
	for peer_id_value in promoted_value:
		var peer_id := int(peer_id_value)
		if not active_players.has(peer_id) or roles.has(peer_id) and str(roles[peer_id]) == promotion_team:
			continue
		if NetworkManager.has_method("respawn_player_for_team") and NetworkManager.respawn_player_for_team(peer_id, promotion_team):
			roles[peer_id] = promotion_team
			_give_items_to_player(peer_id, promotion_team)
			changed = true
	if changed:
		_apply_team_outlines()
		broadcast_state()

func _apply_team_outlines():
	var viewer_role := str(roles.get(NetworkManager.local_player_id, ""))
	var outline_definitions: Variant = mode.get("outlines")
	for peer_id_value in roles.keys():
		var peer_id := int(peer_id_value)
		var player := NetworkManager.get_player(peer_id)
		if player == null or not is_instance_valid(player) or not player.has_method("set_round_role"):
			continue
		var target_role := str(roles.get(peer_id, ""))
		var outline_enabled := false
		var outline_color := Color.RED
		if outline_definitions is Array:
			for definition in outline_definitions:
				if not definition is Dictionary or str(definition.get("team", "")) != target_role:
					continue
				var visible_to: Variant = definition.get("visible_to", [])
				if visible_to is Array and (visible_to.has(viewer_role) or visible_to.has("*")):
					outline_enabled = true
					var color_value: Variant = definition.get("color", Color.RED)
					if color_value is Color:
						outline_color = color_value
					break
		player.call("set_round_role", target_role, outline_enabled, outline_color)

func _get_mode_id() -> String:
	var value: Variant = mode.get("mode_id")
	return str(value) if value is String else "murderer"

func _choose_random_mode() -> Resource:
	var available_modes: Array[Resource] = [MURDERER_MODE.new(), MASSACRE_MODE.new(), DEATHMATCH_MODE.new()]
	return available_modes.pick_random() as Resource

func _create_mode(mode_id: String) -> Resource:
	match mode_id.to_lower():
		"massacre":
			return MASSACRE_MODE.new() as Resource
		"deathmatch":
			return DEATHMATCH_MODE.new() as Resource
		_:
			return MURDERER_MODE.new() as Resource

func _check_round_end():
	if phase != Phase.PLAYING or not NetworkManager.is_server():
		return
	var result := str(mode.call("get_winner", active_players, roles))
	if not result.is_empty():
		_end_round(result)

func _build_state() -> Dictionary:
	var positions: Dictionary = waiting_positions.duplicate()
	for peer_id in NetworkManager.get_connected_peer_ids():
		var player := NetworkManager.get_player(peer_id)
		if player != null and is_instance_valid(player):
			positions[peer_id] = player.global_position
	var map_name := ""
	var map_revision := 0
	var map_manager := NetworkManager.get_map_manager()
	if map_manager != null and map_manager.has_method("get_current_map_name"):
		map_name = str(map_manager.call("get_current_map_name"))
		if map_manager.has_method("get_map_revision"):
			map_revision = int(map_manager.call("get_map_revision"))
	return {"phase": phase, "phase_time": phase_time, "round_elapsed": round_elapsed, "server_time_usec": Time.get_ticks_usec(), "phase_end_server_usec": phase_end_server_usec, "round_start_server_usec": round_start_server_usec, "round_number": round_number, "completed_rounds": completed_rounds, "winner": winner, "active_players": active_players, "waiting_players": waiting_players, "roles": roles, "mode_id": _get_mode_id(), "mode_name": mode.get("mode_name"), "mode_description": mode.get("description"), "music_path": str(mode.get("music_path")), "map_name": map_name, "map_revision": map_revision, "positions": positions}

func broadcast_state():
	if not NetworkManager.is_server():
		return
	receive_state.rpc(_build_state())
	_update_ui()

func send_state_to_peer(peer_id: int):
	if not NetworkManager.is_server():
		return
	receive_state.rpc_id(peer_id, _build_state())

@rpc("authority", "call_remote", "reliable", 8)
func receive_state(state: Dictionary):
	if NetworkManager.is_server():
		return
	var incoming_mode_id := str(state.get("mode_id", "murderer"))
	if incoming_mode_id != _get_mode_id():
		mode = _create_mode(incoming_mode_id)
	phase = int(state.get("phase", Phase.WAITING))
	phase_end_server_usec = int(state.get("phase_end_server_usec", 0))
	round_start_server_usec = int(state.get("round_start_server_usec", 0))
	var received_phase_time := float(state.get("phase_time", WAITING_TIME))
	var received_round_elapsed := float(state.get("round_elapsed", 0.0))
	var server_time_usec := int(state.get("server_time_usec", 0))
	var state_age := 0.0
	var estimated_server_time := NetworkManager.get_estimated_server_time_usec()
	if server_time_usec > 0 and estimated_server_time > 0:
		state_age = maxf(float(estimated_server_time - server_time_usec) / 1000000.0, 0.0)
	client_sync_phase_time = maxf(received_phase_time - state_age, 0.0)
	client_sync_round_elapsed = received_round_elapsed + state_age
	client_sync_received_usec = Time.get_ticks_usec()
	phase_time = client_sync_phase_time
	round_elapsed = client_sync_round_elapsed
	round_number = int(state.get("round_number", 0))
	completed_rounds = int(state.get("completed_rounds", completed_rounds))
	winner = state.get("winner", "") if state.get("winner", "") is String else ""
	var incoming_music_path := str(state.get("music_path", ""))
	if not incoming_music_path.is_empty():
		mode.set("music_path", incoming_music_path)
	active_players = _read_player_ids(state.get("active_players", []))
	waiting_players = _read_player_ids(state.get("waiting_players", []))
	roles = state.get("roles", {}) if state.get("roles", {}) is Dictionary else {}
	var positions: Dictionary = state.get("positions", {}) if state.get("positions", {}) is Dictionary else {}
	var map_changed := false
	var incoming_map_name := str(state.get("map_name", ""))
	var incoming_map_revision := int(state.get("map_revision", 0))
	var map_manager := NetworkManager.get_map_manager()
	if not incoming_map_name.is_empty() and map_manager != null and map_manager.has_method("get_current_map_name"):
		var local_map_name := str(map_manager.call("get_current_map_name"))
		var map_revision_changed := incoming_map_revision > 0 and incoming_map_revision != last_received_map_revision
		if (local_map_name != incoming_map_name or map_revision_changed) and map_manager.has_method("load_map"):
			map_changed = map_manager.call("load_map", incoming_map_name, true) == true
		if map_changed or local_map_name == incoming_map_name:
			last_received_map_revision = incoming_map_revision
	started = true
	NetworkManager.sync_round_entities(active_players, waiting_players, positions, round_number, map_changed)
	NetworkManager.flush_pending_player_states()
	_apply_team_outlines()
	_update_ui()

func is_round_playing() -> bool:
	return started and phase == Phase.PLAYING

func _read_player_ids(value: Variant) -> Array[int]:
	var result: Array[int] = []
	if value is Array:
		for peer_id in value:
			result.append(int(peer_id))
	return result

func _show_round_start():
	if Args.headless or get_tree().current_scene == null:
		return
	_hide_round_result()
	if round_start_ui != null and is_instance_valid(round_start_ui):
		return
	round_start_ui = ROUND_START_SCENE.instantiate() as CanvasLayer
	if round_start_ui == null:
		return
	get_tree().current_scene.add_child(round_start_ui)
	var mode_label := round_start_ui.get_node_or_null("Root/ModePanel/ModeName") as Label
	var role_label := round_start_ui.get_node_or_null("Root/RolePanel/RoleName") as Label
	var image := round_start_ui.get_node_or_null("Root/ModeImage") as TextureRect
	if mode_label != null:
		mode_label.text = str(mode.get("mode_name"))
	if role_label != null:
		var role := get_role(NetworkManager.local_player_id)
		role_label.text = role if not role.is_empty() else "Spectator"
	if image != null:
		var image_value: Variant = mode.get("image")
		if image_value is Texture2D:
			image.texture = image_value
	if _should_continue_shooter_music():
		_update_shooter_music()
	elif round_start_ui.has_method("play_presentation_music"):
		round_start_ui.call("play_presentation_music", str(mode.get("music_path")), INTRO_TIME)


func _should_continue_shooter_music() -> bool:
	if Args.headless or not started or NetworkManager.local_player_id <= 0:
		return false
	if phase != Phase.INTRO and phase != Phase.PLAYING:
		return false
	return str(mode.get("mode_id")) == "massacre" and get_role(NetworkManager.local_player_id) == "Shooter"

func _update_shooter_music():
	if not _should_continue_shooter_music():
		_stop_shooter_music()
		return
	var path := str(mode.get("music_path"))
	if path.is_empty():
		_stop_shooter_music()
		return
	if shooter_music_player != null and is_instance_valid(shooter_music_player) and shooter_music_path == path:
		if not shooter_music_player.playing:
			shooter_music_player.play()
		return
	_stop_shooter_music()
	var loaded_stream := ResourceLoader.load(path) as AudioStream
	if loaded_stream == null:
		return
	var stream := loaded_stream.duplicate(true) as AudioStream
	if stream == null:
		stream = loaded_stream
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	shooter_music_player = AudioStreamPlayer.new()
	shooter_music_player.name = "ShooterRoleMusic"
	shooter_music_player.stream = stream
	shooter_music_player.volume_db = -3.0
	shooter_music_path = path
	add_child(shooter_music_player)
	shooter_music_player.play()

func _stop_shooter_music():
	if shooter_music_player != null and is_instance_valid(shooter_music_player):
		shooter_music_player.stop()
		shooter_music_player.queue_free()
	shooter_music_player = null
	shooter_music_path = ""

func _hide_round_start():
	if round_start_ui != null and is_instance_valid(round_start_ui):
		GC.destroy(round_start_ui)
	round_start_ui = null

func _show_round_result():
	if Args.headless or get_tree().current_scene == null:
		return
	if round_result_ui != null and is_instance_valid(round_result_ui):
		return
	round_result_ui = ROUND_RESULT_SCENE.instantiate() as CanvasLayer
	if round_result_ui == null:
		return
	get_tree().current_scene.add_child(round_result_ui)

func _hide_round_result():
	if round_result_ui != null and is_instance_valid(round_result_ui):
		GC.destroy(round_result_ui)
	round_result_ui = null

func _update_ui():
	_update_shooter_music()
	if Args.headless:
		return
	if phase == Phase.INTRO:
		_hide_round_result()
		_show_round_start()
		return
	_hide_round_start()
	if phase == Phase.WAITING:
		_show_round_result()
		if round_result_ui == null:
			return
		var winner_label := round_result_ui.get_node_or_null("Root/RolePanel/Winner") as Label
		var timer := round_result_ui.get_node_or_null("Root/RolePanel/Timer") as Label
		if winner_label != null:
			winner_label.text = "Waiting for players" if winner.is_empty() else "%s Win" % winner
		if timer != null:
			timer.text = "Next round in %02d" % int(ceil(phase_time))
	else:
		_hide_round_result()
