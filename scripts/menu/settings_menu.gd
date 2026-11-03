extends Window

@onready var window_mode_button: OptionButton = %WindowModeButton
@onready var show_fps_check: CheckBox = %ShowFpsCheck
@onready var master_slider: HSlider = %MasterSlider

@onready var reset_button: Button = %ResetButton
@onready var apply_button: Button = %ApplyButton
@onready var close_button: Button = %CloseButton

func _ready() -> void:
	reset_button.pressed.connect(_on_reset_pressed)
	apply_button.pressed.connect(_on_apply_pressed)
	close_button.pressed.connect(_on_close_pressed)
	close_requested.connect(_on_close_pressed)
	master_slider.value_changed.connect(_on_master_volume_changed)
	
	update_ui_from_settings()

func update_ui_from_settings() -> void:
	var current_mode: String = Settings.check_option("window_mode")
	match current_mode:
		"window": window_mode_button.selected = 0
		"borderless": window_mode_button.selected = 1
		"fullscreen": window_mode_button.selected = 2
		
	show_fps_check.button_pressed = Settings.check_option("show_fps")

	var vol = Settings.check_option("master_volume")
	master_slider.value = vol if vol != null else 100.0
	_apply_audio_volume(master_slider.value)

func _on_apply_pressed() -> void:
	var mode_string := "window"
	match window_mode_button.selected:
		0: mode_string = "window"
		1: mode_string = "borderless"
		2: mode_string = "fullscreen"
	
	Settings.set_option("window_mode", mode_string)
	WindowManager.apply_window_settings()
	Settings.set_option("show_fps", show_fps_check.button_pressed)
	Settings.set_option("master_volume", master_slider.value)
	Settings.save_settings()

func _on_master_volume_changed(value: float) -> void:
	_apply_audio_volume(value)

func _apply_audio_volume(percent: float) -> void:
	var bus_index = AudioServer.get_bus_index("Master")
	if bus_index != -1:
		if percent <= 0:
			AudioServer.set_bus_mute(bus_index, true)
		else:
			AudioServer.set_bus_mute(bus_index, false)
			var db_value = linear_to_db(percent / 100.0)
			AudioServer.set_bus_volume_db(bus_index, db_value)

func _on_reset_pressed() -> void:
	Settings.reset_settings()
	WindowManager.apply_window_settings()
	update_ui_from_settings()

func _on_close_pressed() -> void:
	hide()
