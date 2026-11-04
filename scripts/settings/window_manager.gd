extends Node
class_name WindowManager

const OPTION_WINDOW_MODE := "window_mode"
const OPTION_RESOLUTION := "resolution"
const OPTION_VSYNC := "vsync"
const DEFAULT_RESOLUTION := Vector2i(1152, 648)
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(640, 360),
	Vector2i(720, 405),
	Vector2i(800, 450),
	Vector2i(960, 540),
	Vector2i(1024, 576),
	Vector2i(1152, 648),
	Vector2i(1280, 720),
	Vector2i(1360, 765),
	Vector2i(1366, 768),
	Vector2i(1440, 810),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2048, 1152),
	Vector2i(2560, 1440),
	Vector2i(3200, 1800),
	Vector2i(3840, 2160),
	Vector2i(800, 600),
	Vector2i(1024, 768),
	Vector2i(1280, 960),
	Vector2i(1600, 1200),
	Vector2i(1920, 1440),
	Vector2i(1280, 800),
	Vector2i(1440, 900),
	Vector2i(1680, 1050),
	Vector2i(1920, 1200),
	Vector2i(2560, 1600),
	Vector2i(2560, 1080),
	Vector2i(3440, 1440),
	Vector2i(5120, 2160),
]

var rep := Reporter.new("WindowManager")

func _ready() -> void:
	await get_tree().process_frame
	apply_window_settings()

static func apply_window_settings() -> void:
	var mode := str(Settings.check_option(OPTION_WINDOW_MODE))
	var resolution := _get_saved_resolution()
	var vsync_enabled := bool(Settings.check_option(OPTION_VSYNC))

	if mode == "fullscreen":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, mode == "borderless")
		DisplayServer.window_set_size(resolution)
		_center_window(resolution)

	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED)

static func _get_saved_resolution() -> Vector2i:
	var value := str(Settings.check_option(OPTION_RESOLUTION))
	var parts := value.split("x")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return DEFAULT_RESOLUTION

	var resolution := Vector2i(parts[0].to_int(), parts[1].to_int())
	if resolution.x < 320 or resolution.y < 180:
		return DEFAULT_RESOLUTION
	return resolution

static func _center_window(resolution: Vector2i) -> void:
	var screen := DisplayServer.window_get_current_screen()
	var screen_position := DisplayServer.screen_get_position(screen)
	var screen_size := DisplayServer.screen_get_size(screen)
	var position := screen_position + Vector2i(maxi((screen_size.x - resolution.x) / 2, 0), maxi((screen_size.y - resolution.y) / 2, 0))
	DisplayServer.window_set_position(position)

func change_window_mode(new_mode: String) -> void:
	if new_mode in ["window", "borderless", "fullscreen"]:
		Settings.set_option(OPTION_WINDOW_MODE, new_mode)
		apply_window_settings()
	else:
		rep.error("Window: Unknown window mode: " + new_mode)
