extends CanvasLayer

@onready var root: Control = $Root
@onready var round_timer: Label = $Root/RoundTimerPanel/RoundTimer
@onready var fps_panel: Panel = $Root/FPSPanel
@onready var fps_label: Label = $Root/FPSPanel/Label

func _ready():
	_apply_local_visibility()
	round_timer.visible = false
	
	if Settings.check_option("show_fps"):
		fps_panel.visible = true
	else:
		fps_panel.visible = false

func _process(_delta: float):
	_apply_local_visibility()
	if not visible:
		return
		
	if fps_panel.visible:
		fps_label.text = str(Engine.get_frames_per_second())
	
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

func set_round_elapsed(value: float):
	if value < 0.0:
		round_timer.visible = false
		return
	round_timer.visible = true
	var total_seconds := int(value)
	var minutes := total_seconds / 60
	var seconds := total_seconds % 60
	round_timer.text = "%02d:%02d" % [minutes, seconds]
