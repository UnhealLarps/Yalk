extends Node2D

const MENU_SCENE_PATH := "res://scenes/menu.tscn"

@export var pause_layer: CanvasLayer
@export var input_action: StringName = &"cancel"

var resume_button: Button
var disconnect_button: Button
var exit_button: Button

func _ready() -> void:
	if pause_layer == null:
		pause_layer = get_node_or_null("CanvasLayer") as CanvasLayer
	if pause_layer == null:
		push_error("PauseMenu requires a CanvasLayer assigned to pause_layer.")
		return
	resume_button = pause_layer.find_child("Resume", true, false) as Button
	disconnect_button = pause_layer.find_child("Disconnect", true, false) as Button
	if resume_button == null or disconnect_button == null:
		push_error("PauseMenu CanvasLayer requires ResumeButton and DisconnectButton.")
		return
	resume_button.pressed.connect(_resume)
	disconnect_button.pressed.connect(_disconnect_to_menu)
	pause_layer.visible = false

func _input(event: InputEvent) -> void:
	if pause_layer == null or not event.is_action_pressed(input_action) or event.is_echo():
		return
	var current_scene := get_tree().current_scene
	var chat_layer := current_scene.find_child("Chat", true, false) if current_scene != null else null
	if chat_layer != null and chat_layer.get("chat_open") == true:
		return
	var focused_control := get_viewport().gui_get_focus_owner()
	if focused_control is LineEdit or focused_control is TextEdit:
		return
	_set_menu_visible(not pause_layer.visible)
	get_viewport().set_input_as_handled()

func _set_menu_visible(value: bool) -> void:
	pause_layer.visible = value
	get_viewport().gui_release_focus()
	if value:
		resume_button.grab_focus()

func _resume() -> void:
	_set_menu_visible(false)

func _disconnect_to_menu() -> void:
	pause_layer.visible = false
	NetworkManager.disconnect_network()
	get_tree().call_deferred("change_scene_to_file", MENU_SCENE_PATH)
