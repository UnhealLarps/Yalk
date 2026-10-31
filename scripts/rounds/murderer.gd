extends Resource

var mode_id := "murderer"
var mode_name := "Murdererr"
var description := "One Murder hunts the Survivors. Survivors must survive."
var image: Texture2D = preload("res://sprites/ui/rounds/murderer.png")
var music_path := "res://audio/music/rounds/leberch-dark-cinematic.mp3"
var teams := [
	{"name": "Survivor", "percentage": 99.0, "items": ["", ""]},
	{"name": "Murder", "percentage": 1.0, "items": ["res://prefabs/weapons/melee/knife.tscn", ""]}
]
var outlines := [
	{"team": "Murder", "color": Color(1.0, 0.035, 0.035, 1.0), "visible_to": ["Murder"]}
]

func assign_roles(player_ids: Array[int]) -> Dictionary:
	var result: Dictionary = {}
	if player_ids.is_empty():
		return result
	var shuffled: Array[int] = player_ids.duplicate()
	shuffled.shuffle()
	var murder_team := "Murder"
	var survivor_team := "Survivor"
	for team_value in teams:
		if not team_value is Dictionary:
			continue
		var team_name := str(team_value.get("name", ""))
		if team_name.to_lower() == "murder":
			murder_team = team_name
		elif team_name.to_lower() == "survivor":
			survivor_team = team_name
	var murder_id := shuffled[0]
	for peer_id in shuffled:
		result[peer_id] = murder_team if peer_id == murder_id else survivor_team
	return result

func get_team(team_name: String) -> Dictionary:
	for team_value in teams:
		if team_value is Dictionary and str(team_value.get("name", "")) == team_name:
			return team_value.duplicate(true)
	return {}

func get_winner(player_ids: Array[int], roles: Dictionary) -> String:
	var murder_id := 0
	var murder_team_name := "Murder"
	var survivor_team_name := "Survivor"
	var survivor_win_name := "Survivors"
	for team_value in teams:
		if not team_value is Dictionary:
			continue
		var team_name := str(team_value.get("name", ""))
		if team_name.to_lower() == "murder":
			murder_team_name = team_name
		elif team_name.to_lower() == "survivor":
			survivor_team_name = team_name
			survivor_win_name = team_name + "s"
	for peer_id in roles.keys():
		if str(roles[peer_id]).to_lower() == murder_team_name.to_lower():
			murder_id = int(peer_id)
			break
	if murder_id <= 0:
		return ""
	if not player_ids.has(murder_id):
		return survivor_win_name
	var murder := NetworkManager.get_player(murder_id)
	if murder == null or not is_instance_valid(murder):
		return ""
	var murder_dead: Variant = murder.get("is_dead")
	if murder_dead is bool and murder_dead:
		return survivor_win_name
	var survivor_count := 0
	var survivor_alive := false
	for peer_id in player_ids:
		var id := int(peer_id)
		if str(roles.get(id, "")).to_lower() != survivor_team_name.to_lower():
			continue
		survivor_count += 1
		var player := NetworkManager.get_player(id)
		if player == null or not is_instance_valid(player):
			return ""
		var dead_value: Variant = player.get("is_dead")
		if not (dead_value is bool and dead_value):
			survivor_alive = true
	if survivor_count == 0 or not survivor_alive:
		return murder_team_name
	return ""
