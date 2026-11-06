extends Node

const HEART_ORGAN := 0

@export var area: Area2D

func _ready():
	if area == null:
		return
	var server_authority := NetworkManager.is_server_authority()
	area.collision_layer = 0
	area.collision_mask = 2
	area.monitoring = server_authority
	area.monitorable = server_authority
	for child in area.get_children():
		if child is CollisionPolygon2D:
			(child as CollisionPolygon2D).disabled = not server_authority
		elif child is CollisionShape2D:
			(child as CollisionShape2D).disabled = not server_authority
	if not area.body_entered.is_connected(_on_body_entered):
		area.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D):
	if not NetworkManager.is_server_authority() or not body is CharacterBody2D:
		return
	var player := body as CharacterBody2D
	if player.get_node_or_null("UltraViolence") == null:
		return
	if player.get("is_dead") == true:
		return
	var violence := player.get_node("UltraViolence")
	if violence.get("is_dead") == true or not violence.has_method("apply_organ_hit"):
		return
	var peer_id := int(player.get("network_player_id"))
	var round_manager_value: Variant = NetworkManager.get("round_manager")
	if round_manager_value is Node and round_manager_value.has_method("is_player_active"):
		if not round_manager_value.call("is_player_active", peer_id):
			return
	violence.call("apply_organ_hit", HEART_ORGAN, player.global_position, Vector2.UP)
