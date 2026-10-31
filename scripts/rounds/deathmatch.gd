extends Resource

var mode_id := "deathmatch"
var mode_name := "Deathmatch"
var description := "Every fighter receives a random weapon. Be the last one standing."
var image: Texture2D = preload("res://sprites/ui/rounds/deathmatch.png")
var music_path := "res://audio/music/rounds/leberch-dark-cinematic.mp3"
var teams := [
	{"name": "Fighter", "percentage": 100.0, "items": ["", ""]}
]
var outlines: Array[Dictionary] = []
var available_weapons := [
	"res://prefabs/weapons/pistols/glock17.tscn",
	"res://prefabs/weapons/pistols/rifle.tscn"
]

func assign_roles(player_ids: Array[int]) -> Dictionary:
	var result: Dictionary = {}
	for peer_id in player_ids:
		result[peer_id] = "Fighter"
	return result

func get_team(team_name: String) -> Dictionary:
	for team_value in teams:
		if team_value is Dictionary and str(team_value.get("name", "")) == team_name:
			return team_value.duplicate(true)
	return {}

func get_items_for_player(_peer_id: int, _team_name: String) -> Array[String]:
	var weapons: Array[String] = []
	for path in available_weapons:
		if ResourceLoader.exists(path):
			weapons.append(str(path))
	if weapons.is_empty():
		return ["", ""]
	return [weapons.pick_random(), ""]

func get_winner(player_ids: Array[int], roles: Dictionary) -> String:
	var alive_players: Array[int] = []
	for peer_id in player_ids:
		var id := int(peer_id)
		var player := NetworkManager.get_player(id)
		if player == null or not is_instance_valid(player):
			continue
		if player.get("is_dead") != true:
			alive_players.append(id)
	if alive_players.size() > 1:
		return ""
	if alive_players.size() == 1:
		return NicknameManager.get_nickname(alive_players[0])
	return "Nobody"
