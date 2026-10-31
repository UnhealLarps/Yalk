extends CanvasLayer

@onready var root: Control = $Root
@onready var round_timer: Label = $Root/RoundTimerPanel/RoundTimer

func _ready():
	_apply_local_visibility()
	_set_timer_color()
	round_timer.visible = false

func _process(_delta: float):
	_apply_local_visibility()
	if not visible:
		return
	_set_timer_color()
	var manager: Node = NetworkManager.round_manager
	if manager == null or not is_instance_valid(manager) or not manager.has_method("is_round_playing") or not manager.call("is_round_playing"):
		set_round_elapsed(-1.0)
		return
	var elapsed: Variant = manager.get("round_elapsed")
	if elapsed is int or elapsed is float:
		set_round_elapsed(float(elapsed))

func _apply_local_visibility():
	var player := get_parent()
	visible = player != null and is_instance_valid(player) and player.get("local_player") == true

func _set_timer_color():
	if not is_instance_valid(round_timer):
		return
	round_timer.add_theme_color_override("font_color", Color.WHITE)
	round_timer.modulate = Color.WHITE
	round_timer.self_modulate = Color.WHITE
	root.modulate = Color.WHITE
	root.self_modulate = Color.WHITE

func set_round_elapsed(value: float):
	if value < 0.0:
		round_timer.visible = false
		return
	_set_timer_color()
	round_timer.visible = true
	var total_seconds := int(value)
	var minutes := total_seconds / 60
	var seconds := total_seconds % 60
	round_timer.text = "%02d:%02d" % [minutes, seconds]
