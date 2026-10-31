extends Control

@onready var dots_effect: ColorRect = $DotsEffect
@export var next_scene_path: String = "res://scenes/menu.tscn"

func _ready() -> void:
	var mat = dots_effect.material as ShaderMaterial
	if not mat:
		push_error()
		return

	mat.set_shader_parameter("progress", 1.0)
	var tween = create_tween()
	
	tween.tween_property(mat, "shader_parameter/progress", 0.0, 1.5)\
		.set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_OUT)
	tween.tween_interval(1)
	tween.finished.connect(_change_scene)

func _change_scene() -> void:
	if ResourceLoader.exists(next_scene_path):
		get_tree().change_scene_to_file(next_scene_path)
	else:
		push_error()
