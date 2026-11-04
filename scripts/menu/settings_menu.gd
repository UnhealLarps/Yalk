extends Window

@onready var window_mode_button: OptionButton = %WindowModeButton
@onready var resolution_button: OptionButton = %ResolutionButton
@onready var vsync_check: CheckBox = %VSyncCheck
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
	window_mode_button.item_selected.connect(_on_window_mode_selected)
	_populate_resolution_options()
	update_ui_from_settings()

func _populate_resolution_options() -> void:
	resolution_button.clear()
	for resolution: Vector2i in WindowManager.RESOLUTIONS:
		var label := "%d × %d" % [resolution.x, resolution.y]
		resolution_button.add_item(label)
		resolution_button.set_item_metadata(resolution_button.item_count - 1, "%dx%d" % [resolution.x, resolution.y])

func update_ui_from_settings() -> void:
	var current_mode: String = str(Settings.check_option("window_mode"))
	match current_mode:
		"window": window_mode_button.select(0)
		"borderless": window_mode_button.select(1)
		"fullscreen": window_mode_button.select(2)

	var current_resolution := str(Settings.check_option("resolution"))
	var resolution_index := 0
	for index in range(resolution_button.item_count):
		if str(resolution_button.get_item_metadata(index)) == current_resolution:
			resolution_index = index
			break
	resolution_button.select(resolution_index)
	resolution_button.disabled = current_mode == "fullscreen"
	vsync_check.button_pressed = bool(Settings.check_option("vsync"))
	show_fps_check.button_pressed = bool(Settings.check_option("show_fps"))

	var vol = Settings.check_option("master_volume")
	master_slider.value = vol if vol != null else 100.0
	_apply_audio_volume(master_slider.value)

func _on_window_mode_selected(index: int) -> void:
	resolution_button.disabled = index == 2

func _on_apply_pressed() -> void:
	var mode_string := "window"
	match window_mode_button.selected:
		0: mode_string = "window"
		1: mode_string = "borderless"
		2: mode_string = "fullscreen"

	var resolution_string := str(resolution_button.get_item_metadata(resolution_button.selected))
	Settings.set_option("window_mode", mode_string)
	Settings.set_option("resolution", resolution_string)
	Settings.set_option("vsync", vsync_check.button_pressed)
	Settings.set_option("show_fps", show_fps_check.button_pressed)
	Settings.set_option("master_volume", master_slider.value)
	WindowManager.apply_window_settings()
	Settings.save_settings()

func _on_master_volume_changed(value: float) -> void:
	_apply_audio_volume(value)

func _apply_audio_volume(percent: float) -> void:
	var bus_index := AudioServer.get_bus_index("Master")
	if bus_index != -1:
		if percent <= 0:
			AudioServer.set_bus_mute(bus_index, true)
		else:
			AudioServer.set_bus_mute(bus_index, false)
			var db_value := linear_to_db(percent / 100.0)
			AudioServer.set_bus_volume_db(bus_index, db_value)

func _on_reset_pressed() -> void:
	Settings.reset_settings()
	WindowManager.apply_window_settings()
	update_ui_from_settings()

func _on_close_pressed() -> void:
	hide()
