extends CanvasLayer

const MENU_SCENE_PATH := "res://scenes/menu.tscn"

@export var input_action: StringName = &"cancel"

var resume_button: Button
var settings_button: Button
var disconnect_button: Button
var exit_button: Button

var settings_window: Window

func _ready() -> void:
	resume_button = find_child("Resume", true, false) as Button
	settings_button = find_child("Settings", true, false) as Button
	disconnect_button = find_child("Disconnect", true, false) as Button
	
	settings_window = find_child("SettingsMenu", true, false) as Window

	resume_button.pressed.connect(_resume)
	settings_button.pressed.connect(_on_settings_pressed)
	disconnect_button.pressed.connect(_disconnect_to_menu)
	
	visible = false
	settings_window.visible = false

func _input(event: InputEvent) -> void:
	if not event.is_action_pressed(input_action) or event.is_echo():
		return
		
	if settings_window.visible:
		settings_window.hide()
		get_viewport().set_input_as_handled()
		return

	var current_scene := get_tree().current_scene
	var chat_layer := current_scene.find_child("Chat", true, false) if current_scene != null else null
	if chat_layer != null and chat_layer.get("chat_open") == true:
		return
	var focused_control := get_viewport().gui_get_focus_owner()
	if focused_control is LineEdit or focused_control is TextEdit:
		return
		
	_set_menu_visible(not visible)
	get_viewport().set_input_as_handled()

func _set_menu_visible(value: bool) -> void:
	visible = value
	get_viewport().gui_release_focus()
	if value:
		resume_button.grab_focus()
	else:
		settings_window.hide()

func _resume() -> void:
	_set_menu_visible(false)

func _on_settings_pressed() -> void:
	settings_window.popup_centered()

func _disconnect_to_menu() -> void:
	visible = false
	NetworkManager.disconnect_network()
	get_tree().call_deferred("change_scene_to_file", MENU_SCENE_PATH)
