extends Node2D

const PLAYER_SCENE := preload("res://prefabs/player.tscn")
const HOLES_SCRIPT := preload("res://scripts/menu/corpse_holes.gd")

var rng := RandomNumberGenerator.new()
var wave_remaining := 0

func _ready() -> void:
	top_level = true
	rng.randomize()
	_spawn_wave()

func _spawn_wave() -> void:
	if not is_inside_tree():
		return
	var count := rng.randi_range(1, 4)
	wave_remaining = count
	for i in range(count):
		_spawn_corpse(i, count)

func _spawn_corpse(index: int, count: int) -> void:
	var player := PLAYER_SCENE.instantiate()
	var visuals := player.get_node_or_null("BodyVisuals") as Node2D
	if visuals == null:
		player.free()
		wave_remaining -= 1
		if wave_remaining <= 0:
			call_deferred("_spawn_wave")
		return
	player.remove_child(visuals)
	visuals.top_level = false
	_clear_scene_owners(visuals)
	player.free()

	var corpse := Node2D.new()
	corpse.name = "MenuCorpse"
	corpse.top_level = true
	corpse.z_index = -1
	corpse.add_child(visuals)
	visuals.position = Vector2.ZERO
	visuals.rotation = rng.randf_range(-0.2, 0.2)
	var torso := visuals.get_node_or_null("Torso") as Node2D
	var head := visuals.get_node_or_null("Head") as Node2D
	var left_shoulder := visuals.get_node_or_null("Hands/LeftShoulder") as Node2D
	var right_shoulder := visuals.get_node_or_null("Hands/RightShoulder") as Node2D
	if torso != null:
		torso.rotation = rng.randf_range(-0.28, 0.28)
	if head != null:
		head.rotation = rng.randf_range(-0.4, 0.4)
	if left_shoulder != null:
		left_shoulder.rotation = rng.randf_range(-0.65, 0.65)
	if right_shoulder != null:
		right_shoulder.rotation = rng.randf_range(-0.65, 0.65)
	var wounds := Node2D.new()
	wounds.name = "RandomWounds"
	wounds.set_script(HOLES_SCRIPT)
	visuals.add_child(wounds)
	add_child(corpse)

	var viewport_size := get_viewport_rect().size
	var visible_left := viewport_size.x * 0.2
	var visible_right := viewport_size.x * 0.98
	var spawn_x := rng.randf_range(visible_left, visible_right)
	var spread := (float(index) - float(count - 1) * 0.5) * rng.randf_range(20.0, 65.0)
	var start_screen := Vector2(clampf(spawn_x + spread, 16.0, viewport_size.x - 16.0), -90.0 - rng.randf_range(0.0, 80.0))
	var end_screen := Vector2(clampf(start_screen.x + rng.randf_range(-70.0, 70.0), 16.0, viewport_size.x - 16.0), viewport_size.y + 110.0)
	corpse.position = start_screen
	corpse.rotation = rng.randf_range(-0.3, 0.3)
	var duration := rng.randf_range(6.0, 10.0)
	var tween := create_tween()
	var fall := tween.tween_property(corpse, "position", end_screen, duration)
	fall.set_trans(Tween.TRANS_CUBIC)
	fall.set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(corpse, "rotation", corpse.rotation + rng.randf_range(-1.3, 1.3), duration)
	tween.finished.connect(_on_corpse_finished.bind(corpse))

func _on_corpse_finished(corpse: Node2D) -> void:
	if is_instance_valid(corpse):
		corpse.queue_free()
	wave_remaining -= 1
	if wave_remaining <= 0:
		call_deferred("_spawn_wave")

func _clear_scene_owners(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		_clear_scene_owners(child)
