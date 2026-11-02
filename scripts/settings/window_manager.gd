extends Node
class_name WindowManager

const OPTION_WINDOW_MODE := "window_mode"
var rep := Reporter.new("WindowManager")

func _ready() -> void:
	await get_tree().process_frame
	apply_window_settings()

static func apply_window_settings() -> void:
	var mode: String = Settings.check_option(OPTION_WINDOW_MODE)
	
	match mode:
		"window":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func change_window_mode(new_mode: String) -> void:
	if new_mode in ["window", "borderless", "fullscreen"]:
		Settings.set_option(OPTION_WINDOW_MODE, new_mode)
		apply_window_settings()
	else:
		rep.error("Window: Unknown window mode: " + new_mode)
