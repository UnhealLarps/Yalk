extends Resource

var mode_id := "massacre"
var mode_name := "Massacre"
var description := "The Shooter hunts everyone. Fallen players can return as Police."
var image: Texture2D = preload("res://sprites/ui/rounds/massacre.png")
var music_path := "res://audio/music/rounds/alexgrohl-metal-dark-matter.mp3"
var promotion_team := "Police"
var police_deployed := false
var teams := [
	{"name": "Victim", "percentage": 99.0, "items": ["", ""]},
	{"name": "Shooter", "percentage": 1.0, "items": ["res://prefabs/weapons/pistols/rifle.tscn", ""]},
	{"name": "Police", "percentage": 0.0, "items": ["res://prefabs/weapons/pistols/glock17.tscn", ""]}
]
var outlines := [
	{"team": "Shooter", "color": Color(1.0, 0.035, 0.035, 1.0), "visible_to": ["Shooter"]},
	{"team": "Police", "color": Color(0.15, 0.55, 1.0, 1.0), "visible_to": ["Police"]}
]

func assign_roles(player_ids: Array[int]) -> Dictionary:
	police_deployed = false
	var result: Dictionary = {}
	if player_ids.is_empty():
		return result
	var shuffled: Array[int] = player_ids.duplicate()
	shuffled.shuffle()
	for peer_id in shuffled:
		result[peer_id] = "Victim"
	result[shuffled[0]] = "Shooter"
	return result

func get_team(team_name: String) -> Dictionary:
	for team_value in teams:
		if team_value is Dictionary and str(team_value.get("name", "")) == team_name:
			return team_value.duplicate(true)
	return {}

func get_players_to_promote(round_elapsed: float, player_ids: Array[int], roles: Dictionary) -> Array[int]:
	if police_deployed or round_elapsed < get_police_deployment_time(player_ids.size()):
		return []
	var dead_players: Array[int] = []
	for peer_id in player_ids:
		var id := int(peer_id)
		if str(roles.get(id, "")) != "Victim":
			continue
		var player := NetworkManager.get_player(id)
		if player == null or not is_instance_valid(player):
			continue
		if player.get("is_dead") == true:
			dead_players.append(id)
	if dead_players.is_empty():
		return []
	dead_players.shuffle()
	var promote_count := maxi(1, ceili(float(dead_players.size()) * 0.5))
	police_deployed = true
	return dead_players.slice(0, promote_count)

func get_police_deployment_time(player_count: int) -> float:
	if player_count <= 4:
		return 180.0
	if player_count <= 8:
		return 240.0
	return 300.0

func get_winner(player_ids: Array[int], roles: Dictionary) -> String:
	var shooter_id := 0
	for peer_id in roles.keys():
		if str(roles[peer_id]) == "Shooter":
			shooter_id = int(peer_id)
			break
	if shooter_id <= 0:
		return ""
	var shooter := NetworkManager.get_player(shooter_id)
	if not player_ids.has(shooter_id):
		for role_value in roles.values():
			if str(role_value) == "Police":
				return "Police"
		return "Victims"
	if shooter == null or not is_instance_valid(shooter):
		return ""
	if shooter.get("is_dead") == true:
		for role_value in roles.values():
			if str(role_value) == "Police":
				return "Police"
		return "Victims"
	var others_alive := false
	for peer_id in player_ids:
		var id := int(peer_id)
		if id == shooter_id:
			continue
		var player := NetworkManager.get_player(id)
		if player == null or not is_instance_valid(player):
			continue
		if player.get("is_dead") != true:
			others_alive = true
			break
	if not others_alive:
		return "Shooter"
	return ""
