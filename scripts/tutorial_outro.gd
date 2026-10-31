extends Area2D

const MENU_SCENE_PATH := "res://scenes/menu.tscn"

var transition_started := false

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(_body: Node2D) -> void:
	if transition_started:
		return
	transition_started = true
	set_deferred("monitoring", false)
	call_deferred("_return_to_menu")

func _return_to_menu() -> void:
	var error := get_tree().change_scene_to_file(MENU_SCENE_PATH)
	if error != OK:
		push_error("Could not return to menu: %s" % error_string(error))
